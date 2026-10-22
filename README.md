# Typeless 🎙️

A lightweight, fully offline, privacy-first push-to-talk dictation tool for macOS. A fast, local replacement for Superwhisper that runs directly in your menu bar.

---

## ✨ Features

- **Push-to-Talk Hotkeys**:
  - **Standard Mode (Hold Right Option)**: Records audio from your microphone while held down, transcribes on release, and automatically pastes into whatever text field has focus.
  - **LLM Cleanup Mode (Hold Right Command)**: Transcribes speech locally, then sends the text to an LLM (configured via `.env`) to fix punctuation, capitalize sentences, and eliminate vocal filler words (`um`, `uh`, `like`, `you know`, `o sea`, `este`) before pasting. If no API key is provided, it falls back to a plain paste.
- **100% Offline Speech Recognition**:
  - Audio captured with `ffmpeg` via macOS `AVFoundation` at 16kHz mono.
  - Local on-device transcription with `whisper.cpp` (`small.en` GGML model by default).
  - No cloud speech APIs, no accounts, and zero telemetry.
- **Smart Auto-Paste & Clipboard Restoration**:
  - Simulates `Cmd+V` into your active app using `CGEvent` (with AppleScript fallback).
  - Automatically restores your previous clipboard content after pasting so you never lose what you had copied.
- **Menu Bar Status & History**:
  - Real-time status indicator: Idle (`mic`), Recording (`🔴 REC`), Transcribing (`⏳ Transcribing`), and Polishing (`✨ Polishing`).
  - Dropdown menu displays your **last 10 transcripts** with one-click copy buttons.
  - Quick access to `~/Dictation`, config directory, and permission checkers.
- **Automatic History Logging & Cleanup**:
  - Appends every transcript with an ISO timestamp to `~/Dictation/YYYY-MM.md`.
  - Temporary audio files are strictly deleted immediately after transcription.

---

## 📋 System Prerequisites

Typeless requires **macOS 13.0+ (Ventura, Sonoma, Sequoia or newer)** and two command-line tools: `ffmpeg` and `whisper.cpp`.

Install them via [Homebrew](https://brew.sh):

```bash
brew install ffmpeg whisper.cpp
```

Verify that they are installed:
```bash
which ffmpeg whisper-cli
```

---

## 🚀 Quick Start

### 1. Download the Whisper Model

Typeless defaults to OpenAI's `small.en` GGML model (~465 MB), offering a sweet spot of speed and accuracy on Apple Silicon and Intel Macs:

```bash
./scripts/download_model.sh small.en
```

This saves `ggml-small.en.bin` to `~/.config/typeless/models/`.

> **Note**: You can also download `tiny.en` (~75 MB) or `base.en` (~142 MB) if you prefer even faster execution:
> ```bash
> ./scripts/download_model.sh base.en
> ```

### 2. Build and Launch

Build the standalone menu bar app:

```bash
make build
```

Launch the app:

```bash
make run
# Or simply:
open Typeless.app
```

To install it to `~/Applications`:
```bash
make install
```

---

## 🔒 Permissions & First-Run Prompts

When you run Typeless for the first time, macOS will ask for two critical permissions:

### 1. Accessibility (Required for Global Push-to-Talk & Paste)
- **Why**: Typeless needs to monitor when you hold/release the **Right Option** or **Right Command** keys system-wide (even when another application has focus) and simulate `Cmd+V` into the active field.
- **How to grant**:
  1. Open **System Settings** > **Privacy & Security** > **Accessibility**.
  2. Ensure the toggle next to **Typeless** (or your terminal if running via CLI) is **ON**.
  3. You can also click **"Check System Permissions..."** in the Typeless menu bar dropdown at any time to verify.

### 2. Microphone (Required for Audio Recording)
- **Why**: `ffmpeg` needs access to your input microphone to record your speech.
- **How to grant**:
  - On your very first recording press, macOS will display an alert asking:
    *“Typeless would like to access the microphone”*.
  - Click **OK**.
  - If ever needed, verify under **System Settings** > **Privacy & Security** > **Microphone**.

---

## ⚙️ Configuration

Typeless creates a configuration folder at `~/.config/typeless/` upon first launch.

### `~/.config/typeless/config.json`

```json
{
  "modelPath": "~/.config/typeless/models/ggml-small.en.bin",
  "whisperCliPath": "/opt/homebrew/bin/whisper-cli",
  "ffmpegPath": "/opt/homebrew/bin/ffmpeg",
  "audioDevice": ":default",
  "language": "en",
  "threads": 4,
  "standardHotkey": "rightOption",
  "cleanupHotkey": "rightCommand",
  "dictationFolder": "~/Dictation",
  "pasteDelayMs": 80,
  "minRecordingDurationSeconds": 0.35,
  "llmProvider": "openai",
  "llmModel": "gpt-4o-mini",
  "llmBaseURL": "https://api.openai.com/v1"
}
```

### Supported Hotkeys
- `rightOption` (default for standard dictation)
- `rightCommand` (default for LLM cleanup mode)
- `rightShift`
- `rightControl`
- `leftOption`

---

## 🧠 LLM Cleanup Mode (`.env`)

To enable the smart cleanup mode (fixing punctuation, casing, and removing stuttering/filler words):

1. Copy `.env.example` to `~/.config/typeless/.env` (or project root `.env`):
   ```bash
   cp .env.example ~/.config/typeless/.env
   ```
2. Add your API key:
   ```bash
   # Supported providers: OpenAI, Anthropic, OpenRouter, Groq, or local Ollama
   OPENAI_API_KEY="sk-..."
   ```
3. Click **"Reload Config & .env"** in the Typeless menu bar.
4. Now, hold **Right Command** to speak in cleanup mode!

> **Fallback**: If no API key is set, holding Right Command simply performs a standard plain paste without calling any remote service.

---

## 📁 Dictation History

All completed dictations are saved to:
```
~/Dictation/YYYY-MM.md
```

Each entry is appended with a timestamp:
```markdown
### 2026-10-22 17:30:45 [Cleaned]

This is the transcribed dictation that was automatically pasted into your application.

---
```

You can view and open the dictation directory at any time from the menu bar item **"Open Dictation Folder (~/Dictation)"**.

---

## 🛠️ Makefile Commands

| Command | Description |
|---|---|
| `make build` | Compiles Swift sources and bundles `Typeless.app` |
| `make model` | Downloads default `small.en` Whisper model |
| `make model-base` | Downloads faster `base.en` Whisper model |
| `make model-tiny` | Downloads ultra-compact `tiny.en` Whisper model |
| `make install` | Installs `Typeless.app` into `~/Applications` |
| `make run` | Builds and opens `Typeless.app` |
| `make check` | Checks Homebrew dependencies (`ffmpeg`, `whisper-cli`) |
| `make clean` | Removes build directories and temporary files |

---

## 🛡️ Privacy & Architecture Guarantee

- **No telemetry**: Typeless makes no analytics or usage calls.
- **No accounts**: No login, tracking, or cloud lock-in.
- **Audio deletion**: The temporary `.wav` file is recorded to `/tmp` and deleted immediately upon transcription completion.
- **Pure Native Swift**: Clean, energy-efficient native macOS code with no Electron overhead.
