#!/bin/bash

# Build release version
swift build -c release

# Create app bundle structure
APP_NAME="Media Exporter"
APP_BUNDLE="$HOME/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Creating app bundle at: ${APP_BUNDLE}"

# Remove existing bundle if it exists
rm -rf "${APP_BUNDLE}"

# Create directory structure
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp ".build/release/media-exporter" "${MACOS_DIR}/media-exporter"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.mediaexporter.app</string>
    <key>CFBundleName</key>
    <string>Media Exporter</string>
    <key>CFBundleDisplayName</key>
    <string>Media Exporter</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>media-exporter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>This app needs access to your Photos library to export photos and videos within the specified date range.</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
EOF

echo "App bundle created successfully!"
echo "You can now run: open '${APP_BUNDLE}'"
echo "Or launch it to trigger Photos permission dialog."