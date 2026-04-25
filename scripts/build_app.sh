#!/bin/zsh
set -euo pipefail

CONFIGURATION="${1:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/TypeToTalkDerivedData}"
BUILD_NUMBER="$(zsh ./scripts/generate_build_number.sh "$DERIVED_DATA_PATH")"

xcodegen generate
xcodebuild \
  -project TypeToTalk.xcodeproj \
  -scheme TypeToTalk \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

echo "Built app:"
echo "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/TypeToTalk.app"
echo "Build number: $BUILD_NUMBER"
