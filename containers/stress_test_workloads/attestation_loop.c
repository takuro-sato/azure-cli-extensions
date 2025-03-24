/* Copyright (c) Microsoft Corporation.
   Licensed under the MIT License. */

#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <memory.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <pthread.h>
#include <stdatomic.h>

#include "snp-attestation.h"
#include "snp-ioctl6.h"

static atomic_uint_fast64_t report_ops_count = 0;
static atomic_uint_fast64_t derive_ops_count = 0;
static unsigned char last_derived_key[32];

int deriveKey(int sev_guest_fd, union snp_derived_key_resp *key_out)
{
    // DERIVE_KEY_KEYSELECT:
    // From SEV-SNP Firmware ABI Specification Table 19:
    // Bits     Field           Description
    // 31:3                     Reserved must be 0.
    // 2:1      KEY_SEL         Selects which key to use for derivation. 0: If VLEK is installed, derive with VLEK. Otherwise, derive with VCEK.
    //                                                                   1: Derive with VCEK.
    //                                                                   2: Derive with VLEK.
    //                                                                   3: Reserved.
    // 0        ROOT_KEY_SELECT Selects the root key from which to derive the key. 0 indicates VCEK. 1 indicates VMRK.

    // Derive the key using the VCEK (as opposed to VLEK / VMRK which aren't used in Azure).
    // The Versioned Chip Endorsement Key (VCEK) is an attestation signing key derived from chip unique secrets and a TCB_VERSION
    static int DERIVE_KEY_KEYSELECT = 0x1;

    // DERIVE_KEY_GUEST_FIELD_SELECT:
    // From SEV-SNP Firmware ABI Specification Table 20:
    // Bits     Field           Description
    // 64:6                     Reserved must be 0.
    // 5        TCB_VERSION     Indicates that the guest-provided TCB_VERSION will be mixed into the key.
    // 4        GUEST_SVN       Indicates that the guest-provided SVN will be mixed into the key.
    // 3        MEASUREMENT     Indicates the measurement of the guest during launch will be mixed into the key.
    // 2        FAMILY_ID       Indicates the family ID of the guest will be mixed into the key.
    // 1        IMAGE_ID        Indicates that the image ID of the guest will be mixed into the key.
    // 0        GUEST_POLICY    Indicates that the guest policy will be mixed into the key.
    // Include host data and launch measurement so only an ACI container group with the same UVM image and CCE policy can derive the same key.
    static int DERIVE_KEY_GUEST_FIELD_SELECT = 0x8;

    struct snp_derived_key_req msg_key_request_in = {};
    msg_key_request_in.root_key_select = DERIVE_KEY_KEYSELECT;
    msg_key_request_in.guest_field_select = DERIVE_KEY_GUEST_FIELD_SELECT;
    msg_key_request_in.vmpl = 0;        // VMPL isn't used in Azure (must be >= current VMPL).
    msg_key_request_in.guest_svn = 0;   // Don't set a guest SVN to mix in (must be <= version supplied at launch).
    msg_key_request_in.tcb_version = 0; // Don't set a TCB version to mix in (must be <= CommittedTcb).

    snp_guest_request_ioctl ioctl_request = {};
    ioctl_request.msg_version = 1;
    ioctl_request.req_data = (uint64_t)&msg_key_request_in;
    ioctl_request.resp_data = (uint64_t)key_out;
    int rc = ioctl(sev_guest_fd, SNP_GET_DERIVED_KEY, &ioctl_request);
    if (rc < 0)
    {
        printf("ERROR: Failed to issue ioctl SNP_GET_DERIVED_KEY: %d (%s)\n", errno, strerror(errno));
        return -1;
    }
    if (key_out->status != 0)
    {
        printf("ERROR: Failed to derive key: status = 0x%08x\n", key_out->status);
        return -1;
    }
    return 0;
}

