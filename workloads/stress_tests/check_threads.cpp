#include <thread>
#include <chrono>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <netinet/ip.h>
#include <random>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <sys/time.h>
#include <vector>
#include <atomic>

static auto start_time = std::chrono::system_clock::now();

uint64_t ms_since_start()
{
    auto now = std::chrono::system_clock::now();
    return std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time).count();
}

void printf_with_time(const char *fmt, ...)
{
    char buf[1024];
    uint64_t ms_val = ms_since_start();
    uint64_t val_s = ms_val / 1000;
    uint64_t val_ms = ms_val % 1000;
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, 1024, fmt, args);
    printf("[% 5ld.%03ld] %s", val_s, val_ms, buf);
    va_end(args);
}

static int get_cpu()
{
    return sched_getcpu();
}

static void this_thread_pin_to_cpu(int cpu_id)
{
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu_id, &cpuset);
    if (sched_setaffinity(0, sizeof(cpuset), &cpuset) != 0)
    {
        printf_with_time("Failed to pin thread to cpu %d\n", cpu_id);
        exit(1);
    }
    sched_yield();
}

int sleep_random(int min_secs, int max_secs)
{
    std::random_device rd;
    std::default_random_engine gen(rd());
    std::uniform_int_distribution<int> dist(min_secs * 1000, max_secs * 1000);
    int sleep_ms = dist(gen);
    std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));
    return sleep_ms;
}

static int base_port = 5000;
static bool pin_listen_threads = true;
static bool pin_check_threads = true;
static int num_threads;
static std::vector<std::atomic_int> thread_last_on_cpu;
static std::vector<std::atomic_ullong> thread_last_alive_time_ms;
static std::vector<std::atomic_ullong> check_thread_last_alive_time_ms;

void thread_report_cpu(int this_thread)
{
    uint64_t now_ms = ms_since_start();
    int this_cpu = get_cpu();
    thread_last_on_cpu[this_thread].store(this_cpu, std::memory_order_seq_cst);
    thread_last_alive_time_ms[this_thread].store(now_ms, std::memory_order_seq_cst);
}

void thread_fn(int i)
{
    if (pin_listen_threads)
    {
        this_thread_pin_to_cpu(i);
    }
    thread_report_cpu(i);
    int port = base_port + i;
    const char *maybe_not_pinned = pin_listen_threads ? "" : " (not pinned)";
    printf_with_time("Thread %d on CPU %d%s listening on 0.0.0.0:%d\n", i, get_cpu(), maybe_not_pinned, port);
    if (pin_listen_threads && get_cpu() != i)
    {
        printf_with_time("ERROR: Thread %d is not running on CPU %d!!\n", i, i);
        exit(1);
    }

    thread_report_cpu(i);
    int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    thread_report_cpu(i);
    if (listen_fd < 0)
    {
        perror("socket");
        exit(1);
    }
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);
    thread_report_cpu(i);
    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
    {
        printf_with_time("Failed to bind to port %d\n", port);
        exit(1);
    }
    thread_report_cpu(i);
    char *buf = (char *)malloc(1024);
    while (true)
    {
        thread_report_cpu(i);
        if (listen(listen_fd, 10) < 0)
        {
            perror("listen");
            exit(1);
        }
        thread_report_cpu(i);
        int conn_fd = accept(listen_fd, NULL, NULL);
        thread_report_cpu(i);
        if (conn_fd < 0)
        {
            perror("accept");
            exit(1);
        }
        if (pin_listen_threads && get_cpu() != i)
        {
            printf_with_time("ERROR: Thread %d is not running on CPU %d!!\n", i, i);
            exit(1);
        }
        snprintf(buf, 1024, "CPU %d is alive\n", i);
        thread_report_cpu(i);
        send(conn_fd, buf, strlen(buf), 0);
        thread_report_cpu(i);
        close(conn_fd);
        thread_report_cpu(i);
    }
}

void check_fail_msg(int this_thread, int target_thread, uint64_t check_start_ms, int errno_)
{
    uint64_t now_ms = ms_since_start();
    int check_time_elapsed_ms = now_ms - check_start_ms;
    uint64_t alive_ms_ago = now_ms - thread_last_alive_time_ms[target_thread].load(std::memory_order_seq_cst);
    int last_on_cpu = thread_last_on_cpu[target_thread].load(std::memory_order_seq_cst);
    printf_with_time("ERROR: Failed to get response from thread %d (last on CPU %d, %llu ms ago) after %d ms (error: %s) (checking from thread %d on CPU %d)\n",
                     target_thread, last_on_cpu, alive_ms_ago, check_time_elapsed_ms, errno_ ? strerror(errno_) : "<success but timeout>", this_thread, get_cpu());
}

void check_thread_sleep(int this_thread)
{
    auto before_sleep = ms_since_start();
    check_thread_last_alive_time_ms[this_thread].store(before_sleep, std::memory_order_seq_cst);
    int before_sleep_cpu = get_cpu();
    int sleep_ms = sleep_random(1, 5);
    int after_sleep_cpu = get_cpu();
    auto now = ms_since_start();
    check_thread_last_alive_time_ms[this_thread].store(now, std::memory_order_seq_cst);
    if (now - before_sleep > sleep_ms + 2000)
    {
        printf_with_time("ERROR: Check thread %d (on CPU %d before, %d after sleep) failed to wake up after %d ms (requested sleep was %d ms)\n",
                         this_thread, before_sleep_cpu, after_sleep_cpu, now - before_sleep, sleep_ms);
    }
}

