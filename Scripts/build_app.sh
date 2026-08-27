#!/bin/bash
# Builds Playdock.app without Xcode: `swift build` + manual .app assembly + codesign.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# PRODUCT_NAME is what Finder/Dock/Spotlight show - the app's actual public name. EXECUTABLE_NAME is
# the Swift package target's name (see Package.swift / CFBundleExecutable in Info.plist.template),
# kept as "ExeDock" on purpose: it's an internal filename nobody sees, and matching it to
# ~/Library/Application Support/ExeDock keeps existing installs' bottles/settings intact across the
# Playdock rename instead of orphaning them.
PRODUCT_NAME="Playdock"
EXECUTABLE_NAME="ExeDock"
APP_BUNDLE="build/${PRODUCT_NAME}.app"
ICONSET="Sources/ExeDock/Resources/AppIcon.iconset"

echo "==> swift build -c release"
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/${EXECUTABLE_NAME}" "$APP_BUNDLE/Contents/MacOS/${EXECUTABLE_NAME}"
cp "Info.plist.template" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Building AppIcon.icns"
if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "iconutil not found, skipping icon"
fi

echo "==> Codesigning"
IDENTITY="Apple Development: thecleanestaccount@icloud.com (RUC8R3W68Y)"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --deep --force --options runtime --sign "$IDENTITY" "$APP_BUNDLE"
else
    echo "Falling back to ad-hoc signature"
    codesign --deep --force --sign - "$APP_BUNDLE"
fi

codesign --verify --verbose "$APP_BUNDLE"
echo "==> Built $APP_BUNDLE"
