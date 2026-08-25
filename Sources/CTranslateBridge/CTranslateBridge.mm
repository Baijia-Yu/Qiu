#include "CTranslateBridge.h"

#include <algorithm>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

#include <ctranslate2/translator.h>
#include <sentencepiece_processor.h>

namespace {

enum Direction { EnToZh = 0, ZhToEn = 1 };

std::string replace_all(std::string value, const std::string &from, const std::string &to) {
  size_t position = 0;
  while ((position = value.find(from, position)) != std::string::npos) {
    value.replace(position, from.size(), to);
    position += to.size();
  }
  return value;
}

const std::vector<std::pair<std::string, std::string>> &academic_unicode_replacements() {
  static const std::vector<std::pair<std::string, std::string>> replacements = {
      {"μ", "mu"}, {"µ", "mu"}, {"α", "alpha"}, {"β", "beta"},
      {"γ", "gamma"}, {"δ", "delta"}, {"ε", "epsilon"}, {"θ", "theta"},
      {"λ", "lambda"}, {"σ", "sigma"}, {"τ", "tau"}, {"ω", "omega"},
      {"𝜇", "mu"}, {"𝛼", "alpha"}, {"𝛽", "beta"}, {"𝛾", "gamma"},
      {"𝛿", "delta"}, {"𝜃", "theta"}, {"𝜆", "lambda"}, {"𝜎", "sigma"},
      {"Γ", "Gamma"}, {"Δ", "Delta"}, {"Λ", "Lambda"}, {"Σ", "Sigma"},
      {"Ω", "Omega"}, {"∈", " in "}, {"∉", " not in "},
      {"≤", " less than or equal to "}, {"≥", " greater than or equal to "},
      {"≠", " not equal to "}, {"≈", " approximately "}, {"→", " to "},
      {"←", " from "}, {"↦", " maps to "}, {"×", " times "},
      {"±", " plus or minus "}, {"∞", " infinity "}, {"∑", " sum "},
      {"∂", " partial "}, {"∇", " nabla "}, {"ℝ", " real numbers "},
      {"ℤ", " integers "}, {"ℕ", " natural numbers "}, {"—", "-"}, {"–", "-"},
      {"²", "2"}, {"³", "3"}, {"⁰", "0"}, {"¹", "1"}, {"⁴", "4"},
      {"⁵", "5"}, {"⁶", "6"}, {"⁷", "7"}, {"⁸", "8"}, {"⁹", "9"},
      {"“", "\""}, {"”", "\""}, {"‘", "'"}, {"’", "'"},
  };
  return replacements;
}

// The OPUS-MT tokenizers emit <unk> for several common maths glyphs. One unknown
// source token can make the decoder produce an entire unknown sequence, so rewrite
// those glyphs to equivalent words before retrying inference.
std::string normalize_academic_unicode(const std::string &input) {
  std::string normalized = input;
  for (const auto &[from, to] : academic_unicode_replacements()) {
    normalized = replace_all(std::move(normalized), from, to);
  }
  return normalized;
}

bool contains_unknown_piece(const std::vector<std::string> &tokens) {
  for (const auto &token : tokens) {
    if (token == "<unk>") return true;
  }
  return false;
}

bool contains_unknown_id(
    sentencepiece::SentencePieceProcessor &processor,
    const std::string &input) {
  std::vector<int> ids;
  const auto status = processor.Encode(input, &ids);
  if (!status.ok()) throw std::runtime_error(status.ToString());
  for (const int id : ids) {
    if (id == processor.unk_id()) return true;
  }
  return false;
}

struct TranslationRuntime {
  std::unique_ptr<ctranslate2::Translator> translator;
  std::unique_ptr<sentencepiece::SentencePieceProcessor> source_sp;
  std::unique_ptr<sentencepiece::SentencePieceProcessor> target_sp;

  void load_tokenizers(const Direction direction) {
    const char *configured_root = std::getenv("QUICK_TRANSLATE_MODEL_ROOT");
    const std::string root = configured_root ? configured_root : "Models";
    const std::string pair = direction == EnToZh ? "en-zh" : "zh-en";
    const std::string package_id = direction == EnToZh ? "opus-mt-en-zh-int8" : "opus-mt-zh-en-int8";
    const std::string source_dir = configured_root
        ? root + "/" + package_id + "/1.0.0/sentencepiece"
        : root + "/source/" + pair;

    load_tokenizers(source_dir + "/source.spm", source_dir + "/target.spm");
  }

