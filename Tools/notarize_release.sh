#!/bin/zsh
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
info_plist="$project_root/Distribution/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
architecture=$(uname -m)
app_path="$project_root/Distribution/Qiu.app"
dmg_path="$project_root/Distribution/Qiu-$version-macOS-$architecture.dmg"

if [[ -z "${QIU_SIGNING_IDENTITY:-}" ]]; then
  echo "QIU_SIGNING_IDENTITY must be a Developer ID Application identity." >&2
  echo 'Example: Developer ID Application: Your Name (TEAMID)' >&2
  exit 1
fi

if [[ -z "${QIU_NOTARY_PROFILE:-}" ]]; then
  echo "QIU_NOTARY_PROFILE must name credentials stored with notarytool." >&2
  echo "Run: ./Tools/store_notary_credentials.sh qiu-notary" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$QIU_SIGNING_IDENTITY"; then
  echo "The requested signing identity is not available in the keychain:" >&2
  echo "$QIU_SIGNING_IDENTITY" >&2
  exit 1
fi

"$project_root/Tools/build_dmg.sh"

codesign --verify --deep --strict --verbose=2 "$app_path"
codesign --verify --verbose=2 "$dmg_path"

xcrun notarytool submit \
  "$dmg_path" \
  --keychain-profile "$QIU_NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type execute --verbose=2 "$app_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

echo "$dmg_path"
