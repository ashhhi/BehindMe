#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/BehindMe.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/module-cache"

mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

swiftc \
    -swift-version 5 \
    -target arm64-apple-macosx13.0 \
    -O \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework CoreAudio \
    -framework Vision \
    "$PROJECT_DIR/Sources/main.swift" \
    -o "$MACOS_DIR/BehindMe"

codesign --force --deep --sign - "$APP_DIR"

echo "构建完成：$APP_DIR"