  void load_tokenizers(const std::string &source_path, const std::string &target_path) {
    if (source_sp && target_sp) return;
    source_sp = std::make_unique<sentencepiece::SentencePieceProcessor>();
    target_sp = std::make_unique<sentencepiece::SentencePieceProcessor>();
    const auto source_status = source_sp->Load(source_path);
    if (!source_status.ok()) throw std::runtime_error(source_status.ToString());
    const auto target_status = target_sp->Load(target_path);
    if (!target_status.ok()) throw std::runtime_error(target_status.ToString());
  }

  void load_model(const Direction direction) {
    if (translator) return;
    load_tokenizers(direction);
    const char *configured_root = std::getenv("QUICK_TRANSLATE_MODEL_ROOT");
    const std::string root = configured_root ? configured_root : "Models";
    const std::string pair = direction == EnToZh ? "en-zh" : "zh-en";
    const std::string package_id = direction == EnToZh ? "opus-mt-en-zh-int8" : "opus-mt-zh-en-int8";
    const std::string model_dir = configured_root
        ? root + "/" + package_id + "/1.0.0/ct2/model"
        : root + "/ct2/" + pair + "-int8";

    ctranslate2::ReplicaPoolConfig config;
    config.num_threads_per_replica = 0;
    translator = std::make_unique<ctranslate2::Translator>(
        model_dir, ctranslate2::Device::CPU, ctranslate2::ComputeType::DEFAULT,
        std::vector<int>{0}, false, config);
  }

  void load_model(const std::string &model_dir,
                  const std::string &source_tokenizer,
                  const std::string &target_tokenizer) {
    if (translator) return;
    load_tokenizers(source_tokenizer, target_tokenizer);
    ctranslate2::ReplicaPoolConfig config;
    config.num_threads_per_replica = 0; // CTranslate2 auto-selects a CPU-appropriate value.
    // Let CTranslate2 select its supported Apple CPU fallback for INT8 weights.
    // The model remains the INT8 artifact even if accumulation uses FP32.
    translator = std::make_unique<ctranslate2::Translator>(
        model_dir, ctranslate2::Device::CPU, ctranslate2::ComputeType::DEFAULT,
        std::vector<int>{0}, false, config);
  }

  void unload() {
    translator.reset();
    source_sp.reset();
    target_sp.reset();
  }

  struct TranslationAttempt {
    std::string output;
    bool source_has_unknown = false;
    bool output_has_unknown = false;
  };

  struct NormalizedSurface {
    size_t source_index;
    std::string original;
    std::string normalized;
  };

  std::string visible_surface(std::string value) {
    value = replace_all(std::move(value), "▁", " ");
    const size_t first = value.find_first_not_of(' ');
    if (first == std::string::npos) return "";
    const size_t last = value.find_last_not_of(' ');
    return value.substr(first, last - first + 1);
  }

  std::string sanitize_unknown_source(const std::string &input) {
    if (!contains_unknown_id(*source_sp, input)) return input;

    std::string sanitized;
    size_t copied_until = 0;
    const auto encoded = source_sp->EncodeAsImmutableProto(input);
    for (const auto &piece : encoded.pieces()) {
      if (piece.id() != static_cast<uint32_t>(source_sp->unk_id())) continue;
      sanitized += input.substr(copied_until, piece.begin() - copied_until);
      const auto replacement = normalize_academic_unicode(piece.surface());
      sanitized += replacement == piece.surface()
          ? " "
          : sanitize_unknown_source(replacement);
      copied_until = piece.end();
    }
    sanitized += input.substr(copied_until);
    return sanitized;
  }

  std::vector<std::string> preserved_surfaces(const std::string &input) {
    std::vector<std::string> surfaces;
    const auto encoded = source_sp->EncodeAsImmutableProto(input);
    for (const auto &piece : encoded.pieces()) {
      const auto original = visible_surface(piece.surface());
      const auto normalized = visible_surface(source_sp->Normalize(piece.surface()));
      if (!original.empty()
          && (piece.id() == static_cast<uint32_t>(source_sp->unk_id())
              || original != normalized)) {
        surfaces.push_back(original);
      }
    }
    for (const auto &[symbol, _] : academic_unicode_replacements()) {
      if (input.find(symbol) != std::string::npos
          && symbol != "—" && symbol != "–"
          && symbol != "“" && symbol != "”"
          && symbol != "‘" && symbol != "’") {
        surfaces.push_back(symbol);
      }
    }
    return surfaces;
  }

