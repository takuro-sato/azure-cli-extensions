#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <mutex>
#include <random>
#include <stdarg.h>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <thread>
#include <unistd.h>
#include <vector>

using namespace std;

// Define operation types
enum class OpType {
  READ_RAND,
  WRITE_RAND,
  READ_SEQ,
  WRITE_SEQ,
  FTRUNCATE,
  FSYNC,
  RECREATE
};

// Configuration structure
struct Config {
  int concurrent_files = 1;
  size_t file_size_min = 1024 * 1024;      // 1MB default
  size_t file_size_max = 10 * 1024 * 1024; // 10MB default
  size_t block_size = 4096;                // 4KB default
  vector<OpType> operations;
  string work_dir = ".";
  int latency_threshold_ms = 100;
  bool trace_cmd_stop = false;
};

// Statistics structure
struct Stats {
  atomic<uint64_t> total_ops{0};
  atomic<uint64_t> high_latency_events{0};
  atomic<uint64_t> max_latency_us{0};
};

// Enhance OpOut with error tracking
struct OpOut {
  double total_us;
  double unlink_us = 0;
  double open_us = 0;
  int fd; // Pass back the file descriptor
  bool need_new_buffer_data = false;
  size_t new_size = 0;
  bool error = false;
  string error_msg;
};

uint64_t ns_since_boot() {
  struct timespec ts;
  clock_gettime(CLOCK_BOOTTIME, &ts);
  return (ts.tv_sec * 1000000000ULL) + ts.tv_nsec;
}

void printf_with_time(const char *fmt, ...) {
  char buf[1024];
  uint64_t ns_val = ns_since_boot();
  uint64_t val_s = ns_val / 1000000000;
  uint64_t val_us = (ns_val % 1000000000) / 1000;
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, 1024, fmt, args);
  printf("[% 5ld.%06ld] %s", val_s, val_us, buf);
  va_end(args);
}

// Function prototypes
void print_usage();
bool parse_args(int argc, char const *argv[], Config &config);
void run_benchmark(const Config &config, Stats &stats);
void worker_thread(int thread_id, const Config &config, Stats &stats);
OpOut perform_operation(int fd, OpType op, const string &filename,
                        size_t file_size, const Config &config,
                        vector<char> &buffer, default_random_engine &gen);

void print_usage() {
  // clang-format off
  printf("Usage: io_latency_bench [options]\n"
       "A tool to do random IO operations on a set of files.\n"
       "Options:\n"
       "  --concurrent-files <num>     Number of files to work on concurrently\n"
       "  --file-size <size_min>..<size_max>\n"
       "                               Size of each file in bytes. A size will be randomly\n"
       "                               chosen in the range [size_min, size_max].\n"
       "  --block-size <size>          Size of each IO operation in bytes\n"
       "  -o <operation>               Operation to perform (can be used multiple times, in\n"
       "                               which case they are interleaved randomly)\n"
       "    Operations:\n"
       "      read-rand                Seek to a random place then read a block\n"
       "      write-rand               Seek to a random place then write a block\n"
       "      read-seq                 Read the entire file sequentially\n"
       "      write-seq                Write the entire file sequentially\n"
       "      ftruncate                Truncate the file to a random size within the allowed range\n"
       "      fsync                    Flush the file to disk\n"
       "      recreate                 Unlink and recreate the file\n"
       "  -w <work_dir>                Directory to create files in\n"
       "  --latency-thres <ms>         Threshold for high latency in milliseconds\n"
       "  --trace-cmd-stop             Do `trace-cmd stop` when high latency is detected\n");
  // clang-format on
}

bool parse_args(int argc, char const *argv[], Config &config) {
  for (int i = 1; i < argc; i++) {
    string arg = argv[i];

    if (arg == "--concurrent-files" && i + 1 < argc) {
      config.concurrent_files = atoi(argv[++i]);
    } else if (arg == "--file-size" && i + 1 < argc) {
      string size_range = argv[++i];
      size_t pos = size_range.find("..");
      if (pos != string::npos) {
        config.file_size_min = stoull(size_range.substr(0, pos));
        config.file_size_max = stoull(size_range.substr(pos + 2));
        if (config.file_size_min > config.file_size_max) {
          cerr << "Invalid file size range: " << size_range << endl;
          return false;
        }
      } else {
        config.file_size_min = config.file_size_max = stoull(size_range);
      }
    } else if (arg == "--block-size" && i + 1 < argc) {
      config.block_size = stoull(argv[++i]);
    } else if (arg == "-o" && i + 1 < argc) {
      string op = argv[++i];
      if (op == "read-rand") {
        config.operations.push_back(OpType::READ_RAND);
      } else if (op == "write-rand") {
        config.operations.push_back(OpType::WRITE_RAND);
      } else if (op == "read-seq") {
        config.operations.push_back(OpType::READ_RAND);
      } else if (op == "write-seq") {
        config.operations.push_back(OpType::WRITE_RAND);
      } else if (op == "ftruncate") {
        config.operations.push_back(OpType::FTRUNCATE);
      } else if (op == "fsync") {
        config.operations.push_back(OpType::FSYNC);
      } else if (op == "recreate") {
        config.operations.push_back(OpType::RECREATE);
      } else {
        cerr << "Unknown operation: " << op << endl;
        return false;
      }
    } else if (arg == "-w" && i + 1 < argc) {
      config.work_dir = argv[++i];
    } else if (arg == "--latency-thres" && i + 1 < argc) {
      config.latency_threshold_ms = atoi(argv[++i]);
    } else if (arg == "--trace-cmd-stop") {
      config.trace_cmd_stop = true;
    } else {
      cerr << "Unknown argument: " << arg << endl;
      print_usage();
      return false;
    }
  }

  if (config.operations.empty()) {
    cerr << "No operations specified" << endl;
    return false;
  }

  return true;
}

