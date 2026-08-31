#!/bin/zsh
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
destination="$project_root/.native-build/mlx.metallib"
release_url="https://github.com/ml-explore/mlx-swift/releases/download/0.31.3/Cmlx.xcframework.zip"
release_sha256="e0fa04cb5bb2da239691c62c441b1742ff53d701267ba0612bfc8a6b81396d61"
archive=$(mktemp "$project_root/.build/Cmlx.xcframework.XXXXXX.zip")
extract_root=$(mktemp -d "$project_root/.build/Cmlx.xcframework.XXXXXX")

trap 'rm -f "$archive"; rm -rf "$extract_root"' EXIT

if [[ -f "$destination" ]]; then
  exit 0
fi

curl --fail --location --retry 3 "$release_url" --output "$archive"
actual_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
if [[ "$actual_sha256" != "$release_sha256" ]]; then
  echo "MLX runtime checksum mismatch." >&2
  exit 1
fi

unzip -q "$archive" \
  'Cmlx.xcframework/macos-arm64_x86_64/Cmlx.framework/Versions/A/Resources/default.metallib' \
  -d "$extract_root"
mkdir -p "$(dirname "$destination")"
cp \
  "$extract_root/Cmlx.xcframework/macos-arm64_x86_64/Cmlx.framework/Versions/A/Resources/default.metallib" \
  "$destination"
