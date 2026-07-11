#!/bin/bash
# create_dmg.sh — AtariFileMgr
# Packages the built AtariFileMgr.app into a compressed macOS DMG file with an Applications shortcut.

set -e

APP_NAME="AtariFileMgr"
DMG_NAME="AtariFileMgr-Release.dmg"
TEMP_DIR="dmg_temp"

echo "=== 1. Cleaning up old DMG and temp files ==="
rm -rf "${TEMP_DIR}"
rm -f "${DMG_NAME}"

echo "=== 2. Creating temporary directory ==="
mkdir -p "${TEMP_DIR}"

echo "=== 3. Copying ${APP_NAME}.app to temporary directory ==="
if [ ! -d "${APP_NAME}.app" ]; then
    echo "ERROR: ${APP_NAME}.app does not exist. Please run ./build_app.sh first."
    exit 1
fi
cp -R "${APP_NAME}.app" "${TEMP_DIR}/"

echo "=== 4. Creating Applications symlink ==="
ln -s /Applications "${TEMP_DIR}/Applications"

echo "=== 5. Building DMG ==="
hdiutil create -volname "${APP_NAME}" -srcfolder "${TEMP_DIR}" -ov -format UDZO "${DMG_NAME}"

echo "=== 6. Cleaning up temporary directory ==="
rm -rf "${TEMP_DIR}"

echo "=== DONE! ${DMG_NAME} has been built successfully! ==="