void *fetchAttestationReport6Loop(void *_t)
{
    int fd = open("/dev/sev-guest", O_RDWR | O_CLOEXEC);
    if (fd < 0)
    {
        fprintf(stderr, "Failed to open /dev/sev-guest\n");
        exit(-1);
        return NULL;
    }

    snp_report_req snp_request;
    snp_report_resp snp_response;
    snp_guest_request_ioctl ioctl_request;

    memset(&snp_request, 0, sizeof(snp_request));
    memset(snp_request.report_data, 0, sizeof(snp_request.report_data));

    memset(&snp_response, 0, sizeof(snp_response));
    memset(&ioctl_request, 0, sizeof(ioctl_request));

    ioctl_request.msg_version = 1;
    ioctl_request.req_data = (uint64_t)&snp_request;
    ioctl_request.resp_data = (uint64_t)&snp_response;

    while (1)
    {
        int rc = ioctl(fd, SNP_GET_REPORT, &ioctl_request);
        if (rc < 0)
        {
            printf("ERROR: Failed to issue ioctl SNP_GET_REPORT: %d (%s)\n", errno, strerror(errno));
            exit(-1);
            return NULL;
        }
        atomic_fetch_add_explicit(&report_ops_count, 1, memory_order_relaxed);
    }
}

void *deriveKeyLoop(void *_t)
{
    int fd = open("/dev/sev-guest", O_RDWR | O_CLOEXEC);
    if (fd < 0)
    {
        fprintf(stderr, "Failed to open /dev/sev-guest\n");
        exit(-1);
        return NULL;
    }

    union snp_derived_key_resp *derive_key_out;
    derive_key_out = (union snp_derived_key_resp *)malloc(sizeof(union snp_derived_key_resp));
    if (derive_key_out == NULL)
    {
        abort();
        exit(-1);
        return NULL;
    }

    while (1)
    {
        memset(derive_key_out, 0, sizeof(union snp_derived_key_resp));
        int rc = deriveKey(fd, derive_key_out);
        if (rc < 0)
        {
            exit(-1);
            return NULL;
        }
        memcpy(last_derived_key, derive_key_out->key, sizeof(last_derived_key));
        atomic_fetch_add_explicit(&derive_ops_count, 1, memory_order_relaxed);
    }
}

int main(int argc, char *argv[])
{
    setbuf(stdout, NULL);
    const int derive_thr_count = 8;
    const int attest_thr_count = 8;
    pthread_t reportThread[attest_thr_count], deriveThreads[derive_thr_count];

    for (int i = 0; i < attest_thr_count; i++)
    {
        if (pthread_create(&reportThread[i], NULL, fetchAttestationReport6Loop, NULL) != 0)
        {
            fprintf(stderr, "Failed to create fetchAttestationReport6Loop thread\n");
            return -1;
        }
    }
    for (int i = 0; i < derive_thr_count; i++)
    {
        if (pthread_create(&deriveThreads[i], NULL, deriveKeyLoop, NULL) != 0)
        {
            fprintf(stderr, "Failed to create deriveKeyLoop thread\n");
            return -1;
        }
    }

    // Status printing loop in main thread
    struct timespec last_print, now;
    clock_gettime(CLOCK_MONOTONIC, &last_print);
    unsigned long last_report_count = 0;
    unsigned long last_derive_count = 0;

    while (true)
    {
        sleep(5);
        clock_gettime(CLOCK_MONOTONIC, &now);
        double elapsed = (now.tv_sec - last_print.tv_sec) + (now.tv_nsec - last_print.tv_nsec) / 1e9;

        unsigned long current_report_count = atomic_load_explicit(&report_ops_count, memory_order_relaxed);
        unsigned long current_derive_count = atomic_load_explicit(&derive_ops_count, memory_order_relaxed);

        unsigned long report_diff = current_report_count - last_report_count;
        unsigned long derive_diff = current_derive_count - last_derive_count;
        last_report_count = current_report_count;
        last_derive_count = current_derive_count;

        double report_rate = report_diff / elapsed;
        double derive_rate = derive_diff / elapsed;

        printf("Reports: %lu total (%0.1f/s) | Derive Keys: %lu total (%0.1f/s)\n",
               current_report_count, report_rate, current_derive_count, derive_rate);

        if (current_derive_count > 0)
        {
            printf("Last key = %02x%02x%02x%02x%02x%02x%02x%02x...\n",
                   last_derived_key[0], last_derived_key[1], last_derived_key[2], last_derived_key[3],
                   last_derived_key[4], last_derived_key[5], last_derived_key[6], last_derived_key[7]);
        }

        last_report_count = current_report_count;
        last_derive_count = current_derive_count;
        last_print = now;
    }
}