  std::string preserve_missing_surfaces(
      std::string output,
      const std::vector<std::string> &surfaces,
      const Direction direction) {
    std::vector<std::string> missing;
    for (const auto &surface : surfaces) {
      if (output.find(surface) == std::string::npos
          && std::find(missing.begin(), missing.end(), surface) == missing.end()) {
        missing.push_back(surface);
      }
    }
    if (missing.empty()) return output;

    output += direction == EnToZh ? "\n符号：" : "\nSymbols: ";
    for (size_t index = 0; index < missing.size(); ++index) {
      if (index > 0) output += " ";
      output += missing[index];
    }
    return output;
  }

  std::vector<NormalizedSurface> normalized_surfaces(const std::string &input) {
    std::vector<NormalizedSurface> surfaces;
    const auto encoded = source_sp->EncodeAsImmutableProto(input);
    const auto pieces = encoded.pieces();
    for (size_t index = 0; index < pieces.size(); ++index) {
      const auto original = visible_surface(pieces[index].surface());
      const auto normalized = visible_surface(source_sp->Normalize(pieces[index].surface()));
      if (!original.empty() && original != normalized) {
        surfaces.push_back({index, original, normalized});
      }
    }
    return surfaces;
  }

  void restore_normalized_surfaces(
      std::vector<std::string> &hypothesis,
      const std::vector<std::vector<float>> &attention,
      const std::vector<NormalizedSurface> &surfaces) {
    std::vector<bool> used_targets(hypothesis.size(), false);
    for (const auto &surface : surfaces) {
      size_t best_target = hypothesis.size();
      float best_score = -1;
      for (size_t target_index = 0;
           target_index < hypothesis.size() && target_index < attention.size();
           ++target_index) {
        if (used_targets[target_index]) continue;
        if (surface.source_index >= attention[target_index].size()) continue;
        std::string decoded_piece;
        const std::vector<std::string> target_piece = {hypothesis[target_index]};
        if (!target_sp->Decode(target_piece, &decoded_piece).ok()) continue;
        if (decoded_piece.find(surface.normalized) == std::string::npos) continue;
        if (attention[target_index][surface.source_index] > best_score) {
          best_score = attention[target_index][surface.source_index];
          best_target = target_index;
        }
      }
      if (best_target == hypothesis.size()) continue;

      const bool starts_word = hypothesis[best_target].rfind("▁", 0) == 0;
      hypothesis[best_target] = (starts_word ? "▁" : "") + surface.original;
      used_targets[best_target] = true;
    }
  }

  TranslationAttempt translate_once(const std::string &input) {
    const auto surfaces = normalized_surfaces(input);
    std::vector<std::string> source_tokens;
    const auto encode_status = source_sp->Encode(input, &source_tokens);
    if (!encode_status.ok()) throw std::runtime_error(encode_status.ToString());
    const bool source_has_unknown = contains_unknown_id(*source_sp, input);

    // These OPUS models were made with ct2-transformers-converter. MarianTokenizer
    // appends EOS, so the C++ path must do the same to match the Python reference.
    source_tokens.emplace_back("</s>");

    ctranslate2::TranslationOptions options;
    options.beam_size = 1;
    options.max_decoding_length = 256;
    options.return_scores = false;
    options.return_attention = !surfaces.empty();
    options.replace_unknowns = true;
    const auto results = translator->translate_batch({source_tokens}, options);
    if (results.empty() || results.front().hypotheses.empty()) {
      throw std::runtime_error("Translation returned no hypothesis");
    }

    std::string output;
    auto hypothesis = results.front().hypotheses.front();
    if (!surfaces.empty() && !results.front().attention.empty()) {
      restore_normalized_surfaces(
          hypothesis, results.front().attention.front(), surfaces);
    }
    const auto decode_status = target_sp->Decode(hypothesis, &output);
    if (!decode_status.ok()) throw std::runtime_error(decode_status.ToString());
    return {output, source_has_unknown,
            contains_unknown_piece(hypothesis) || output.find("⁇") != std::string::npos};
  }