void check_thread_fn(int this_thread, int target_thread)
{
    if (pin_check_threads)
    {
        this_thread_pin_to_cpu(this_thread);
    }
    if (pin_check_threads && get_cpu() != this_thread)
    {
        printf_with_time("ERROR: Thread %d is not running on CPU %d!!\n", this_thread, this_thread);
        exit(1);
    }
    printf_with_time("Thread %d checking thread %d\n", this_thread, target_thread);
    int port = base_port + this_thread;
    char *buf = (char *)malloc(1024);
    char *expected_buf = (char *)malloc(1024);
    snprintf(expected_buf, 1024, "CPU %d is alive\n", target_thread);
    int expected_len = strlen(expected_buf);
    while (true)
    {
        if (pin_check_threads && get_cpu() != this_thread)
        {
            printf_with_time("ERROR: Check thread %d is not running on CPU %d!!\n", this_thread, this_thread);
            exit(1);
        }
        int s = socket(AF_INET, SOCK_STREAM, 0);
        if (s < 0)
        {
            perror("socket");
        }
        struct sockaddr_in addr;
        addr.sin_family = AF_INET;
        addr.sin_port = htons(base_port + target_thread);
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

        auto check_start = ms_since_start();

        const int timeout_secs = 2;
        struct timeval tv;
        tv.tv_sec = timeout_secs;
        tv.tv_usec = 0;
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        if (connect(s, (struct sockaddr *)&addr, sizeof(addr)) < 0)
        {
            check_fail_msg(this_thread, target_thread, check_start, errno);
            close(s);
            check_thread_sleep(this_thread);
            continue;
        }
        int received = recv(s, buf, 1024, 0);
        if (received < 0)
        {
            check_fail_msg(this_thread, target_thread, check_start, errno);
            close(s);
            check_thread_sleep(this_thread);
            continue;
        }
        uint64_t now_ms = ms_since_start();
        int last_on_cpu = thread_last_on_cpu[target_thread].load(std::memory_order_seq_cst);
        int64_t alive_ms_ago = now_ms - thread_last_alive_time_ms[target_thread].load(std::memory_order_seq_cst);
        if (alive_ms_ago < 0) {
            printf_with_time("Clock went backword? alive_ms_ago = %ld\n", alive_ms_ago);
        }
        if (received != expected_len || strncmp(buf, expected_buf, received) != 0)
        {
            printf_with_time("ERROR: Received unexpected data from check socket for CPU %d\n", target_thread);
            buf[received] = '\0';
            printf("        Expected: %s (len=%d)\n", expected_buf, expected_len);
            printf("        Received: %s (len=%d)\n", buf, received);
            printf("        Elapsed time: %lu ms\n", now_ms - check_start);
            printf("        Thread %d was last on CPU %d, %lu ms ago\n", target_thread, last_on_cpu, alive_ms_ago);
            close(s);
            check_thread_sleep(this_thread);
            continue;
        }
        close(s);
        printf_with_time("Checked thread %d (last on CPU %d, %ld ms ago) in %ld ms\n",
                         target_thread, last_on_cpu, alive_ms_ago, now_ms - check_start);
        if (alive_ms_ago > timeout_secs * 1000)
        {
            check_fail_msg(this_thread, target_thread, check_start, 0);
        }
        check_thread_sleep(this_thread);
    }
}

void parse_args(int argc, char **argv)
{
    for (int i = 1; i < argc; i++)
    {
        if (strcmp(argv[i], "--no-pin-listen-threads") == 0)
        {
            pin_listen_threads = false;
        }
        else if (strcmp(argv[i], "--no-pin-check-threads") == 0)
        {
            pin_check_threads = false;
        }
        else if (strcmp(argv[i], "--threads") == 0)
        {
            if (i + 1 >= argc)
            {
                printf("Missing argument for --threads\n");
                exit(1);
            }
            num_threads = atoi(argv[i + 1]);
            i++;
        }
        else
        {
            printf("Unknown argument: %s\n", argv[i]);
            printf("Usage: %s OPTIONS\n", argv[0]);
            printf("Options:\n");
            printf("--no-pin-listen-threads\n");
            printf("--no-pin-check-threads\n");
            printf("--threads N\n");
            exit(1);
        }
    }
}

int main(int argc, char const *argv[])
{
    num_threads = std::thread::hardware_concurrency();

    parse_args(argc, (char **)argv);
    const char* no_pin_env = getenv("NO_PIN_THREADS");
    if (no_pin_env && strcmp(no_pin_env, "1") == 0)
    {
        printf("NO_PIN_THREADS provided, disabling pinning\n");
        pin_listen_threads = false;
        pin_check_threads = false;
    }
    if (num_threads > std::thread::hardware_concurrency() && (pin_check_threads || pin_listen_threads)) {
        printf("ERROR: can't both have more threads than CPUs and pin threads to CPUs\n");
        return 1;
    }

    setbuf(stdout, NULL);

    auto gen = std::default_random_engine(std::random_device()());
    base_port = std::uniform_int_distribution<int>(5000, 6000)(gen);

    thread_last_on_cpu = std::vector<std::atomic_int>(num_threads);
    thread_last_alive_time_ms = std::vector<std::atomic_ullong>(num_threads);
    check_thread_last_alive_time_ms = std::vector<std::atomic_ullong>(num_threads);

    for (int i = 0; i < num_threads; i++)
    {
        std::thread t(thread_fn, i);
        t.detach();
    }
    std::this_thread::sleep_for(std::chrono::seconds(2));
    for (int i = 0; i < num_threads; i++)
    {
        std::thread t(check_thread_fn, i, (i + 1) % num_threads);
        t.detach();
    }
    while (true)
    {
        std::this_thread::sleep_for(std::chrono::seconds(10000));
    }
}
