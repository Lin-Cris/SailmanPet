#!/bin/zsh

set -euo pipefail

LFP_SCRIPT_DIR=${0:A:h}
LFP_PROJECT_DIR=${LFP_SCRIPT_DIR:h}
LFP_BUILD_DIR="$LFP_PROJECT_DIR/.build"
LFP_MODULE_CACHE="$LFP_BUILD_DIR/module-cache"
LFP_APP_DIR="$LFP_BUILD_DIR/LuffyPet.app"
LFP_APP_EXECUTABLE="$LFP_APP_DIR/Contents/MacOS/LuffyPet"

mkdir -p \
  "$LFP_BUILD_DIR" \
  "$LFP_MODULE_CACHE" \
  "$LFP_APP_DIR/Contents/MacOS"
export CLANG_MODULE_CACHE_PATH="$LFP_MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="$LFP_MODULE_CACHE"
/usr/bin/swiftc \
  -O \
  -module-cache-path "$LFP_MODULE_CACHE" \
  -framework AppKit \
  -framework QuartzCore \
  "$LFP_PROJECT_DIR/Sources/LuffyPet/main.swift" \
  -o "$LFP_APP_EXECUTABLE"

cp "$LFP_PROJECT_DIR/Resources/Info.plist" "$LFP_APP_DIR/Contents/Info.plist"
echo "Built $LFP_APP_DIR"
