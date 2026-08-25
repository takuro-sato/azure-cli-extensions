// Container group that mounts a native-ACI ElasticSAN (ESAN) volume over a
// bring-your-own VNet, using a user-assigned managed identity to resolve the iSCSI
// target.
//
// The confidential flag selects between the two variants that share this workload:
//   confidential = true  -> Confidential Linux (C-LCOW): sku 'Confidential' +
//                           confidentialComputeProperties (SevSnp) + CCE policy.
//   confidential = false -> standard (non-confidential) Linux: none of the above.
// Note: at the time of writing the non-confidential cplat data-plane does not support
// native ESAN volumes, so the confidential = false deployment is expected to fail at
// runtime; it is included so the gap is exercised and tracked once support lands.
//
// The API version is pinned to 2025-09-01, which ARM reports as supported for the
// target region and whose types include the elasticSan volume type and
// confidentialComputeProperties.isolationType.

param location string

// Confidential (C-LCOW) when true, standard non-confidential Linux when false.
param confidential bool = true

// CCE policy map; only referenced (and required) when confidential is true.
param ccePolicies object = {}

param registry string
param repository string
param tag string = ''

param cpu int = 4
param memoryInGb int = 8

// ESAN volume, managed identity and BYO-VNet subnet are fixed cross-subscription
// resources (see esan.bicepparam), so they are passed as full resource IDs rather than
// resolved with resourceId() against the deployment's own subscription/resource group.
param elasticSanVolumeResourceId string
param managedIdentityResourceId string
param managedIdentityClientId string
param subnetResourceId string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2025-09-01' = {
  name: deployment().name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {}
    }
  }
  properties: {
    osType: 'Linux'
    sku: confidential ? 'Confidential' : null
    restartPolicy: 'OnFailure'
    subnetIds: [{ id: subnetResourceId }]
    confidentialComputeProperties: confidential
      ? {
          isolationType: 'SevSnp'
          ccePolicy: ccePolicies.esan
        }
      : null
    containers: [
      {
        name: 'primary'
        properties: {
          image: '${empty(registry) ? 'mcr.microsoft.com/mirror/docker/library' : registry}/${empty(repository) ? 'ubuntu' : repository}:${empty(tag) ? '24.04' : tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          volumeMounts: [
            {
              name: 'esanvol'
              mountPath: '/mnt/esan'
            }
          ]
          command: [
            '/bin/bash'
            '-c'
            '''
            set +e
            CMD_START=$(date +%s.%N)   # high-res start so a sub-second connection time is measurable

            echo '=== ESAN clcow PERFBENCH (native ACI ESAN volume, no sidecar, no hack) ==='
            echo "date: $(date -u)  (command-start epoch=${CMD_START})"

            # Is /mnt/esan the genuine native-ACI ElasticSAN block volume, or just the
            # scratch disk bound in as a placeholder?
            #
            # The volume can be STACKED at the same path: ACI first binds a scratch
            # placeholder at /mnt/esan and then, once the iSCSI target is resolved, mounts
            # the real ESAN block device ON TOP of it. Two mounts then share the path and
            # only the TOPMOST (last) one is what the container actually reads/writes. We
            # resolve the EFFECTIVE mount from /proc/self/mountinfo (authoritative and
            # mount-ordered; the last entry for the path wins) and judge only that one,
            # with size- and device-name-independent signals:
            #   (1) /mnt/esan is a mountpoint at all.
            #   (2) the effective fs is a real on-disk fs (not overlay/tmpfs/...) on /dev.
            #   (3) the effective mount is a WHOLE device (mountinfo root "/"), not a bind
            #       of a scratch subdirectory.
            #   (4) the effective device (major:minor) differs from the container root AND
            #       from a known scratch-backed path (/etc/hostname is bound from scratch).
            #   (5) it is actually writable, proven with a probe file.
            is_real_esan() {
              m=/mnt/esan
              mi=/proc/self/mountinfo
              mountpoint -q "$m" 2>/dev/null || return 1
              [ -r "$mi" ] || return 1

              # Effective (topmost) mount at exactly $m = last matching line in mountinfo.
              # mountinfo fields: 3=major:minor 4=root 5=mountpoint ... " - " fstype source superopts
              eff_mm=$(awk -v t="$m" '$5==t{v=$3} END{print v}' "$mi")
              eff_root=$(awk -v t="$m" '$5==t{v=$4} END{print v}' "$mi")
              eff_fs=$(awk -v t="$m" '$5==t{for(i=7;i<=NF;i++)if($i=="-"){v=$(i+1);break}} END{print v}' "$mi")
              eff_src=$(awk -v t="$m" '$5==t{for(i=7;i<=NF;i++)if($i=="-"){v=$(i+2);break}} END{print v}' "$mi")
              root_mm=$(awk '$5=="/"{v=$3} END{print v}' "$mi")
              scr_mm=$(awk '$5=="/etc/hostname"{v=$3} END{print v}' "$mi")

              [ -n "$eff_mm" ] || return 1                                       # (1) something is mounted
              case "$eff_fs" in overlay|tmpfs|ramfs|devtmpfs|"") return 1;; esac # (2a) real on-disk fs only
              case "$eff_src" in /dev/*) : ;; *) return 1;; esac                 # (2b) backed by a /dev block device
              [ "$eff_root" = "/" ] || return 1                                  # (3) whole device, not a bind subdir
              [ "$eff_mm" != "$root_mm" ] || return 1                            # (4a) not the root device
              [ -z "$scr_mm" ] || [ "$eff_mm" != "$scr_mm" ] || return 1         # (4b) not the scratch device
              probe="$m/.esan-probe.$$"                                          # (5) writable
              ( : > "$probe" ) 2>/dev/null || return 1
              rm -f "$probe" 2>/dev/null
              return 0
            }

            echo '--- waiting up to 180s for /mnt/esan to be a REAL esan device (poll every 1s so the connection time is measured finely; distinct whole-device block volume; effective/topmost mount, not a bind onto scratch) ---'
            MOUNT_READY=""
            for i in $(seq 1 180); do
              if is_real_esan; then
                MOUNT_READY=$(date +%s.%N)
                echo "[t=${i}s] /mnt/esan is a REAL esan mount"
                break
              fi
              echo "[t=${i}s] not-real-esan :: src=$(findmnt -nlo SOURCE /mnt/esan 2>/dev/null) :: $(df -h /mnt/esan 2>/dev/null | tail -1)"
              sleep 1
            done

            echo '--- df -h /mnt/esan ---'
            df -h /mnt/esan

            echo '--- mount | grep esan ---'
            (mount | grep esan || echo '(no esan mount line)')

            echo '--- findmnt /mnt/esan ---'
            (findmnt /mnt/esan || echo '(findmnt: nothing at /mnt/esan)')

            echo '--- lsblk ---'
            (lsblk || true)

            echo '--- VERDICT ---'
            if is_real_esan; then
              echo 'VERDICT: REAL ESAN volume mounted (distinct whole-device block volume; effective/topmost mount, not the scratch bind)'
            else
              echo 'VERDICT: NOT esan -- /mnt/esan is a bind onto the scratch disk; data is EPHEMERAL, not persisted to ESAN'
            fi

            # Quick diagnostics — only when esan is NOT present. Answers "why is there no
            # ESAN block device in the guest?" (iSCSI LUN never attached => nothing to mount).
            if ! is_real_esan; then
              echo '=== DIAG (esan not present; quick block/iscsi/kernel diag) ==='
              echo '--- /proc/partitions ---'
              cat /proc/partitions
              echo '--- lsblk -f ---'
              (lsblk -o NAME,MAJ:MIN,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null || true)
              echo '--- all mounts (findmnt -A) ---'
              (findmnt -A 2>/dev/null || cat /proc/mounts)
              echo '--- blkid ---'
              (blkid 2>/dev/null || echo '(none)')
              echo '--- iscsi sessions ---'
              (command -v iscsiadm >/dev/null && iscsiadm -m session 2>&1 || echo '(iscsiadm not present in this container)')
              echo '--- scsi devices (/proc/scsi/scsi) ---'
              (cat /proc/scsi/scsi 2>/dev/null || echo '(none)')
              echo '--- device-mapper ---'
              (ls -la /dev/mapper 2>/dev/null; command -v dmsetup >/dev/null && dmsetup ls 2>&1 || true)
              echo '--- esan-related env ---'
              (env | grep -iE 'esan|volume|mount' || true)
              echo '--- dmesg (scsi/iscsi/dm/xfs/esan/err) ---'
              (dmesg 2>/dev/null | grep -iE 'scsi|iscsi|multipath|dm-|device-mapper|xfs|esan|elastic|error|fail' | tail -80 \
                 || echo '(dmesg unavailable)')
              echo '--- KERNEL CAPABILITY: uname -a ---'
              uname -a
              echo '--- lsmod iscsi/multipath ---'
              (command -v lsmod >/dev/null && lsmod | grep -iE 'iscsi|multipath' || echo '(lsmod unavailable or none)')
              echo '--- /proc/modules iscsi/multipath ---'
              (grep -iE 'iscsi|multipath' /proc/modules || echo '(none in /proc/modules)')
              echo '--- /sys/module iscsi/multipath ---'
              (ls /sys/module 2>/dev/null | grep -iE 'iscsi|multipath' || echo '(none in /sys/module)')
              echo '--- CONFIG flags (/proc/config.gz) ---'
              (zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_(SCSI_ISCSI_ATTRS|ISCSI_TCP|DM_MULTIPATH|CIFS_UPCALL)' || echo '(no /proc/config.gz)')
              echo '--- dmesg: iSCSI transport class registration ---'
              (dmesg 2>/dev/null | grep -iE 'iscsi transport|scsi_transport_iscsi|Loading iSCSI' \
                 || echo '(NOT FOUND -- iscsi transport may not be compiled into this kernel)')
              echo '--- dmesg: multipath ---'
              (dmesg 2>/dev/null | grep -iE 'multipath' || echo '(none)')
              echo '--- attempt modprobe iscsi_tcp ---'
              (modprobe iscsi_tcp 2>&1 || echo '(modprobe failed/unavailable -- expected without privileged)')
              echo '=== DIAG done ==='
            fi

            echo '--- ls -la /mnt/esan ---'
            ls -la /mnt/esan

            echo '--- CONNECTION TIME (container command start -> ESAN mount ready) ---'
            if [ -n "$MOUNT_READY" ]; then
              CONNECTION_SECONDS=$(awk "BEGIN{printf \"%.2f\", ${MOUNT_READY} - ${CMD_START}}")
              echo "ESAN_CONNECTION_SECONDS=${CONNECTION_SECONDS}"
            else
              CONNECTION_SECONDS=NA
              echo "ESAN_CONNECTION_SECONDS=NA  (/mnt/esan never became a real esan within the wait window)"
            fi

            # ---------- FIO PERFBENCH ----------
            # Two fio jobs on the mounted ESAN ext4 filesystem (bs=64k, iodepth=64,
            # libaio, direct=1, numjobs=4 to spread IO across the 4 vCPUs for more
            # throughput). All output goes to the container log so it is visible in CI.
            fio_ok=false
            if is_real_esan; then
              echo '=== FIO PERFBENCH (bs=64k, iodepth=64, libaio, direct=1, numjobs=4; CG cpu=4/mem=8) ==='
              echo "nproc=$(nproc)"
              echo '--- installing fio ---'
              export DEBIAN_FRONTEND=noninteractive
              apt-get update >/dev/null 2>&1
              apt-get install -y fio >/dev/null 2>&1
              if command -v fio >/dev/null 2>&1; then
                echo "fio installed OK: $(fio --version)"
              else
                echo 'fio install failed on first try; retrying...'
                apt-get update; apt-get install -y fio
              fi
              cd /mnt/esan || echo 'cd /mnt/esan failed'

              if command -v fio >/dev/null 2>&1; then
                echo '===== FIO TEST 1/2: randrw, size=32G, numjobs=4 (128G total) ====='
                T1S=$(date +%s)
                # Original perfbench command (single job, 128G total) - restore to revert:
                # fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=64k --iodepth=64 --readwrite=randrw --size=128G
                fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --bs=64k --iodepth=64 --numjobs=4 --readwrite=randrw --size=32G
                r1=$?
                echo "FIO_RANDRW_WALL_SECONDS=$(( $(date +%s) - T1S ))"
                rm -f /mnt/esan/test* 2>/dev/null

                echo '===== FIO TEST 2/2: rw (seq), size=32G, numjobs=4 (128G total) ====='
                T2S=$(date +%s)
                # Original perfbench command (single job, 128G total) - restore to revert:
                # fio --ioengine=libaio --direct=1 --name=seqrw --bs=64k --iodepth=64 --readwrite=rw --size=128G
                fio --ioengine=libaio --direct=1 --name=seqrw --bs=64k --iodepth=64 --numjobs=4 --readwrite=rw --size=32G
                r2=$?
                echo "FIO_SEQRW_WALL_SECONDS=$(( $(date +%s) - T2S ))"
                rm -f /mnt/esan/seqrw* 2>/dev/null
                echo '=== FIO PERFBENCH done ==='
                if [ "$r1" = 0 ] && [ "$r2" = 0 ]; then fio_ok=true; fi
              else
                echo 'ERROR: fio not installed; perf tests skipped'
              fi
            else
              echo 'ERROR: /mnt/esan is not a real ESAN mount; perf numbers would be meaningless'
            fi

            echo '--- SUMMARY ---'
            echo "ESAN_CONNECTION_SECONDS=${CONNECTION_SECONDS}"

            # Machine-readable result for the pipeline. scripts/parse_container_output.py
            # keys on the OUTPUT:/ERROR: line prefixes; the workflow runs it with
            # --fail-on-error, so an ERROR line fails the job. Success = real ESAN mount
            # AND both fio jobs completed, so the pass is visible in the CI log.
            if is_real_esan && [ "$fio_ok" = true ]; then
              echo 'PERFBENCH SUCCESS: ESAN mounted and both fio jobs completed'
              echo 'OUTPUT: {"esan_accessible": true}'
            else
              echo 'ERROR: ESAN perfbench failed (mount not real or fio did not complete)'
              echo 'OUTPUT: {"esan_accessible": false}'
            fi

            echo '=== ESAN perfbench done; keeping container alive ==='
            while true; do
              echo "primary alive: $(date -u)"
              sleep 30
            done
            '''
          ]
        }
      }
    ]
    volumes: [
      {
        name: 'esanvol'
        elasticSan: {
          volumeResourceId: elasticSanVolumeResourceId
          storageTargetKey: 'managedidentity#${managedIdentityClientId}'
          volumeMode: 'filesystem'
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
