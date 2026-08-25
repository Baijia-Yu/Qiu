#!/bin/zsh
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
source_root="$project_root/Vendor/CTranslate2"
build_root="$project_root/.native-build/ctranslate2"
output_library="$project_root/.native-build/libquicktranslate-native.a"

if [[ ! -f "$source_root/CMakeLists.txt" || \
      ! -f "$source_root/third_party/ruy/CMakeLists.txt" || \
      ! -f "$source_root/third_party/spdlog/CMakeLists.txt" ]]; then
  echo "Initializing native source dependencies..."
  git -C "$project_root" submodule update --init --recursive
fi

if [[ ! -f "$source_root/CMakeLists.txt" || \
      ! -f "$source_root/third_party/ruy/CMakeLists.txt" || \
      ! -f "$source_root/third_party/spdlog/CMakeLists.txt" ]]; then
  echo "CTranslate2 source dependencies are incomplete." >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "CMake is required. Install it with: brew install cmake" >&2
  exit 1
fi

architecture=$(uname -m)
case "$architecture" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported macOS architecture: $architecture" >&2
    exit 1
    ;;
esac

cmake -S "$source_root" -B "$build_root" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$architecture" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_CLI=OFF \
  -DBUILD_TESTS=OFF \
  -DOPENMP_RUNTIME=NONE \
  -DWITH_ACCELERATE=ON \
  -DWITH_CUDA=OFF \
  -DWITH_CUDNN=OFF \
  -DWITH_DNNL=OFF \
  -DWITH_MKL=OFF \
  -DWITH_OPENBLAS=OFF \
  -DWITH_RUY=ON

cmake --build "$build_root" --target ctranslate2 --parallel

native_libraries=("$build_root/libctranslate2.a")
while IFS= read -r archive; do
  native_libraries+=("$archive")
done < <(find "$build_root/third_party/ruy" -type f -name '*.a' | sort)

mkdir -p "$(dirname "$output_library")"
/usr/bin/libtool -static -o "$output_library" "${native_libraries[@]}"
echo "$output_library"