OpOut perform_operation(int fd, OpType op, const string &filename,
                        size_t file_size, const Config &config,
                        vector<char> &buffer, default_random_engine &gen) {
  OpOut result;
  result.fd = fd; // Initialize with the input fd
  result.need_new_buffer_data = false;
  result.error = false;
  result.new_size = file_size;

  // Use the passed in generator instead of creating a new one
  uniform_int_distribution<size_t> pos_dist(0, file_size - config.block_size);
  uniform_int_distribution<size_t> file_size_dist(config.file_size_min,
                                                  config.file_size_max);

  auto start = chrono::high_resolution_clock::now();

  switch (op) {
  case OpType::READ_RAND: {
    off_t pos = pos_dist(gen);
    if (lseek(fd, pos, SEEK_SET) == -1) {
      result.error = true;
      result.error_msg = "lseek failed: " + string(strerror(errno));
      break;
    }

    ssize_t bytes_read = read(fd, buffer.data(), config.block_size);
    if (bytes_read == -1) {
      result.error = true;
      result.error_msg = "read failed: " + string(strerror(errno));
    } else if (bytes_read < config.block_size) {
      result.error = true;
      result.error_msg = "Short read: got " + to_string(bytes_read) +
                         " bytes, expected " + to_string(config.block_size) +
                         " bytes. Reading from pos " + to_string(pos) +
                         " with file size " + to_string(file_size);
    }
    result.need_new_buffer_data = !result.error;
    break;
  }
  case OpType::WRITE_RAND: {
    off_t pos = pos_dist(gen);
    if (lseek(fd, pos, SEEK_SET) == -1) {
      result.error = true;
      result.error_msg = "lseek failed: " + string(strerror(errno));
      break;
    }

    ssize_t bytes_written = write(fd, buffer.data(), config.block_size);
    if (bytes_written == -1) {
      result.error = true;
      result.error_msg = "write failed: " + string(strerror(errno));
    } else if (bytes_written < config.block_size) {
      result.error = true;
      result.error_msg = "Short write: wrote " + to_string(bytes_written) +
                         " bytes, expected " + to_string(config.block_size) +
                         " bytes";
    }
    result.need_new_buffer_data = !result.error;
    break;
  }
  case OpType::READ_SEQ: {
    if (lseek(fd, 0, SEEK_SET) == -1) {
      result.error = true;
      result.error_msg = "lseek failed: " + string(strerror(errno));
      break;
    }

    ssize_t bytes_read = 0;
    while (bytes_read < file_size) {
      ssize_t bytes = read(fd, buffer.data() + bytes_read, config.block_size);
      if (bytes == -1) {
        result.error = true;
        result.error_msg = "read failed: " + string(strerror(errno));
        break;
      } else if (bytes < config.block_size &&
                 bytes_read <= file_size - config.block_size) {
        result.error = true;
        result.error_msg = "Short read: got " + to_string(bytes) +
                           " bytes, expected " + to_string(config.block_size) +
                           " bytes";
        break;
      } else if (bytes == 0) {
        if (bytes_read < file_size) {
          result.error = true;
          result.error_msg = "Short read: got 0 bytes, expected " +
                             to_string(file_size - bytes_read) + " bytes";
        }
        break;
      }
      bytes_read += bytes;
    }
    result.need_new_buffer_data = !result.error;
    break;
  }
  case OpType::WRITE_SEQ: {
    if (lseek(fd, 0, SEEK_SET) == -1) {
      result.error = true;
      result.error_msg = "lseek failed: " + string(strerror(errno));
      break;
    }

    ssize_t bytes_written = 0;
    while (bytes_written < file_size) {
      ssize_t bytes =
          write(fd, buffer.data() + bytes_written, config.block_size);
      if (bytes == -1) {
        result.error = true;
        result.error_msg = "write failed: " + string(strerror(errno));
        break;
      } else if (bytes < config.block_size &&
                 bytes_written <= file_size - config.block_size) {
        result.error = true;
        result.error_msg = "Short write: wrote " + to_string(bytes) +
                           " bytes, expected " + to_string(config.block_size) +
                           " bytes";
        break;
      } else if (bytes == 0) {
        if (bytes_written < file_size) {
          result.error = true;
          result.error_msg = "Short write: wrote 0 bytes, expected " +
                             to_string(file_size - bytes_written) + " bytes";
        }
        break;
      }
      bytes_written += bytes;
    }
    result.need_new_buffer_data = !result.error;
    break;
  }
  case OpType::FTRUNCATE: {
    result.new_size = file_size_dist(gen);
    if (ftruncate(fd, result.new_size) == -1) {
      result.new_size = 0;
      result.error = true;
      result.error_msg = "ftruncate failed: " + string(strerror(errno));
    }
    break;
  }
  case OpType::FSYNC: {
    if (fsync(fd) == -1) {
      result.error = true;
      result.error_msg = "fsync failed: " + string(strerror(errno));
    }
    break;
  }
  case OpType::RECREATE: {
    // Close the current file
    if (close(fd) == -1) {
      printf_with_time("Warning: close failed: %s\n", strerror(errno));
      // Not treating this as operation failure
    }

    // Measure unlink time separately
    auto unlink_start = chrono::high_resolution_clock::now();
    if (unlink(filename.c_str()) == -1) {
      result.error = true;
      result.error_msg = "unlink failed: " + string(strerror(errno));
    }
    auto unlink_end = chrono::high_resolution_clock::now();
    result.unlink_us =
        chrono::duration_cast<chrono::microseconds>(unlink_end - unlink_start)
            .count();

    // If unlink failed, still try to open the file
    // Generate a new random file size
    result.new_size = file_size_dist(gen);

    // Measure open time separately
    auto open_start = chrono::high_resolution_clock::now();
    result.fd = open(filename.c_str(), O_RDWR | O_CREAT, 0644);
    auto open_end = chrono::high_resolution_clock::now();
    result.open_us =
        chrono::duration_cast<chrono::microseconds>(open_end - open_start)
            .count();

    if (result.fd == -1) {
      result.error = true;
      result.error_msg = "open failed: " + string(strerror(errno));
    } else {
      // Allocate space for the new file
      if (ftruncate(result.fd, result.new_size) == -1) {
        result.error = true;
        result.error_msg = "ftruncate failed: " + string(strerror(errno));
      }
    }
    break;
  }
  }

  auto end = chrono::high_resolution_clock::now();
  result.total_us =
      chrono::duration_cast<chrono::microseconds>(end - start).count();

  return result;
}

