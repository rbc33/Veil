# Veil

macOS menu bar AI chat that **does not appear in screen sharing, recordings, or screenshots**.

Built for Ollama, OpenAI-compatible APIs (NVIDIA NIM, llama.cpp, LM Studio), and OpenAI itself. No Dock icon. No trace on screen captures.

---

## Invisible by design

Veil uses `NSWindow.sharingType = .none` — a public AppKit API that marks the window as excluded from all capture pipelines at the display server level.

**Not visible in:**
- Google Meet, Zoom, Microsoft Teams — screen share
- QuickTime, OBS, `Cmd+Shift+5` — screen recording
- Any app using `CGWindowListCreateImage` or `SCScreenshotManager`

The window is **only visible to you**, on your physical screen.

---

## Requirements

- macOS 13 or later
- Xcode Command Line Tools: `xcode-select --install`
- At least one backend (see below)
- whisper-cpp

---

## Installation

```bash
git clone <repo> && cd Veil
bash build.sh
open Veil.app
```

Or open the `.dmg`, drag Veil to Applications.

The **⬡** icon appears in the menu bar. Click it → **Open chat**.

---

## Backends

Configure via **⬡ → Configure backend…**

| Backend | URL |
|---------|-----|
| Ollama (default) | `http://localhost:11434` |
| llama.cpp | `http://localhost:8080/v1` |
| LM Studio | `http://localhost:1234/v1` |
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1` |
| OpenAI | `https://api.openai.com/v1` |

The config panel loads available models on open and has a **Test** button to verify connectivity.

---

## Voice input (optional)

Requires **whisper.cpp**:

```bash
brew install whisper-cpp
curl -L -o /opt/homebrew/share/whisper-cpp/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

| Model | Size | Quality |
|-------|------|---------|
| `tiny` | 75 MB | Basic |
| `base` | 150 MB | Good |
| `small` | 470 MB | Very good |
| `medium` | 1.5 GB | Excellent |

Press **🎙** to record → press again to stop → transcribes and sends automatically.

First use: macOS will ask for microphone access. If you denied it:

```bash
tccutil reset Microphone com.local.veil
```

---

## Usage

| Action | How |
|--------|-----|
| Send message | Type + **Enter** |
| Cancel generation | Click **⏹** |
| Switch model | Click model name → dropdown |
| Record voice | **🎙** → record → **🎙** again |
| Close window | **×** in corner or **Cmd+W** |
| Configure backend | **⬡** → Configure backend… |

---

## Privacy

All processing is local. Audio is transcribed by Whisper on your machine and never sent anywhere. No telemetry, no analytics, no network calls except to the backend you configure.
