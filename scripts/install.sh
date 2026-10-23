#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Typeless Installation ==="

# 1. Build app if needed
if [ ! -d "${ROOT_DIR}/Typeless.app" ]; then
    echo "Typeless.app not found. Building now..."
    "${ROOT_DIR}/scripts/build_app.sh"
fi

# 2. Setup ~/.config/typeless
CONFIG_DIR="$HOME/.config/typeless"
mkdir -p "${CONFIG_DIR}/models"

if [ ! -f "${CONFIG_DIR}/config.json" ]; then
    echo "Creating initial ${CONFIG_DIR}/config.json..."
    cp "${ROOT_DIR}/config.example.json" "${CONFIG_DIR}/config.json"
fi

if [ ! -f "${CONFIG_DIR}/.env" ]; then
    echo "Creating template ${CONFIG_DIR}/.env..."
    cp "${ROOT_DIR}/.env.example" "${CONFIG_DIR}/.env"
fi

# 3. Copy to /Applications
INSTALL_DIR="/Applications"
if [ ! -w "${INSTALL_DIR}" ]; then
    INSTALL_DIR="$HOME/Applications"
fi
mkdir -p "${INSTALL_DIR}"

echo "Installing Typeless.app to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/Typeless.app"
cp -R "${ROOT_DIR}/Typeless.app" "${INSTALL_DIR}/Typeless.app"

# 4. Setup LaunchAgent for auto-start at login
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "${LAUNCH_AGENTS_DIR}"
if [ -f "${ROOT_DIR}/Assets/com.typeless.app.plist" ]; then
    echo "Installing LaunchAgent for auto-start at login..."
    cp "${ROOT_DIR}/Assets/com.typeless.app.plist" "${LAUNCH_AGENTS_DIR}/com.typeless.app.plist"
fi

echo ""
echo "✓ Installation complete!"
echo "Installed app: ${INSTALL_DIR}/Typeless.app"
echo "Config folder: ${CONFIG_DIR}"
echo "Auto-start:    ${LAUNCH_AGENTS_DIR}/com.typeless.app.plist"
echo ""
echo "Next steps:"
echo "1. Download the Whisper model:   ./scripts/download_model.sh small"
echo "2. Launch the application:       open ${INSTALL_DIR}/Typeless.app"
echo "3. Grant Accessibility & Microphone permissions when prompted by macOS."
