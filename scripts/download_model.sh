#!/bin/bash
set -euo pipefail

RAW_MODEL="${1:-small.en}"
MODEL_NAME="$(basename "${RAW_MODEL}")"
TARGET_DIR="${2:-$HOME/.config/typeless/models}"
MODEL_FILE="ggml-${MODEL_NAME}.bin"
TARGET_PATH="${TARGET_DIR}/${MODEL_FILE}"

echo "=== Typeless Whisper Model Downloader ==="
echo "Model name: ${MODEL_NAME}"
echo "Target path: ${TARGET_PATH}"

mkdir -p "${TARGET_DIR}"

if [ -f "${TARGET_PATH}" ]; then
    echo "✓ Model ${MODEL_FILE} already exists at ${TARGET_PATH}."
    echo "Size: $(du -h "${TARGET_PATH}" | cut -f1)"
    exit 0
fi

URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"

echo "Downloading ${MODEL_FILE} from Hugging Face..."
echo "URL: ${URL}"

TEMP_FILE="${TARGET_PATH}.tmp"
trap 'rm -f "${TEMP_FILE}"' ERR INT TERM

if command -v curl >/dev/null 2>&1; then
    curl -L --progress-bar -o "${TEMP_FILE}" "${URL}"
elif command -v wget >/dev/null 2>&1; then
    wget --progress=bar:force -O "${TEMP_FILE}" "${URL}"
else
    echo "Error: Neither curl nor wget was found." >&2
    exit 1
fi

mv "${TEMP_FILE}" "${TARGET_PATH}"
echo ""
echo "✓ Successfully downloaded ${MODEL_FILE} to ${TARGET_PATH}!"
echo "Size: $(du -h "${TARGET_PATH}" | cut -f1)"
