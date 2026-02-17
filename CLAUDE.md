# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

Generate the Xcode project (required after cloning or modifying `project.yml`):
```bash
xcodegen generate
```

Build the project:
```bash
xcodebuild -project VoiceApp.xcodeproj -scheme VoiceApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Build for physical device (requires code signing setup):
```bash
xcodebuild -project VoiceApp.xcodeproj -scheme VoiceApp -destination 'platform=iOS,name=Your iPhone' build
```

Run tests in the mlx-audio-ios package:
```bash
cd Packages/mlx-audio-ios
swift test --filter ChatterboxTurboTests
```

## Architecture Overview

This is an on-device AI voice app for iOS that generates spoken responses using local LLM and voice-cloning TTS — no cloud APIs. It runs entirely on the iPhone's GPU via [MLX](https://github.com/ml-explore/mlx-swift).

### Key Components

**Managers (Services layer):**
- `PersonalityManager` - Loads Qwen3-1.7B-MLX-4bit LLM, generates text, manages LLM lifecycle. Lives in `VoiceApp/Services/PersonalityManager.swift`
- `VoiceCloningManager` - Loads Chatterbox-Turbo TTS, streams sentence-by-sentence audio. Lives in `VoiceApp/Services/VoiceCloningManager.swift`
- `PromptBuilder` - Constructs system/user prompts per mode. Lives in `VoiceApp/Services/PromptBuilder.swift`
- `CalendarProvider` - Reads EventKit events and reminders. Lives in `VoiceApp/Services/CalendarProvider.swift`
- `ScreenTimeProvider` - Reads screen time data from App Group (falls back to synthetic data). Lives in `VoiceApp/Services/ScreenTimeProvider.swift`

**UI Layer:**
- `HomeView` - Main view with mode switching (Fun/Schedule/ScreenTime/VoiceClone). Lives in `VoiceApp/Views/HomeView.swift`
- Mode controls live in `VoiceApp/Views/Controls/` directory
- `VoiceSetupView` - Voice recording and profile management. Lives in `VoiceApp/Views/VoiceSetupView.swift`

**Models:**
- `Personality` enum with system prompts for different personalities (Snoop Dogg, Donald Trump, Morgan Freeman, etc.). Lives in `VoiceApp/Models/Personality.swift`

**Extension:**
- `ScreenTimeReport/` - DeviceActivityReport extension that reads real usage and writes to App Group shared UserDefaults. Lives in `ScreenTimeReport/ScreenTimeReportExtension.swift`

**Local Package:**
- `Packages/mlx-audio-ios` - Custom MLX audio package with TTS engines (ChatterboxTurbo, Chatterbox, CosyVoice, etc.)

### Pipeline Flow

1. User enters topic → `HomeView.goFun()` or `goWithPrompts()`
2. `PersonalityManager.generate()` streams text from Qwen3-1.7B
3. LLM unloads from memory (`personality.unloadModel()`) to free ~850MB
4. 300ms delay for memory reclamation
5. `VoiceCloningManager.speak()` loads Chatterbox-Turbo TTS and streams audio sentence-by-sentence
6. Audio plays while subsequent sentences generate

### Memory Management

Models share MLX GPU memory and are never loaded simultaneously. The pipeline handles swapping automatically:
- LLM: ~850MB (Qwen3-1.7B-MLX-4bit)
- TTS: ~1.3GB (Chatterbox-Turbo-4bit)
- MLX cache limit: 512MB (configured in `VoiceApp.swift`)

## Project Configuration

**project.yml** - XcodeGen configuration file defining:
- Main app target (`VoiceApp`) with iOS 18.4+ deployment target
- ScreenTimeReport extension target (app extension for Screen Time data)
- Dependencies on local package `mlx-audio-ios` and remote `mlx-swift-lm`
- Code signing settings (must be changed from placeholder values)

**Code Signing Setup Required:**
The project ships with placeholder bundle IDs (`com.incept5.VoiceApp`) and team ID (`NGX9KBXLZ6`). You must change these in `project.yml`:
- `PRODUCT_BUNDLE_IDENTIFIER` for both VoiceApp and ScreenTimeReport targets
- `DEVELOPMENT_TEAM` to your Apple Developer Team ID
- App Group ID in `VoiceApp.entitlements`, `ScreenTimeReport/ScreenTimeReport.entitlements`, and `VoiceApp/Services/ScreenTimeConstants.swift`

After modifying `project.yml`, regenerate the project with `xcodegen generate`.

## Important Implementation Notes

**Screen Time Data Flow:**
Apple's Screen Time APIs require a DeviceActivityReport extension. The extension renders usage on screen but the main app never sees raw data directly. The extension writes a summary to App Group shared UserDefaults (`ScreenTimeConstants.appGroupID`), which the main app reads. If App Group is not configured, the app falls back to synthetic placeholder data defined in `ScreenTimeProvider.swift`.

**Voice Cloning:**
Voice samples are recorded on-device during onboarding and stored locally in the app's Documents directory (`voice_profiles/`). Recordings are never uploaded. Reference audio is pre-computed once per voice sample and cached for reuse.

**Simulator Limitations:**
MLX requires Apple Silicon GPU. The Simulator is not supported — you must use a physical iPhone (A14+). When building for Simulator, the code compiles but MLX operations will fail at runtime.

**Download Progress:**
Models download automatically from Hugging Face on first launch. ChatterboxTurbo downloads two files in parallel (model + tokenizer) with separate progress handlers to avoid UI flickering.

**Audio Session:**
Configured in `VoiceApp.swift` init: playAndRecord category with defaultToSpeaker and allowBluetoothHFP options.
