#!/usr/bin/env bash
#
# build-app-iconset.sh
#
# Generates the 1024x1024 master PNG via generate-app-icon.swift, resizes it to
# all required macOS AppIcon variants with sips, then writes the appiconset and
# its parent xcassets Contents.json files.
#
# Usage (from repo root):
#   tools/build-app-iconset.sh
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
MASTER_PNG="$TOOLS_DIR/AppIcon-1024.png"

ASSETS_DIR="$REPO_ROOT/Sources/TypeToTalk/Resources/Assets.xcassets"
APPICON_DIR="$ASSETS_DIR/AppIcon.appiconset"

echo "==> Generating master 1024x1024 icon"
swift "$TOOLS_DIR/generate-app-icon.swift"

if [ ! -f "$MASTER_PNG" ]; then
    echo "ERROR: $MASTER_PNG was not produced" >&2
    exit 1
fi

echo "==> Preparing $APPICON_DIR"
mkdir -p "$APPICON_DIR"
# Clean previously generated PNGs so renames/removals don't leave orphans.
rm -f "$APPICON_DIR"/icon_*.png

# Pairs of "<filename>:<pixel-size>" for the macOS AppIcon set.
# Each logical size is provided at @1x and @2x scales.
ENTRIES=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for entry in "${ENTRIES[@]}"; do
    name="${entry%%:*}"
    size="${entry##*:}"
    out="$APPICON_DIR/$name"
    echo "  -> $name (${size}x${size})"
    sips -Z "$size" "$MASTER_PNG" --out "$out" >/dev/null
done

echo "==> Writing AppIcon.appiconset/Contents.json"
cat > "$APPICON_DIR/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "==> Writing Assets.xcassets/Contents.json"
cat > "$ASSETS_DIR/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "==> Done. Asset catalog at: $ASSETS_DIR"
