#!/bin/bash
# Packages build/ExeDock.app into dist/ExeDock-<version>.dmg with a drag-to-Applications layout.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-1.0.0}"
APP_BUNDLE="build/ExeDock.app"
STAGING_DIR="build/dmg-staging"
DMG_PATH="dist/ExeDock-${VERSION}.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "error: $APP_BUNDLE not found - run Scripts/build_app.sh first" >&2
    exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" dist
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "ExeDock" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

rm -rf "$STAGING_DIR"
echo "==> Built $DMG_PATH"
