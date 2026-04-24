# Veil

macOS menu bar AI chat. **Invisible to screen sharing, screen recording, and screenshots.**

No Dock icon. No trace on capture.

---

## How it works

`NSWindow.sharingType = .none` — a public AppKit API that excludes the window from the display server's capture pipeline before any recording app sees it.

**Invisible in:**

- Zoom, Google Meet, Microsoft Teams screen share
- QuickTime, OBS, Cmd+Shift+5 screen recording
- Anything using `CGWindowListCreateImage` or `SCScreenshotManager`

Only you see it. On your physical display.

---

## Install

**From source:**

```bash
git clone <repo> && cd Veil
bash build.sh
open Veil.app
```

**From DMG:** open `Veil-v1.0.0.dmg`, drag to Applications.

The **⬡** icon appears in the menu bar. Click → **Open chat**.

Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

---

## Backends

Open via **⬡ → Settings…**

| Backend          | URL                                       |
|------------------|-------------------------------------------|
| Ollama (default) | `http://localhost:11434`                  |
| llama.cpp        | `http://localhost:8080/v1`                |
| LM Studio        | `http://localhost:1234/v1`                |
| NVIDIA NIM       | `https://integrate.api.nvidia.com/v1`     |
| OpenAI           | `https://api.openai.com/v1`               |

Settings fetches available models automatically. Use **Test** to verify connectivity before saving.

### NVIDIA NIM API key

NIM gives free API access to hundreds of models — Llama, Mistral, Gemma, Qwen, DeepSeek, and more. No credit card required.

1. Go to [https://build.nvidia.com](https://build.nvidia.com)
2. Sign in or create a free account
3. Click any model → **Get API Key**
4. Copy the key (starts with `nvapi-`)
5. In Veil: select **OpenAI-compatible**, set URL to `https://integrate.api.nvidia.com/v1`, paste the key in **API key**

Browse all available models at [build.nvidia.com/explore/discover](https://build.nvidia.com/explore/discover).

---

## Voice input

Requires whisper-cpp:

```bash
brew install whisper-cpp
curl -L -o /opt/homebrew/share/whisper-cpp/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

Press **🎙** or use the keyboard shortcut → speak → press again → transcribes and sends. All on-device.

Default shortcut: **⌘⌥** (customizable in Settings).

| Model    | Size   | Notes                |
|----------|--------|----------------------|
| `tiny`   | 75 MB  | Fast, basic accuracy |
| `base`   | 150 MB | Good balance         |
| `small`  | 470 MB | Better accuracy      |
| `medium` | 1.5 GB | Best accuracy        |

If macOS denied microphone access:

```bash
tccutil reset Microphone com.local.veil
```

---

## Screenshot analysis

Press **⌗** to capture your screen. Veil attaches it to your next message — the model sees your screen.

Works with any vision-capable model (e.g. `llava`, `gpt-4o`, `gemma3`). Screenshot data is sent only to the backend you configured.

---

## Conversation context

Full history is maintained within each session. Every message includes all prior exchanges so the model remembers context. Resets when you close the window.

---

## Usage

| Action | How |
|--------|-----|
| Send | Type + **Enter** |
| Stop generation | **⏹** |
| Switch model | Click model name in header |
| Voice input | **🎙** or **⌘⌥** (default) |
| Screenshot | **⌗** → sends with next message |
| Close | **×** or **Cmd+W** |
| Settings | **⬡ → Settings…** |

---

## Privacy

No telemetry. No analytics. No cloud. Network calls go only to the backend you configure — Ollama runs fully local, nothing leaves your machine. Audio transcription runs on-device via Whisper. Screenshot data is sent only to your configured backend.
