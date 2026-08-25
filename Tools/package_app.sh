#!/bin/zsh
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
app_path="$project_root/Distribution/Qiu.app"
resources="$app_path/Contents/Resources"
icon_source="$project_root/Distribution/Assets/QiuIcon.png"
icon_workspace=$(mktemp -d "$project_root/.build/qiu-icon.XXXXXX")
iconset_path="$icon_workspace/Qiu.iconset"

trap 'rm -rf "$icon_workspace"' EXIT

if [[ ! -f "$project_root/.native-build/libquicktranslate-native.a" ]]; then
  "$project_root/Tools/build_native.sh"
fi

for package_id in opus-mt-en-zh-int8 opus-mt-zh-en-int8; do
  if [[ ! -f "$project_root/Models/LanguagePacks/$package_id/1.0.0/ct2/model/model.bin" ]]; then
    echo "Language pack assets are missing. Run: ./Tools/prepare_models.sh" >&2
    exit 1
  fi
done

swift build -c release --package-path "$project_root"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$resources/LanguagePacks"
cp "$project_root/Distribution/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/.build/release/QuickTranslate" "$app_path/Contents/MacOS/QuickTranslate"
mkdir -p "$iconset_path"
sips -z 16 16 "$icon_source" --out "$iconset_path/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_path/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_path/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_source" --out "$iconset_path/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_source" --out "$iconset_path/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_path/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_path/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_path/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_path/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$icon_source" --out "$iconset_path/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset_path" -o "$resources/Qiu.icns"
for package_id in opus-mt-en-zh-int8 opus-mt-zh-en-int8; do
  package_root="$resources/LanguagePacks/$package_id/1.0.0"
  ditto "$project_root/Models/LanguagePacks/$package_id/1.0.0" "$package_root"
done
codesign --force --deep --sign - "$app_path"
echo "$app_path"
