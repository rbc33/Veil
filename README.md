# OllamaChat

Native macOS menubar client for Ollama. Lives in the menu bar, invisible to screen sharing in Google Meet, Zoom, Teams, and any capture app.

## Requirements

- macOS 13 or later
- [Ollama](https://ollama.com) installed and running
- Xcode Command Line Tools (`xcode-select --install`)

## Installation

### 1. Clone or download the project

```bash
git clone <repo> OllamaChat
cd OllamaChat
```

### 2. Build the .app

```bash
bash build.sh
```

This compiles the binary, creates `OllamaChat.app`, and signs it with an ad-hoc signature.

### 3. Run

```bash
open OllamaChat.app
```

The **⬡** icon appears in the menu bar. No Dock icon.

---

## Audio input (optional)

To use the microphone you need **whisper.cpp** and a transcription model.

### Install whisper-cpp

```bash
brew install whisper-cpp
```

### Download a model

Models are stored in `/opt/homebrew/share/whisper-cpp/` and detected automatically by the app.

| Model | Size | Speed | Quality |
|-------|------|-------|---------|
| `tiny` | 75 MB | Very fast | Basic |
| `base` | 150 MB | Fast | Good |
| `small` | 470 MB | Medium | Very good |
| `medium` | 1.5 GB | Slow | Excellent |

Download `base` (recommended):

```bash
curl -L --output /opt/homebrew/share/whisper-cpp/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

Download `tiny` (lightest):

```bash
curl -L --output /opt/homebrew/share/whisper-cpp/ggml-tiny.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
```

### Microphone permissions

The first time you press 🎙 macOS will ask for microphone access. If you accidentally denied it:

```bash
tccutil reset Microphone com.local.ollamachat
```

Reopen the app and it will prompt again.

---

## Usage

### Chat

- Type in the text field and press **Enter** or **↵** to send
- While Ollama is generating, the **↵** button turns into **⏹** — press it to cancel

### Microphone

- Press **🎙** to start recording (turns red)
- Press again to stop → transcribes with Whisper → sends automatically
- Shows **⏳** while transcribing

### Switching models

Click the model name in the top left to open a dropdown with all models installed in Ollama.

### Changing the Ollama URL

To connect to Ollama on another machine:

1. Click **⬡** in the menu bar
2. Select "Change Ollama URL…"
3. Enter the new URL, e.g. `http://192.168.1.50:11434`

The URL is saved and persists across sessions.

### Launch at login

```bash
cp -r OllamaChat.app /Applications/
```

Then go to **System Settings → General → Login Items** and add `OllamaChat.app`.

---

## Privacy

The chat window is invisible to any screen capture app (Google Meet, Zoom, Teams, QuickTime, `Cmd+Shift+5`). Uses the public AppKit API `NSWindow.sharingType = .none`.

All processing is local — audio is transcribed by Whisper on your machine and never leaves it.