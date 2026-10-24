#!/bin/bash
# Builds a universal (Apple Silicon + Intel) PortableHiDPI.app and a zip for release.
# Usage: scripts/build-app.sh            -> build/PortableHiDPI.app, build/PortableHiDPI.zip
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PortableHiDPI"

APP=build/PortableHiDPI.app
rm -rf "$APP" build/PortableHiDPI.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PortableHiDPI"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature (no Apple Developer ID). Gatekeeper will ask once on first launch.
# The bundle has a single executable; sign it explicitly (no --deep) and verify.
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=1 "$APP"

ditto -c -k --keepParent "$APP" build/PortableHiDPI.zip
echo "Built $APP and build/PortableHiDPI.zip"
