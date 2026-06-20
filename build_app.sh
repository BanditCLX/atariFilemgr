#!/bin/bash
# build_app.sh — AtariFileMgr
# Automatically builds a universal (Intel + Apple Silicon) native macOS .app bundle via CLI (including AppIcon)

set -e

APP_NAME="AtariFileMgr"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_DIR="${CONTENTS_DIR}/MacOS"
RES_DIR="${CONTENTS_DIR}/Resources"

echo "=== 1. Clean up old builds ==="
rm -rf "${APP_DIR}"
swift package clean

echo "=== 2. Compile Universal Binaries (arm64 & x86_64) ==="
echo "Building for Apple Silicon (arm64)..."
swift build -c release --triple arm64-apple-macosx
echo "Building for Intel (x86_64)..."
swift build -c release --triple x86_64-apple-macosx

echo "Merging binaries into Universal format..."
mkdir -p .build/release
lipo -create -output .build/release/${APP_NAME} \
    .build/arm64-apple-macosx/release/${APP_NAME} \
    .build/x86_64-apple-macosx/release/${APP_NAME}

# Paths to the compilation outputs
BINARY_PATH=".build/release/${APP_NAME}"
BUNDLE_PATH=".build/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"

echo "=== 3. Create app structure ==="
mkdir -p "${MAC_DIR}"
mkdir -p "${RES_DIR}"

echo "=== 4. Copy executable and resources ==="
cp "${BINARY_PATH}" "${MAC_DIR}/"

if [ -d "${BUNDLE_PATH}" ]; then
    cp -R "${BUNDLE_PATH}"/* "${RES_DIR}/" || true
fi

# Copy AppIcon if present
if [ -f "Sources/AtariFileMgr/Resources/AppIcon.icns" ]; then
    cp "Sources/AtariFileMgr/Resources/AppIcon.icns" "${RES_DIR}/"
    echo "AppIcon.icns successfully copied to app bundle!"
fi

echo "=== 5. Create Info.plist ==="
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>de.atari.filemgr</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.6</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo "=== Done! ==="
echo "The app was successfully created at '${APP_DIR}'!"
echo "You can now launch it by double-clicking or move it to your Applications folder."
