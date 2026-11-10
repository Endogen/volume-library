#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-debug}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$(pwd)/build/Volume Library.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/VolumeLibrary" "$app/Contents/MacOS/VolumeLibrary"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier local.volumelibrary.app "$app"
printf 'Built %s\n' "$app"
