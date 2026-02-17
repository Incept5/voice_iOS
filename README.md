# Voice iOS

On-device AI voice app for iPhone. Generates spoken responses using a local LLM and voice-cloning TTS — no cloud APIs, no data leaves your device.

## What It Does

Pick a personality (Snoop Dogg, Morgan Freeman, Gordon Ramsay, etc.), give it a topic, and it generates a monologue and speaks it aloud — all running locally on your iPhone's GPU via [MLX](https://github.com/ml-explore/mlx-swift).

**Three modes:**

- **Fun** — Celebrity-style monologues on any topic, spoken in a cloned voice
- **Schedule** — Reads your calendar and reminders, then briefs you on your day
- **Screen Time** — Shows your device usage and roasts your app habits

**How the pipeline works:**

1. **LLM** ([Qwen3-1.7B-MLX-4bit](https://huggingface.co/Qwen/Qwen3-1.7B-MLX-4bit)) generates text on-device
2. LLM unloads from memory (~1GB freed)
3. **TTS** ([Chatterbox-Turbo-4bit](https://huggingface.co/mlx-community/Chatterbox-Turbo-4bit)) synthesizes speech with voice cloning
4. Audio streams sentence-by-sentence — you hear the first sentence while the rest generate

## Requirements

- **Physical iPhone** with Apple Silicon (A14+). Models run on the GPU via MLX — the Simulator is not supported.
- **iOS 18.4+**
- **~2.5GB free storage** — models download from Hugging Face on first launch (~1.3GB LLM + ~1.3GB TTS)
- **Xcode 16+**
- **[xcodegen](https://github.com/yonaskolb/XcodeGen)** — `brew install xcodegen`
- **Apple Developer account** (free or paid) — required for code signing and on-device deployment

## Getting Started

### 1. Clone and generate the Xcode project

```bash
git clone https://github.com/AdeRiz/voice_iOS.git
cd voice_iOS
xcodegen generate
open VoiceApp.xcodeproj
```

### 2. Configure code signing

The project ships with placeholder signing identifiers that you **must** change to your own.

**In `project.yml`**, replace the following values under both the `VoiceApp` and `ScreenTimeReport` targets:

| Setting | Replace with |
|---------|-------------|
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID |
| `PRODUCT_BUNDLE_IDENTIFIER` | A bundle ID unique to you (e.g. `com.yourname.VoiceApp`) |

The `ScreenTimeReport` extension's bundle ID must be a child of the main app's (e.g. `com.yourname.VoiceApp.ScreenTimeReport`).

**Update the App Group ID** in these files to match your new bundle ID:

| File | What to change |
|------|---------------|
| `VoiceApp.entitlements` | `group.com.incept5.VoiceApp` → `group.com.yourname.VoiceApp` |
| `ScreenTimeReport/ScreenTimeReport.entitlements` | Same |
| `VoiceApp/Services/ScreenTimeConstants.swift` | `appGroupID` string |

Then regenerate:

```bash
xcodegen generate
```

### 3. Set up App Group (optional — required for real Screen Time data)

If you want the Screen Time mode to use **real usage data** instead of synthetic placeholder data, you need to register an App Group in the Apple Developer portal:

1. Go to [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers)
2. **Register the App Group** (Sidebar > App Groups > +) using the ID from your entitlements (e.g. `group.com.yourname.VoiceApp`)
3. **Register both App IDs** if not already done by Xcode:
   - `com.yourname.VoiceApp` (main app)
   - `com.yourname.VoiceApp.ScreenTimeReport` (extension)
4. **Enable capabilities** on both App IDs: **App Groups** (select your group) and **Family Controls**

If you skip this step, the Screen Time mode works fine — it just uses synthetic placeholder data for the AI roast (see below).

### 4. Build and run

- Select the **VoiceApp** scheme
- Set the destination to your **physical iPhone**
- Build and run (`Cmd+R`)
- On first launch, models download automatically from Hugging Face

### 5. Grant permissions

The app will prompt for:

- **Microphone** — recording a voice sample for cloning
- **Calendar & Reminders** — for Schedule mode
- **Screen Time / Family Controls** — for Screen Time mode

## Synthetic Data

The app uses **synthetic placeholder data** in two places. This is intentional — it lets you run and demo the app without requiring any real personal data.

### Screen Time

Apple's Screen Time APIs require a `DeviceActivityReport` extension (a separate process) to access usage data. The extension can render usage on screen, but the main app process never sees the raw data directly. To bridge this gap, the extension writes a summary to **App Group shared UserDefaults**, which the main app reads and feeds to the LLM.

**If the App Group is not configured** (or on the Simulator), the app falls back to hardcoded placeholder data:

```
Instagram for 2 hours 15 minutes
TikTok for 1 hour 45 minutes
Safari for 1 hour 10 minutes
Messages for 45 minutes
YouTube for 35 minutes
Total screen time 7 hours 20 minutes
85 phone pickups
```

This placeholder data is defined in `VoiceApp/Services/ScreenTimeProvider.swift`. The AI will roast this synthetic usage instead of your real usage. To get real data flowing, complete the App Group setup in step 3 above.

### Voice Cloning

No voice samples are bundled with the app. Users record their own voice sample on-device during onboarding. Recordings are stored locally in the app's Documents directory and never uploaded anywhere.

## Architecture

| Component | Role |
|-----------|------|
| `PersonalityManager` | Loads Qwen3-1.7B, generates text, manages LLM lifecycle |
| `VoiceCloningManager` | Loads Chatterbox-Turbo TTS, streams sentence-by-sentence audio |
| `PromptBuilder` | Constructs system/user prompts per mode, normalizes text for TTS |
| `CalendarProvider` | Reads EventKit events and reminders |
| `ScreenTimeProvider` | Reads screen time data from App Group (falls back to synthetic data) |
| `ScreenTimeReport/` | DeviceActivityReport extension — reads real usage, writes to App Group |

Models share MLX GPU memory and are never loaded simultaneously. The pipeline unloads the LLM before loading TTS, with a brief settle period for memory reclamation.

## Known Limitations

**LLM quality** — Qwen3-1.7B is a small language model. It may produce short or repetitive output for some prompts.

**TTS speed** — Speech generation takes 5-15 seconds per sentence on iPhone. Audio streams sentence-by-sentence so you hear output before the full response is ready.

**Memory** — The LLM (~1.3GB) and TTS (~1.3GB) models cannot be loaded simultaneously. The pipeline handles swapping automatically.

**Screen Time on Simulator** — Not supported by Apple. Placeholder data is always used.

## License

MIT
