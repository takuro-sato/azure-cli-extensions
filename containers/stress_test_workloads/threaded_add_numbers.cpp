#include <iostream>
#include <fstream>
#include <vector>
#include <thread>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <algorithm>
#include <stdarg.h>

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

static std::vector<uint64_t> per_threads_iters;
static std::vector<int32_t> numbers;

static size_t buf_size = 4<<20; // 4 MB
static bool pin_threads = false;

void thread_fn(int t_id) {
    if (pin_threads) {
        this_thread_pin_to_cpu(t_id);
        if (get_cpu() != t_id) {
            printf_with_time("ERROR: Thread %d is not running on CPU %d!!\n", t_id, t_id);
            exit(1);
        }
    }
    auto last_update_time = std::chrono::steady_clock::now();
    uint64_t local_iters = 0;

    while (true) {
        int64_t sum = 0;

        for (size_t i = 0; i < buf_size / sizeof(numbers[0]); ++i) {
            sum += numbers[i];
        }

        if (buf_size == 0) {
            sum += 1;
        }

        if (sum == 0) {
            abort();
        }

        asm volatile ("" :: "r"(sum) : "memory");

        local_iters += 1;
        auto now = std::chrono::steady_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_update_time).count() >= 101) {
            last_update_time = now;
            per_threads_iters[t_id] += local_iters;
            local_iters = 0;
        }
    }
}

void read_random_data() {
    std::ifstream urandom("/dev/urandom", std::ios::in | std::ios::binary);
    if (!urandom) {
        printf_with_time("Failed to open /dev/urandom\n");
        exit(1);
    }

    urandom.read((char*)(numbers.data()), buf_size);
    if (urandom.gcount() != buf_size) {
        printf_with_time("Failed to read enough data from /dev/urandom\n");
        exit(1);
    }
    urandom.close();
}

int main(int argc, char* argv[]) {
    int nproc = std::thread::hardware_concurrency();
    int num_threads = nproc;

    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--threads" && i + 1 < argc) {
            num_threads = std::stoi(argv[i + 1]);
            if (num_threads <= 0 || num_threads > nproc) {
                std::cerr << "Invalid number of threads: " << argv[i + 1] << std::endl;
                return 1;
            }
            ++i;
        } else if (std::string(argv[i]) == "--pin-threads") {
            pin_threads = true;
        } else if (std::string(argv[i]) == "--buf-size-kb" && i + 1 < argc) {
            buf_size = std::stoi(argv[i + 1]) << 10;
            if (buf_size < 0) {
                std::cerr << "Invalid buffer size: " << argv[i + 1] << std::endl;
                return 1;
            }
            ++i;
        } else {
            std::cerr << "Usage: " << argv[0] <<
                " [--threads N] [--pin-threads] [--buf-size-kb N]" << std::endl;
            return 1;
        }
    }

    if (buf_size % sizeof(int32_t) != 0) {
        abort();
    }
    numbers.resize(buf_size / sizeof(int32_t));
    per_threads_iters.resize(num_threads);

    if (buf_size) {
        read_random_data();
    }

    printf_with_time("%d threads\n", num_threads);

    std::vector<std::thread> threads;
    threads.reserve(num_threads);

    for (int i = 0; i < num_threads; ++i) {
        threads.emplace_back(thread_fn, i);
    }

    const auto report_interval = std::chrono::seconds(1);
    uint64_t prev_iters = 0;
    std::chrono::steady_clock::time_point prev_time = std::chrono::steady_clock::now();

    while (true) {
        std::this_thread::sleep_for(report_interval);
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration<double>(now - prev_time).count();
        prev_time = now;
        uint64_t current_iters = 0;
        for (const uint64_t& iters : per_threads_iters) {
            current_iters += iters;
        }
        uint64_t iterations_delta = current_iters - prev_iters;
        prev_iters = current_iters;

        double iterations_per_second = iterations_delta / elapsed;
        printf_with_time("%.2f iters/sec (%.2f iters/sec/cpu, %.2f MB/s/cpu)\n", current_iters, iterations_per_second, iterations_per_second / num_threads,
               (iterations_per_second * buf_size) / (1024 * 1024) / num_threads);
    }

    return 0;
}
