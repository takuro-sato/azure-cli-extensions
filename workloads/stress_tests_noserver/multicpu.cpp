#include <stdio.h>
#include <stdlib.h>
#include <thread>
#include <string.h>
#include <sched.h>

static uint64_t get_cycles()
{
    uint64_t t;
    unsigned long lo, hi;
    asm volatile("rdtsc" : "=a"(lo), "=d"(hi));
    t = lo | (hi << 32);
    return t;
}

uint64_t measure_rdtsc_per_secs()
{
    uint64_t start = get_cycles();
    auto start_tp = std::chrono::system_clock::now();
    std::this_thread::sleep_for(std::chrono::seconds(1));
    uint64_t end = get_cycles();
    auto end_tp = std::chrono::system_clock::now();
    auto duration_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(end_tp - start_tp)
            .count();
    return ( (double)(end - start) / (double)duration_ms ) * 1000.0;
}

static uint64_t rdtsc_per_secs;

static int get_cpu()
{
    return sched_getcpu();
}

static int loop_rounds = 300000000;

// These settings seems to be relatively stable
static int wall_duration_mismatch_tolerance_ms = 100;
static int stall_tolerance_ms = 300;
static int speedup_jitter_tolerance_ms = 300;

static bool update_average_cycles = true;
static int calibration_time_secs = 10;
static int numThreads = 2;

void process_thread(int i)
{
    printf("Thread %d started\n", i);
    uint64_t calibration_cycles = 0;
    uint64_t calibration_count = 0;
    bool calibrated = false;
    uint64_t calibrated_average_cycles;
    uint64_t calibrated_avg_cycles_msecs;
    uint64_t nb_loops_done = 0;
    uint64_t nb_loops_with_slowdown = 0;
    auto process_start_wall = std::chrono::system_clock::now();
    while (1)
    {
        nb_loops_done += 1;
        uint64_t start_cycles = get_cycles();
        auto start_wall = std::chrono::steady_clock::now();
        for (int j = 0; j < loop_rounds; j++)
        {
            asm volatile("" ::: "memory");
        }
        uint64_t end_cycles = get_cycles();
        auto end_wall = std::chrono::steady_clock::now();
        if (start_cycles == end_cycles)
        {
            printf("SHOULD NEVER HAPPEN: Thread %d: rdtsc did not move\n", i);
        }
        if (end_cycles < start_cycles)
        {
            printf("SHOULD NEVER HAPPEN: Thread %d: end_cycles = %lu < start_cycles = %lu\n", i,
                   end_cycles, start_cycles);
        }
        int64_t cycles_duration = end_cycles - start_cycles;
        auto wall_duration_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(end_wall -
                                                                  start_wall)
                .count();
        if (end_wall <= start_wall) {
            printf("SHOULD NEVER HAPPEN: Thread %d: end_wall <= start_wall\n", i);
        }
        int64_t cycles_duration_ms = cycles_duration * 1000 / rdtsc_per_secs;
        if (wall_duration_ms >
                cycles_duration_ms + wall_duration_mismatch_tolerance_ms ||
            cycles_duration_ms >
                wall_duration_ms + wall_duration_mismatch_tolerance_ms)
        {
            printf("Thread %d: rdtsc and wall time mismatch: wall diff %ld msecs, "
                   "cycles is %lu to %lu = %ld, calculated duration %ld msecs\n",
                   i, wall_duration_ms, start_cycles, end_cycles, cycles_duration, cycles_duration_ms);
        }
        if (!calibrated)
        {
            calibration_cycles += cycles_duration;
            calibration_count++;
            auto time_now = std::chrono::system_clock::now();
            if (time_now - process_start_wall >
                std::chrono::seconds(calibration_time_secs))
            {
                calibrated_average_cycles = calibration_cycles / calibration_count;
                calibrated_avg_cycles_msecs = calibrated_average_cycles * 1000 / rdtsc_per_secs;
                calibrated = true;
                printf("Thread %d: settled on %lu cycles_duration on average (%f "
                       "secs) per "
                       "loop\n",
                       i, calibrated_average_cycles,
                       (double)calibrated_average_cycles / (double)rdtsc_per_secs);
            }
        }
        if (calibrated)
        {
            // printf("Thread %d: %lu cycles_duration on average\n", i,
            //        calibration_cycles / calibration_count);
            if (cycles_duration_ms > calibrated_avg_cycles_msecs + stall_tolerance_ms)
            {
                nb_loops_with_slowdown += 1;
                printf("Thread %d (cpu %d): loop took %lu msecs which is an extra %lu msecs "
                       "compared to average of %lu msecs. Percentage %f%%\n",
                       i, get_cpu(), cycles_duration_ms, cycles_duration_ms - calibrated_avg_cycles_msecs, calibrated_avg_cycles_msecs,
                       (double)nb_loops_with_slowdown / (double)nb_loops_done * 100.0);
            }
            else if (calibrated_avg_cycles_msecs >
                     cycles_duration_ms + speedup_jitter_tolerance_ms)
            {
                printf("Thread %d (cpu %d): rdtsc slowed down or loop got faster? "
                       "%lu msecs this time compared to %lu msecs average, which is %ld less.\n",
                       i, get_cpu(), cycles_duration_ms, calibrated_avg_cycles_msecs, calibrated_avg_cycles_msecs - cycles_duration_ms);
            }
        }
    }
}

