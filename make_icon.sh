#!/bin/bash
# make_icon.sh — AtariFileMgr
# Generates a native macOS AppIcon.icns from the high-resolution PNG icon

set -e

SRC_PNG="Sources/AtariFileMgr/Resources/AppIcon.png"
ICONSET_DIR="AppIcon.iconset"

if [ ! -f "${SRC_PNG}" ]; then
    echo "ERROR: Source PNG file not found at '${SRC_PNG}'!"
    exit 1
fi

echo "=== 1. Create temporary iconset directory ==="
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

echo "=== 2. Generate various macOS icon sizes ==="
sips -s format png -z 16 16     "${SRC_PNG}" --out "${ICONSET_DIR}/icon_16x16.png"
sips -s format png -z 32 32     "${SRC_PNG}" --out "${ICONSET_DIR}/icon_16x16@2x.png"
sips -s format png -z 32 32     "${SRC_PNG}" --out "${ICONSET_DIR}/icon_32x32.png"
sips -s format png -z 64 64     "${SRC_PNG}" --out "${ICONSET_DIR}/icon_32x32@2x.png"
sips -s format png -z 128 128   "${SRC_PNG}" --out "${ICONSET_DIR}/icon_128x128.png"
sips -s format png -z 256 256   "${SRC_PNG}" --out "${ICONSET_DIR}/icon_128x128@2x.png"
sips -s format png -z 256 256   "${SRC_PNG}" --out "${ICONSET_DIR}/icon_256x256.png"
sips -s format png -z 512 512   "${SRC_PNG}" --out "${ICONSET_DIR}/icon_256x256@2x.png"
sips -s format png -z 512 512   "${SRC_PNG}" --out "${ICONSET_DIR}/icon_512x512.png"
sips -s format png -z 1024 1024 "${SRC_PNG}" --out "${ICONSET_DIR}/icon_512x512@2x.png"

echo "=== 3. Generate native macOS AppIcon.icns ==="
iconutil -c icns "${ICONSET_DIR}"
mkdir -p Sources/AtariFileMgr/Resources
mv AppIcon.icns Sources/AtariFileMgr/Resources/

echo "=== 4. Clean up temporary iconset files ==="
rm -rf "${ICONSET_DIR}"

echo "=== DONE! ==="
echo "AppIcon.icns was successfully created under 'Sources/AtariFileMgr/Resources/AppIcon.icns'!"
