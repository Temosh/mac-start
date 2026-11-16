#!/usr/bin/env bash
# Builds MacStart in release mode, assembles build/MacStart.app, and signs it ad hoc.
# Runs unattended, so the same script works locally and in CI.
#
# Environment:
#   MACSTART_VERSION  CFBundleShortVersionString, X.Y.Z (default 0.0.0)
#   MACSTART_BUILD    CFBundleVersion, a whole number (default 0)
set -euo pipefail

cd "$(dirname "$0")/.."

version="${MACSTART_VERSION:-0.0.0}"
build_number="${MACSTART_BUILD:-0}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: MACSTART_VERSION must look like X.Y.Z, got '$version'" >&2
    exit 1
fi
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "error: MACSTART_BUILD must be a whole number, got '$build_number'" >&2
    exit 1
fi

swift build -c release --product MacStart
bin_path="$(swift build -c release --show-bin-path)"

app="build/MacStart.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin_path/MacStart" "$app/Contents/MacOS/MacStart"
cp Support/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"
iconutil --convert icns --output "$app/Contents/Resources/AppIcon.icns" Support/AppIcon.iconset

codesign --force --sign - "$app"
codesign --verify --strict "$app"

echo "Built $app (version $version, build $build_number)"