  std::string translate(const std::string &input, const Direction direction) {
    const auto surfaces = preserved_surfaces(input);
    const auto prepared = sanitize_unknown_source(input);
    const auto attempt = translate_once(prepared);
    if (!attempt.source_has_unknown && !attempt.output_has_unknown) {
      return preserve_missing_surfaces(attempt.output, surfaces, direction);
    }

    throw std::runtime_error("此离线模型暂时无法解析其中的特殊字符；请简化公式后重试。");
  }
};

struct RuntimeStore {
  std::mutex mutex;
  TranslationRuntime en_to_zh;
  TranslationRuntime zh_to_en;
  std::unordered_map<std::string, std::unique_ptr<TranslationRuntime>> packages;
  thread_local static std::string result;

  TranslationRuntime &runtime(const int direction) {
    return direction == ZhToEn ? zh_to_en : en_to_zh;
  }
};

thread_local std::string RuntimeStore::result;
RuntimeStore store;

TranslationRuntime &package_runtime(const std::string &identity) {
  auto &runtime = store.packages[identity];
  if (!runtime) runtime = std::make_unique<TranslationRuntime>();
  return *runtime;
}

} // namespace

const char *QTNativeBridgeStatus(void) {
  return "CTranslate2 + SentencePiece bridge ready";
}

const char *QTNativeTranslate(const char *input, int direction) {
  try {
    std::lock_guard<std::mutex> lock(store.mutex);
    auto &runtime = store.runtime(direction);
    runtime.load_model(direction == ZhToEn ? ZhToEn : EnToZh);
    const auto model_direction = direction == ZhToEn ? ZhToEn : EnToZh;
    RuntimeStore::result = runtime.translate(input ? input : "", model_direction);
    return RuntimeStore::result.c_str();
  } catch (const std::exception &error) {
    RuntimeStore::result = "ERROR: " + std::string(error.what());
    return RuntimeStore::result.c_str();
  }
}

const char *QTNativeTranslatePackage(const char *input,
                                     const char *package_identity,
                                     const char *model_directory,
                                     const char *source_tokenizer,
                                     const char *target_tokenizer,
                                     int direction) {
  try {
    if (!package_identity || !model_directory || !source_tokenizer || !target_tokenizer) {
      throw std::runtime_error("Language pack paths are missing");
    }
    std::lock_guard<std::mutex> lock(store.mutex);
    const std::string identity(package_identity);
    if (identity.empty()) throw std::runtime_error("Language pack identity is missing");
    auto &runtime = package_runtime(identity);
    runtime.load_model(model_directory, source_tokenizer, target_tokenizer);
    RuntimeStore::result = runtime.translate(input ? input : "", direction == ZhToEn ? ZhToEn : EnToZh);
    return RuntimeStore::result.c_str();
  } catch (const std::exception &error) {
    RuntimeStore::result = "ERROR: " + std::string(error.what());
    return RuntimeStore::result.c_str();
  }
}

int QTNativePrimeTokenizers(int direction) {
  try {
    std::lock_guard<std::mutex> lock(store.mutex);
    store.runtime(direction).load_tokenizers(direction == ZhToEn ? ZhToEn : EnToZh);
    return 0;
  } catch (const std::exception &error) {
    RuntimeStore::result = error.what();
    return 1;
  }
}

int QTNativeLoadModel(int direction) {
  try {
    std::lock_guard<std::mutex> lock(store.mutex);
    store.runtime(direction).load_model(direction == ZhToEn ? ZhToEn : EnToZh);
    return 0;
  } catch (const std::exception &error) {
    RuntimeStore::result = error.what();
    return 1;
  }
}

void QTNativeUnload(int direction) {
  std::lock_guard<std::mutex> lock(store.mutex);
  auto &runtime = store.runtime(direction);
  runtime.unload();
}

void QTNativeUnloadPackage(const char *package_identity) {
  if (!package_identity) return;
  std::lock_guard<std::mutex> lock(store.mutex);
  const auto iterator = store.packages.find(package_identity);
  if (iterator == store.packages.end()) return;
  iterator->second->unload();
  store.packages.erase(iterator);
}
