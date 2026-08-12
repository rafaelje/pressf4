#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_root"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid CFBundleShortVersionString: $version" >&2
  exit 1
fi

release_dir=${RELEASE_DIR:-"$project_root/dist"}
signing_identity=${SIGN_IDENTITY:--}
arm_build="$project_root/build/release-arm64"
intel_build="$project_root/build/release-x86_64"
universal_build="$project_root/build/release-universal"
universal_app="$universal_build/pressf4.app"

make BUILD_DIR="$arm_build" ARCH=arm64 SIGN_IDENTITY="$signing_identity"
make BUILD_DIR="$intel_build" ARCH=x86_64 SIGN_IDENTITY="$signing_identity"

mkdir -p "$universal_build"
rm -rf "$universal_app"
ditto "$arm_build/pressf4.app" "$universal_app"

lipo -create \
  "$arm_build/pressf4.app/Contents/MacOS/pressf4" \
  "$intel_build/pressf4.app/Contents/MacOS/pressf4" \
  -output "$universal_app/Contents/MacOS/pressf4"

codesign --force --sign "$signing_identity" \
  --entitlements Resources/CapturaApp.entitlements \
  --options runtime \
  "$universal_app"

lipo "$universal_app/Contents/MacOS/pressf4" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "$universal_app"

mkdir -p "$release_dir"
dmg_path="$release_dir/pressf4_${version}_universal.dmg"
dmg_staging=$(mktemp -d "$project_root/build/pressf4-dmg.XXXXXX")
trap 'rm -rf "$dmg_staging"' EXIT

ditto "$universal_app" "$dmg_staging/pressf4.app"
ln -s /Applications "$dmg_staging/Applications"
rm -f "$dmg_path"

hdiutil create \
  -volname "PressF4 $version" \
  -srcfolder "$dmg_staging" \
  -ov \
  -format UDZO \
  "$dmg_path"

if [[ "$signing_identity" != "-" ]]; then
  codesign --force --sign "$signing_identity" --timestamp "$dmg_path"
  codesign --verify --verbose=2 "$dmg_path"
fi

hdiutil verify "$dmg_path"
echo "$dmg_path"
