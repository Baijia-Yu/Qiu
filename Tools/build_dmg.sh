#!/bin/zsh
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
app_path="$project_root/Distribution/Qiu.app"
info_plist="$project_root/Distribution/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
release_suffix=${QIU_RELEASE_SUFFIX:-}
release_label=$version
if [[ -n "$release_suffix" ]]; then
  release_label="$version-$release_suffix"
fi
architecture=$(uname -m)
signing_identity=${QIU_SIGNING_IDENTITY:--}
staging_root=$(mktemp -d "$project_root/.build/qiu-dmg.XXXXXX")

if [[ "$signing_identity" == "-" ]]; then
  dmg_path="$project_root/Distribution/Qiu-$release_label-macOS-$architecture-development.dmg"
else
  dmg_path="$project_root/Distribution/Qiu-$release_label-macOS-$architecture.dmg"
fi

trap 'rm -rf "$staging_root"' EXIT

"$project_root/Tools/package_app.sh"

ditto "$app_path" "$staging_root/Qiu.app"
ln -s /Applications "$staging_root/Applications"

rm -f "$dmg_path"
hdiutil create \
  -volname "Qiu" \
  -srcfolder "$staging_root" \
  -ov \
  -format UDZO \
  "$dmg_path"

if [[ "$signing_identity" != "-" ]]; then
  codesign \
    --force \
    --timestamp \
    --sign "$signing_identity" \
    "$dmg_path"
  codesign --verify --verbose=2 "$dmg_path"
fi

echo "$dmg_path"
