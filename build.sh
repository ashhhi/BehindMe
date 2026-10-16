#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/BehindMe.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/module-cache"

if [[ "$APP_DIR" != "$BUILD_DIR/BehindMe.app" ]]; then
    echo "应用输出路径异常，已停止构建。" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

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
touch "$APP_DIR"

echo "构建完成：$APP_DIR"
