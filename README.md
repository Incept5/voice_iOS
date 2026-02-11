# Voice iOS

On-device AI voice app for iPhone. Generates spoken responses using a local LLM and TTS model — no cloud APIs, everything runs on your device.

## Features

### Three Modes
- **Fun** — Pick a personality (Snoop Dogg, Trump, Morgan Freeman, Gordon Ramsay, Optimus Prime) and give it a topic. It generates a monologue and speaks it aloud in a cloned voice.
- **Schedule** — Reads your calendar events and reminders, then briefs you on your day.
- **Screen Time** — Shows your device usage and roasts your app habits.

### On-Device AI Pipeline
1. **LLM** (Qwen3-1.7B-MLX-4bit) generates text locally via MLX
2. LLM unloads from memory (~850MB freed)
3. **TTS** (Chatterbox-Turbo-4bit) synthesizes speech via MLX
4. Audio streams sentence-by-sentence — you hear the first sentence while the next is being generated

### Voice Cloning
Record a short voice sample and the TTS model clones it for all spoken output.

## Requirements

- iOS 18.4+
- Physical iPhone (models run on Apple Silicon GPU via MLX)
- ~2GB free storage (models download on first use)
- Xcode 16+ with xcodegen installed

## Build

```bash
brew install xcodegen  # if not installed
xcodegen generate
open VoiceApp.xcodeproj
```

Select the **VoiceApp** scheme and your iPhone, then build and run.

## Architecture

| Component | Role |
|-----------|------|
| `PersonalityManager` | Loads Qwen3-1.7B, generates text, manages LLM lifecycle |
| `VoiceCloningManager` | Loads Chatterbox-Turbo TTS, streams sentence-by-sentence audio |
| `PromptBuilder` | Constructs system/user prompts per mode, normalizes text for TTS |
| `CalendarProvider` | Reads EventKit events and reminders |
| `ScreenTimeProvider` | Reads screen time data from App Group shared by extension |
| `ScreenTimeReport/` | DeviceActivityReport extension — reads real usage, writes to App Group |

Models share MLX GPU memory and are never loaded simultaneously. The pipeline unloads the LLM before loading TTS, with a 300ms settle period for memory reclamation.

## Limitations

### Screen Time Data

The Screen Time feature has a significant architectural constraint imposed by Apple:

- **The main app cannot read Screen Time data directly.** Apple requires a `DeviceActivityReport` extension (a separate process) to access usage data.
- The extension renders a SwiftUI view showing real usage data on screen, but **the main app process never sees this data**.
- To pass data from the extension to the main app (for the LLM roast), we use **App Group shared UserDefaults**. This requires the App Group to be registered in the Apple Developer portal.

**To get real Screen Time data flowing to the AI:**

1. Register App Group `group.com.incept5.VoiceApp` at [developer.apple.com](https://developer.apple.com/account/resources/identifiers)
2. Enable **App Groups** and **Family Controls** capabilities on both:
   - `com.incept5.VoiceApp` (main app)
   - `com.incept5.VoiceApp.ScreenTimeReport` (extension)
3. Rebuild — Xcode will provision the shared container

**Without this setup**, the Screen Time mode falls back to placeholder data. You will see real usage rendered on screen (by the extension), but the AI will roast placeholder data instead.

Screen Time APIs do not work on the iOS Simulator — placeholder data is always used there.

### LLM Quality

Qwen3-1.7B is a small model. It sometimes:
- Ignores the `/no_think` flag and spends tokens on internal `<think>` reasoning instead of output
- Echoes input data back instead of generating creative responses
- Produces short or repetitive output

A fallback extracts usable content from think blocks when the model exhausts its token budget on reasoning.

### TTS

- First run downloads ~1.3GB model weights
- Generation takes 5-15 seconds per sentence on iPhone
- Audio quality depends on the reference voice sample — longer, cleaner samples produce better clones

### General

- Models require ~850MB (LLM) and ~1.3GB (TTS) of memory — only one loaded at a time
- Calendar and Screen Time features require explicit user permission grants
- FamilyControls authorization is needed before Screen Time data is available
