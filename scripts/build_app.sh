#!/bin/bash
set -euo pipefail

APP_NAME="Typeless"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Building ${APP_NAME}.app ==="

OUTPUT_DIR="${ROOT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${OUTPUT_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "Compiling Swift source files..."
swiftc -O \
    "${ROOT_DIR}"/Sources/Typeless/*.swift \
    -o "${MACOS_DIR}/${APP_NAME}" \
    -framework Cocoa \
    -framework Carbon

echo "Generating Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Typeless</string>
    <key>CFBundleIdentifier</key>
    <string>com.typeless.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Typeless</string>
    <key>CFBundleDisplayName</key>
    <string>Typeless</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Typeless needs access to your microphone to capture audio for offline transcription.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Typeless performs local on-device speech-to-text dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Typeless simulates Cmd+V keystroke to paste dictation into the active focused field.</string>
</dict>
</plist>
EOF

# Copy app icon if available
if [ -f "${ROOT_DIR}/Assets/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/Assets/AppIcon.icns" "${RESOURCES_DIR}/"
fi

echo "Signing application bundle with stable designated requirement..."
codesign --force --deep --sign - --requirements '=designated => identifier "com.typeless.app"' "${OUTPUT_DIR}"

echo "✓ Successfully built: ${OUTPUT_DIR}"
echo "You can now run it with: open ${APP_NAME}.app"