static void parse_command_line(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--loop-rounds") == 0) {
            i++;
            if (i >= argc) {
                printf("Missing argument for --loop-rounds\n");
                exit(1);
            }
            loop_rounds = atoi(argv[i]);
        } else if (strcmp(argv[i], "--wall-duration-mismatch-tolerance-ms") == 0) {
            i++;
            if (i >= argc) {
                printf("Missing argument for --wall-duration-mismatch-tolerance-ms\n");
                exit(1);
            }
            wall_duration_mismatch_tolerance_ms = atoi(argv[i]);
        } else if (strcmp(argv[i], "--stall-tolerance-ms") == 0) {
            i++;
            if (i >= argc) {
                printf("Missing argument for --stall-tolerance-ms\n");
                exit(1);
            }
            stall_tolerance_ms = atoi(argv[i]);
        } else if (strcmp(argv[i], "--speedup-jitter-tolerance-ms") == 0) {
            i++;
            if (i >= argc) {
                printf("Missing argument for --speedup-jitter-tolerance-ms\n");
                exit(1);
            }
            speedup_jitter_tolerance_ms = atoi(argv[i]);
        } else if (strcmp(argv[i], "--no-update-average-cycles") == 0) {
            update_average_cycles = false;
        } else if (strcmp(argv[i], "--calibration-time-secs") == 0) {
            i++;
            if (i >= argc) {
                printf("Missing argument for --calibration-time-secs\n");
                exit(1);
            }
            calibration_time_secs = atoi(argv[i]);
        } else if (strcmp(argv[i], "--num-threads") == 0) {
            i++;
            if (i >= argc) {
                printf("Missing argument for --num-threads\n");
                exit(1);
            }
            numThreads = atoi(argv[i]);
        } else if (strcmp(argv[i], "--help") == 0) {
            printf("Options:\n");
            printf("--loop-rounds <num>\n");
            printf("--wall-duration-mismatch-tolerance-ms <num>\n");
            printf("--stall-tolerance-ms <num>\n");
            printf("--speedup-jitter-tolerance-ms <num>\n");
            printf("--no-update-average-cycles\n");
            printf("--calibration-time-secs <num>\n");
            exit(0);
        } else {
            printf("Unknown argument: %s\n", argv[i]);
            exit(1);
        }
    }
}

int main(int argc, char **argv)
{
    setbuf(stdout, NULL);

    parse_command_line(argc, argv);

    bool done = false;
    int n = std::thread::hardware_concurrency();
    printf("Number of CPU cores: %d\n", n);
    printf("Config:\n");
    printf("  loop_rounds: %d\n", loop_rounds);
    printf("  wall_duration_mismatch_tolerance_ms: %d\n", wall_duration_mismatch_tolerance_ms);
    printf("  stall_tolerance_ms: %d\n", stall_tolerance_ms);
    printf("  speedup_jitter_tolerance_ms: %d\n", speedup_jitter_tolerance_ms);
    printf("  update_average_cycles: %s\n", update_average_cycles ? "true" : "false");
    printf("  calibration_time_secs: %d\n", calibration_time_secs);
    printf("  numThreads: %d\n", numThreads);

    rdtsc_per_secs = measure_rdtsc_per_secs();
    printf("rdtsc per second: %lu\n", rdtsc_per_secs);
    for (int i = 0; i < numThreads; i++)
    {
        std::thread t(process_thread, i);
        t.detach();
    }
    while (1)
    {
        std::this_thread::sleep_for(std::chrono::seconds(100000));
    }
}
