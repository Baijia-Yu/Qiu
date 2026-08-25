#!/bin/zsh
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
tool_environment="$project_root/.model-tools"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required to prepare model assets." >&2
  exit 1
fi

if [[ ! -x "$tool_environment/bin/python" ]]; then
  python3 -m venv "$tool_environment"
fi

"$tool_environment/bin/python" -m pip install --disable-pip-version-check \
  --requirement "$project_root/Tools/model-requirements.txt"

prepare_package() {
  local repository=$1
  local revision=$2
  local package_id=$3
  local package_root="$project_root/Models/LanguagePacks/$package_id/1.0.0"
  local model_root="$package_root/ct2/model"
  local tokenizer_root="$package_root/sentencepiece"

  if [[ ! -f "$package_root/qiu-package.json" ]]; then
    echo "Missing package manifest: $package_root/qiu-package.json" >&2
    exit 1
  fi

  if [[ ! -f "$model_root/model.bin" ]]; then
    mkdir -p "$model_root"
    "$tool_environment/bin/ct2-transformers-converter" \
      --model "$repository" \
      --revision "$revision" \
      --output_dir "$model_root" \
      --quantization int8 \
      --force
  fi

  if [[ ! -f "$tokenizer_root/source.spm" || ! -f "$tokenizer_root/target.spm" ]]; then
    mkdir -p "$tokenizer_root"
    "$tool_environment/bin/hf" download "$repository" source.spm target.spm \
      --revision "$revision" \
      --local-dir "$tokenizer_root"
  fi
}

prepare_package \
  Helsinki-NLP/opus-mt-en-zh \
  408d9bc410a388e1d9aef112a2daba955b945255 \
  opus-mt-en-zh-int8

prepare_package \
  Helsinki-NLP/opus-mt-zh-en \
  cf109095479db38d6df799875e34039d4938aaa6 \
  opus-mt-zh-en-int8

echo "$project_root/Models/LanguagePacks"
