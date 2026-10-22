#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ApplicationManager"
EXEC_NAME="ApplicationManager"
SWIFT_BIN="appmanager"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
SRC_DIR="$ROOT/ApplicationManager"

XCODE_DEV="/Applications/Xcode.app/Contents/Developer"

if ! xcode-select -p &>/dev/null; then
    if [[ -d "$XCODE_DEV" ]]; then
        export DEVELOPER_DIR="$XCODE_DEV"
        echo "Using Xcode at $XCODE_DEV (no sudo required)"
    else
        echo "Error: Apple developer tools are not installed."
        echo ""
        echo "Install Xcode from the App Store, or run: xcode-select --install"
        exit 1
    fi
fi

echo "Building $APP_NAME..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"

swiftc \
    -O \
    -o "$MACOS_DIR/$SWIFT_BIN" \
    "$SRC_DIR/main.swift" \
    "$SRC_DIR/AppDelegate.swift" \
    "$SRC_DIR/LibraryApp.swift" \
    "$SRC_DIR/LibraryStore.swift" \
    "$SRC_DIR/AppBundleIcon.swift" \
    "$SRC_DIR/MenuBarSymbolDiscovery.swift" \
    "$SRC_DIR/MenuBarAppsDiscovery.swift" \
    "$SRC_DIR/LaunchAtLogin.swift" \
    "$SRC_DIR/MenuBarOnlyApps.swift" \
    -framework AppKit \
    -framework ServiceManagement \
    -framework Carbon

# The bundle executable is a compiled C launcher that posix_spawns the Swift
# binary (see launcher.c for why it must spawn rather than exec).
clang -O2 -Wall -o "$MACOS_DIR/$EXEC_NAME" "$ROOT/launcher.c"

cp "$SRC_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

PLIST="$CONTENTS_DIR/Info.plist"
for key_value in \
    "CFBundleExecutable:$EXEC_NAME" \
    "CFBundleIdentifier:com.applicationmanager.app" \
    "CFBundleName:$APP_NAME" \
    "LSMinimumSystemVersion:13.0"; do
    key="${key_value%%:*}"
    value="${key_value#*:}"
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST"
done

codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
echo "Run with: open \"$APP_DIR\""
