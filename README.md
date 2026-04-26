<div align="center">

<img src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple&logoColor=white" />
<img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift&logoColor=white" />
<img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" />
<img src="https://img.shields.io/github/stars/rbc33/Veil?style=flat-square&color=yellow" />

<br><br>

# ⬡ Veil

### macOS AI chat. Invisible to screen sharing.

*Zoom, Teams, Meet, OBS, QuickTime — none of them see it. Only you do.*

<br>

[**Download DMG**](https://github.com/rbc33/Veil/releases) · [**Build from source**](#install) · [**Report bug**](https://github.com/rbc33/Veil/issues)

</div>

---

## Why Veil?

You're in a work call. You need to ask an AI something. You open ChatGPT — and everyone sees it.

Veil solves this. It lives in your menu bar, invisible to every screen recorder and screen share tool on macOS. No one sees it but you.

```swift
// The entire secret: one native AppKit API
window.sharingType = .none
```

That's it. A public, documented API that removes the window from macOS's display capture pipeline — before Zoom, OBS, or `CGWindowListCreateImage` ever touches it.

---

## Features

| | |
|---|---|
| 🫥 **Invisible by default** | Hidden from Zoom, Teams, Meet, OBS, QuickTime, Cmd+Shift+5 |
| 🍎 **Menu bar only** | No Dock icon. No trace. Appears as **⬡** |
| 🤖 **Multi-backend** | Ollama, OpenAI, Claude, OpenRouter, NVIDIA NIM, LM Studio, llama.cpp |
| 🎙 **Voice input** | On-device transcription via whisper-cpp |
| 📸 **Screenshot analysis** | You see the screen. Recorders don't see Veil. |
| 🔒 **Zero telemetry** | No analytics, no cloud, no tracking |

---

## Install

**Option A — DMG (fastest)**

Download [`Veil-v1.0.1.dmg`](https://github.com/rbc33/Veil/releases), drag to Applications, open.

**Option B — Build from source**

```bash
# Requirements: macOS 13+, Xcode Command Line Tools
xcode-select --install

git clone https://github.com/rbc33/Veil.git && cd Veil
bash build.sh
open Veil.app
```

The **⬡** icon appears in your menu bar. Click → **Open chat**.

---

## How the invisibility works

macOS exposes a window-level API that controls whether a window participates in the display server's capture pipeline:

```swift
NSWindow.sharingType = .none   // excluded from capture
NSWindow.sharingType = .readOnly   // default — visible to recorders
```

Setting `.none` tells the display server to exclude this window from all capture operations **at the compositor level** — before any recording application, screenshot tool, or capture API (`CGWindowListCreateImage`, `SCStreamConfiguration`, etc.) can observe it.

**Result:** The window renders normally on your physical display. It simply does not exist to capture pipelines.

This is a public, documented AppKit API. No hacks. No injection. No overlay tricks.

---

## Backends

Open **⬡ → Settings…** and pick your backend:

| Backend | URL | Notes |
|---|---|---|
| **Ollama** | `http://localhost:11434` | Local, no key |
| **OpenAI** | `https://api.openai.com/v1` | API key required |
| **Anthropic** | `https://api.anthropic.com/v1` | API key required |
| **OpenRouter** | `https://openrouter.ai/api/v1` | API key required |
| **NVIDIA NIM** | `https://integrate.api.nvidia.com/v1` | Free tier available |
| **LM Studio** | `http://localhost:1234/v1` | Local, no key |
| **llama.cpp** | `http://localhost:8080/v1` | Local, no key |
| **Azure OpenAI** | *(your endpoint)* | API key required |

Any OpenAI-compatible server works — select **OpenAI** and set the URL.

### Free models via NVIDIA NIM

1. Go to [build.nvidia.com](https://build.nvidia.com) → sign in → any model → **Get API Key**
2. Key starts with `nvapi-`
3. In Veil: select **NVIDIA NIM**, paste key

Hundreds of models (Llama, Mistral, Gemma, Qwen, DeepSeek) — no credit card required.

---

## Voice input

```bash
brew install whisper-cpp
curl -L -o /opt/homebrew/share/whisper-cpp/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

Press **🎙** or **⌘⌥** → speak → press again → transcribed and sent. Fully on-device.

| Model | Size | Quality |
|---|---|---|
| `tiny` | 75 MB | Fast |
| `base` | 150 MB | Balanced ✓ |
| `small` | 470 MB | Better |
| `medium` | 1.5 GB | Best |

If macOS denied microphone access:

```bash
tccutil reset Microphone com.local.veil
```

### Internal audio (system sound)

macOS does not expose system audio to apps directly. Use [BlackHole](https://github.com/ExistentialAudio/BlackHole) to route it:

```bash
brew install blackhole-2ch
```

1. Open **Audio MIDI Setup** (`/Applications/Utilities/`)
2. Click **+** → **Create Aggregate Device**
3. Check both **BlackHole 2ch** and your microphone
4. Click **+** → **Create Multi-Output Device**
5. Check both **BlackHole 2ch** and your speakers/headphones
6. **System Settings → Sound → Output** → select the Multi-Output Device
7. **System Settings → Sound → Input** → select the Aggregate Device

Veil now records mic + system audio together. Revert output device when done.

---

## Screenshot analysis

**⌘⇧** or **⌗** → captures screen → attaches to next message.

The model sees your screen. The screen recorder doesn't see Veil.

Works with any vision model: `llava`, `gpt-4o`, `gemma3`, `claude-opus-4-7`…

---

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Show / hide window | **⌘⌥M** |
| Send message | **Enter** |
| New line | **Shift+Enter** |
| Voice input | **⌘⌥** |
| Screenshot | **⌘⇧** |
| Stop generation | **⏹** |
| Close | **Cmd+W** |

All shortcuts customizable in **⬡ → Settings…**

---

## Privacy

- **No telemetry.** No analytics. No crash reporting to any server.
- **No cloud.** Network calls go only to your configured backend.
- **Local backends** (Ollama, llama.cpp, LM Studio) run entirely on your machine — nothing leaves it.
- **Voice** transcription runs on-device via Whisper.
- **Screenshots** are sent only to your configured backend.

---

## Contributing

PRs welcome. Open an issue first for large changes.

```bash
git clone https://github.com/rbc33/Veil.git
cd Veil
open Package.swift   # Xcode opens automatically
```

---

<div align="center">

Made with ⬡ — because some things should stay invisible.

</div>