const char *op_to_string(OpType op) {
  switch (op) {
  case OpType::READ_RAND:
    return "read-rand";
  case OpType::WRITE_RAND:
    return "write-rand";
  case OpType::READ_SEQ:
    return "read-seq";
  case OpType::WRITE_SEQ:
    return "write-seq";
  case OpType::FTRUNCATE:
    return "ftruncate";
  case OpType::FSYNC:
    return "fsync";
  case OpType::RECREATE:
    return "recreate";
  default:
    return "???";
  }
}

void fill_buffer_random(vector<char> &buffer, default_random_engine &gen) {
  uniform_int_distribution<char> byte_dist(0, 255);
  uint8_t fill_byte = byte_dist(gen);
  memset(buffer.data(), fill_byte, buffer.size());
}

// We need to modify the worker_thread function to handle the fd change after
// recreate
void worker_thread(int thread_id, const Config &config, Stats &stats) {
  // Create a unique filename for this thread
  string filename =
      config.work_dir + "/io_bench_" + to_string(thread_id) + ".dat";

  // Generate random file size within the configured range
  random_device rd;
  default_random_engine gen(rd());
  uniform_int_distribution<size_t> file_size_dist(config.file_size_min,
                                                  config.file_size_max);
  uniform_int_distribution<size_t> op_dist(0, config.operations.size() - 1);

  size_t file_size = file_size_dist(gen);

  // Create and initialize the file
  int fd = open(filename.c_str(), O_RDWR | O_CREAT | O_TRUNC, 0644);
  if (fd == -1) {
    cerr << "Failed to create file: " << filename << endl;
    return;
  }

  // Allocate space for the file
  int res = ftruncate(fd, file_size);
  if (res == -1) {
    cerr << "Failed to ftruncate " << filename << ": " << strerror(errno)
         << endl;
    exit(1);
    return;
  }

  // Allocate a buffer for read/write operations
  vector<char> buffer(config.block_size);

  fill_buffer_random(buffer, gen);

  bool trace_cmd_stopped = false;

  // Do random operations
  while (true) {
    // Select a random operation
    OpType op = config.operations[op_dist(gen)];

    // Perform the operation
    OpOut result =
        perform_operation(fd, op, filename, file_size, config, buffer, gen);
    double latency_us = result.total_us;

    // Check for errors
    if (result.error) {
      printf_with_time("ERROR: in thread %d during %s: %s\n", thread_id,
                       op_to_string(op), result.error_msg.c_str());

      // If the file descriptor is invalid after an error, try to recover
      if (op == OpType::RECREATE && result.fd == -1) {
        // Attempt to recreate the file
        fd = open(filename.c_str(), O_RDWR | O_CREAT, 0644);
        if (fd == -1) {
          printf_with_time("Failed to re-open file %s: %s\n", filename.c_str(),
                           strerror(errno));
          break; // Exit thread if recover fails
        }

        size_t file_size = file_size_dist(gen);
        if (ftruncate(fd, file_size) == -1) {
          printf_with_time("Failed to ftruncate %s: %s\n", filename.c_str(),
                           strerror(errno));
        }
      }
    } else if (op == OpType::RECREATE) {
      fd = result.fd; // Update fd from the operation result

      // Check for high latency in specific parts of the recreate operation
      if (result.unlink_us > config.latency_threshold_ms * 1000) {
        printf_with_time("High unlink latency: %.3f ms (thread %d)\n",
                         result.unlink_us / 1000.0, thread_id);
      }
      if (result.open_us > config.latency_threshold_ms * 1000) {
        printf_with_time("High open latency: %.3f ms (thread %d)\n",
                         result.open_us / 1000.0, thread_id);
      }

      // Check if file recreation failed
      if (fd == -1) {
        cerr << "Failed to recreate file: " << filename << endl;
        break;
      }
    }

    if (result.new_size) {
      file_size = result.new_size;
    }

    // Update statistics
    stats.total_ops++;

    // Check for high latency
    if (latency_us > config.latency_threshold_ms * 1000) {
      stats.high_latency_events++;

      // Update max latency
      uint64_t current_max = stats.max_latency_us.load(memory_order_relaxed);
      while (latency_us > current_max) {
        if (stats.max_latency_us.compare_exchange_weak(current_max, latency_us,
                                                       memory_order_relaxed)) {
          break;
        }
        current_max = stats.max_latency_us.load(memory_order_relaxed);
      }

      printf_with_time("ERROR: High latency doing %s: %.3f ms (thread %d)\n",
                       op_to_string(op), latency_us / 1000.0, thread_id);

      // Stop trace-cmd if configured
      if (config.trace_cmd_stop && !trace_cmd_stopped) {
        system("trace-cmd stop");
        printf_with_time("trace-cmd stopped\n");
        trace_cmd_stopped = true;
      }
    }

    if (result.need_new_buffer_data && !result.error) {
      // Refill the buffer with new data if needed
      fill_buffer_random(buffer, gen);
    }
  }

  close(fd);
}

