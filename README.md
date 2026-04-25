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

Open via **⬡ → Settings…** and pick from the Backend dropdown.

| Backend       | Default URL                                    | Notes                        |
|---------------|------------------------------------------------|------------------------------|
| Ollama        | `http://localhost:11434`                       | Local, no key needed         |
| OpenAI        | `https://api.openai.com/v1`                    | API key required             |
| Anthropic     | `https://api.anthropic.com/v1`                 | API key required             |
| OpenRouter    | `https://openrouter.ai/api/v1`                 | API key required             |
| Azure OpenAI  | *(your endpoint)*                              | API key required             |
| NVIDIA NIM    | `https://integrate.api.nvidia.com/v1`          | API key required (free tier) |
| llama.cpp     | `http://localhost:8080/v1`                     | Local, no key needed         |
| LM Studio     | `http://localhost:1234/v1`                     | Local, no key needed         |

Any OpenAI-compatible server works (vLLM, LiteLLM, etc.) — select **OpenAI** and set the URL.

Selecting a backend auto-fills the URL. **Test** verifies connectivity. Models load automatically.

### NVIDIA NIM (free)

1. Go to [build.nvidia.com](https://build.nvidia.com) → sign in → click any model → **Get API Key**
2. Key starts with `nvapi-`
3. In Veil: select **NVIDIA NIM**, paste key in **API key**

Hundreds of models: Llama, Mistral, Gemma, Qwen, DeepSeek, and more. No credit card.

---

## Voice input

Requires whisper-cpp:

```bash
brew install whisper-cpp
curl -L -o /opt/homebrew/share/whisper-cpp/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

Press **🎙** or the keyboard shortcut → speak → press again → transcribes and sends. All on-device.

Default shortcut: **⌘⌥** (customizable in Settings).

| Model    | Size   | Notes           |
|----------|--------|-----------------|
| `tiny`   | 75 MB  | Fast            |
| `base`   | 150 MB | Good balance    |
| `small`  | 470 MB | Better accuracy |
| `medium` | 1.5 GB | Best accuracy   |

If macOS denied microphone access:

```bash
tccutil reset Microphone com.local.veil
```

---

## Screenshot analysis

Press **⌗** to capture your screen. Veil attaches it to your next message — the model sees your screen.

Works with any vision-capable model (`llava`, `gpt-4o`, `gemma3`, `claude-opus-4-7`, etc.). Screenshot data goes only to your configured backend.

---

## Usage

| Action | How |
|--------|-----|
| Send | **Enter** |
| New line | **Shift+Enter** |
| Stop generation | **⏹** |
| Switch model | Click model name in header |
| Voice input | **🎙** or **⌘⌥** |
| Screenshot | **⌗** → attaches to next message |
| Close | **×** or **Cmd+W** |
| Settings | **⬡ → Settings…** |

---

## Privacy

No telemetry. No analytics. No cloud. Network calls go only to the backend you configure. Ollama and local servers (llama.cpp, LM Studio) run fully on-device — nothing leaves your machine. Audio transcription runs on-device via Whisper. Screenshot data is sent only to your configured backend.
