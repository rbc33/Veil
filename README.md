<div align="center">

<img src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple&logoColor=white" />
<img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift&logoColor=white" />
<img src="https://img.shields.io/badge/No_Electron-✓-green?style=flat-square" />
<img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" />
<img src="https://img.shields.io/github/stars/rbc33/Veil?style=flat-square&color=yellow" />

<br><br>

# ⬡ Veil

### The only native Swift macOS Cluely alternative.

*No Electron. No subscription. No cloud. Just Swift.*  
*AI invisible to screen sharing — Zoom, Teams, Meet, OBS.*

<br>

[**Download DMG**](https://github.com/rbc33/Veil/releases) · [**Build from source**](#install) · [**Report bug**](https://github.com/rbc33/Veil/issues)

</div>

---

## Why Veil over Pluely, Natively, or Vysper?

Every other Cluely alternative is built on **Electron or Tauri** — that means a bundled Chromium browser, 200–500MB of RAM just to open, and slow startup times.

Veil is written in **native Swift using AppKit**. It starts instantly, uses minimal memory, and feels like a real macOS app — because it is one.

| | Veil | Pluely | Natively | Vysper |
|---|---|---|---|---|
| **Tech** | ✅ Native Swift | Tauri/Rust | Electron | Electron |
| **macOS only** | ✅ Purpose-built | ❌ Cross-platform | ❌ Cross-platform | ❌ Cross-platform |
| **Ollama / local LLMs** | ✅ | ⚠️ Partial | ✅ | ❌ |
| **Free** | ✅ Always | ✅ | ✅ Free tier | ✅ |
| **No subscription** | ✅ | ✅ | ⚠️ Premium tier | ✅ |
| **Open source** | ✅ MIT | ✅ | ✅ | ✅ |
| **No telemetry** | ✅ Zero | ⚠️ | ⚠️ Limited | ❓ |
| **Voice input** | ✅ On-device | ❌ | ✅ | ❌ |
| **App size** | ✅ ~5MB | ~10MB | ~150MB | ~200MB |

---

## What is Veil?

A macOS menu bar AI client that is **completely invisible to screen capture**.

Zoom, Google Meet, Microsoft Teams, OBS, QuickTime, Cmd+Shift+5 — none of them see it. It only exists on your physical display.

```swift
// The entire secret. One native AppKit API.
window.sharingType = .none
```

No hacks. No injection. A public, documented Apple API that removes the window from the display capture pipeline before any recording tool can touch it.

---

## Use cases

**Technical interviews**  
LeetCode, HackerRank, take-home assessments. Ask for hints, complexity analysis, edge cases — all while sharing your screen. The interviewer sees your code. They don't see Veil.

**Live coding demos**  
Presenting to a client or team? Use AI to look up syntax, generate boilerplate, or sanity-check logic in real time. Nobody notices.

**Work calls & meetings**  
Prepare answers on the fly. Summarize what was just said. Draft a response before you speak.

**System design interviews**  
Ask for architecture patterns, trade-offs, scalability approaches instantly.

**Local & private**  
Pair with Ollama or LM Studio for fully on-device inference. Nothing leaves your machine.

---

## Tested invisible in ✅

| Tool | Status |
|---|---|
| Zoom | ✅ Invisible |
| Google Meet (Chrome) | ✅ Invisible |
| Microsoft Teams | ✅ Invisible |
| OBS Studio | ✅ Invisible |
| QuickTime screen recording | ✅ Invisible |
| macOS Cmd+Shift+5 | ✅ Invisible |

---

## Features

| | |
|---|---|
| 🫥 **Invisible by default** | Hidden from every screen capture tool on macOS |
| 🍎 **Menu bar only** | No Dock icon. No trace. Appears as **⬡** |
| 🤖 **Multi-backend** | Ollama, OpenAI, Claude, OpenRouter, NVIDIA NIM, LM Studio, llama.cpp |
| 🎙 **Voice input** | On-device transcription via whisper-cpp |
| 📸 **Screenshot analysis** | Capture your screen → attach to message. Model sees it, recorder doesn't. |
| 🔒 **Zero telemetry** | No analytics, no cloud, no tracking |
| ⚡ **Instant startup** | Native Swift — no Chromium, no Electron overhead |

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
NSWindow.sharingType = .none     // excluded from all capture
NSWindow.sharingType = .readOnly // default — visible to recorders
```

Setting `.none` tells the macOS compositor to exclude the window from all capture operations before any recording application, screenshot tool, or API (`CGWindowListCreateImage`, `SCStreamConfiguration`, etc.) can observe it.

The window renders normally on your physical display. It simply does not exist to capture pipelines.

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

---

## Screenshot analysis

**⌘⇧** → captures screen → attaches to next message.

The model sees your screen. The screen recorder doesn't see Veil.

Works with any vision model: `llava`, `gpt-4o`, `gemma3`, `claude-opus-4-7`…

---

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Send message | **Enter** |
| New line | **Shift+Enter** |
| Voice input | **⌘⌥** |
| Screenshot | **⌘⇧** |
| Close | **Cmd+W** |

All shortcuts customizable in Settings.

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