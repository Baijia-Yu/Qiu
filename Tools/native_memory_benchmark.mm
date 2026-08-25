#include <mach/mach.h>
#include <sys/resource.h>
#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "CTranslateBridge.h"

namespace {

struct MemorySample {
  double rss_mib;
  double footprint_mib;
};

MemorySample memory_sample() {
  mach_task_basic_info basic{};
  mach_msg_type_number_t basic_count = MACH_TASK_BASIC_INFO_COUNT;
  task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
            reinterpret_cast<task_info_t>(&basic), &basic_count);

  task_vm_info vm{};
  mach_msg_type_number_t vm_count = TASK_VM_INFO_COUNT;
  task_info(mach_task_self(), TASK_VM_INFO,
            reinterpret_cast<task_info_t>(&vm), &vm_count);
  constexpr double mib = 1024.0 * 1024.0;
  return {basic.resident_size / mib, vm.phys_footprint / mib};
}

double elapsed_seconds(const std::chrono::steady_clock::time_point start) {
  return std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
}

void sample(FILE *csv, const std::chrono::steady_clock::time_point start,
            const char *stage, const char *direction, int request) {
  const auto memory = memory_sample();
  std::fprintf(csv, "%.3f,%s,%s,%d,%.2f,%.2f\n", elapsed_seconds(start), stage,
               direction, request, memory.rss_mib, memory.footprint_mib);
  std::fflush(csv);
}

void require_ok(const int status, const char *operation) {
  if (status != 0) {
    std::fprintf(stderr, "%s failed\n", operation);
    std::exit(1);
  }
}

void translate(FILE *csv, const std::chrono::steady_clock::time_point start,
               const int direction, const char *direction_name, const int request,
               const std::string &text) {
  const char *result = QTNativeTranslate(text.c_str(), direction);
  if (!result || std::string(result).rfind("ERROR: ", 0) == 0) {
    std::fprintf(stderr, "translation failed: %s\n", result ? result : "null");
    std::exit(1);
  }
  sample(csv, start, "inference", direction_name, request);
}

}  // namespace

int main() {
  FILE *csv = std::fopen("native-memory-benchmark.csv", "w");
  if (!csv) return 1;
  std::fprintf(csv, "timestamp,stage,direction,request,rss_mib,phys_footprint_mib\n");
  const auto start = std::chrono::steady_clock::now();

  sample(csv, start, "baseline", "none", 0);
  require_ok(QTNativePrimeTokenizers(0), "prime EN→ZH tokenizer");
  sample(csv, start, "sentencepiece_ready", "en_zh", 0);
  require_ok(QTNativeLoadModel(0), "load EN→ZH");
  sample(csv, start, "model_loaded", "en_zh", 0);
  for (int i = 1; i <= 100; ++i) {
    translate(csv, start, 0, "en_zh", i, "This is translation request number " + std::to_string(i) + ".");
  }
  QTNativeUnload(0);
  sleep(2);
  sample(csv, start, "unloaded", "en_zh", 0);

  require_ok(QTNativePrimeTokenizers(1), "prime ZH→EN tokenizer");
  sample(csv, start, "sentencepiece_ready", "zh_en", 0);
  require_ok(QTNativeLoadModel(1), "load ZH→EN");
  sample(csv, start, "model_loaded", "zh_en", 0);
  for (int i = 1; i <= 100; ++i) {
    translate(csv, start, 1, "zh_en", i, "这是第" + std::to_string(i) + "次翻译请求。");
  }
  QTNativeUnload(1);
  sleep(2);
  sample(csv, start, "unloaded", "zh_en", 0);

  require_ok(QTNativeLoadModel(0), "reload EN→ZH");
  require_ok(QTNativeLoadModel(1), "reload ZH→EN");
  sample(csv, start, "both_models_loaded", "both", 0);
  translate(csv, start, 0, "both", 1, "The model runs entirely offline.");
  translate(csv, start, 1, "both", 2, "这个模型完全在本地运行。");
  QTNativeUnload(0);
  QTNativeUnload(1);
  sleep(2);
  sample(csv, start, "both_unloaded", "none", 0);
  std::fclose(csv);
  return 0;
}