void run_benchmark(const Config &config, Stats &stats) {
  vector<thread> threads;

  printf_with_time("Starting benchmark with %d concurrent files\n",
                   config.concurrent_files);

  // Create worker threads
  for (int i = 0; i < config.concurrent_files; i++) {
    threads.emplace_back(worker_thread, i, ref(config), ref(stats));
  }

  uint64_t last_ops = 0;
  chrono::steady_clock::time_point last_time = chrono::steady_clock::now();

  // Print stats periodically
  while (true) {
    this_thread::sleep_for(chrono::seconds(1));
    uint64_t ops = stats.total_ops.load();
    uint64_t delta_ns = chrono::duration_cast<chrono::nanoseconds>(
                            chrono::steady_clock::now() - last_time)
                            .count();
    last_time = chrono::steady_clock::now();
    uint64_t ops_per_sec = (ops - last_ops) * 1000000000ULL / delta_ns;
    last_ops = ops;
    uint64_t high_latency = stats.high_latency_events.load();
    uint64_t max_latency = stats.max_latency_us.load();

    printf_with_time("Ops: % 7lu (% 4lu/s), High latency events: %lu", ops,
                     ops_per_sec, high_latency);
    if (max_latency > 0) {
      printf(", Max latency: %.3f ms", max_latency / 1000.0);
    }
    printf("\n");
  }

  // Join threads (this won't be reached as the loop above is infinite)
  for (auto &t : threads) {
    t.join();
  }
}

int main(int argc, char const *argv[]) {
  Config config;
  Stats stats;

  setbuf(stdout, NULL);

  if (argc == 1) {
    print_usage();
    return 1;
  }

  if (!parse_args(argc, argv, config)) {
    return 1;
  }

  run_benchmark(config, stats);

  return 0;
}
