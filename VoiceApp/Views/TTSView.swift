import SwiftUI

/// Demo-focused TTS view: big sphere, one-tap Go pipeline
struct TTSView: View {
    @State private var manager = VoiceCloningManager.shared
    @State private var personality = PersonalityManager.shared
    @State private var topicText = ""
    @State private var isRunningPipeline = false
    @FocusState private var topicFocused: Bool

    private var captionText: String {
        if let error = manager.error ?? personality.error {
            return error
        }
        if manager.isDownloading {
            return "Downloading TTS model… \(Int(manager.downloadProgress * 100))%"
        }
        if personality.isDownloading {
            return "Downloading LLM… \(Int(personality.downloadProgress * 100))%"
        }
        if personality.isGenerating || !personality.generatedText.isEmpty {
            return personality.generatedText
        }
        return ""
    }

    private var captionIsError: Bool {
        (manager.error ?? personality.error) != nil
    }

    private var goDisabled: Bool {
        topicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isRunningPipeline
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Sphere + Caption
                ZStack(alignment: .bottom) {
                    SphereView(
                        isActive: manager.isSpeaking,
                        audioLevel: manager.audioLevel
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !captionText.isEmpty {
                        Text(captionText)
                            .font(.subheadline)
                            .foregroundStyle(captionIsError ? .red : .white)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial.opacity(0.6))
                    }
                }
                .background(Color.black)
                .onTapGesture {
                    topicFocused = false
                }

                // MARK: - Controls
                VStack(spacing: 12) {
                    personalityPicker

                    if let voiceName = manager.currentVoiceProfileName {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                            Text(voiceName)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    topicInput
                    goStopButton
                }
                .padding()
                .layoutPriority(1)
            }
            .navigationTitle("Speak")
            .toolbar {
                if topicFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { topicFocused = false }
                    }
                }
            }
        }
    }

    // MARK: - Personality Picker

    private var personalityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Personality.allCases) { p in
                    Button {
                        personality.setPersonality(p)
                    } label: {
                        HStack(spacing: 4) {
                            Text(p.icon)
                            Text(p.rawValue)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            personality.selectedPersonality == p
                                ? Color.accentColor
                                : Color(.systemGray5)
                        )
                        .foregroundStyle(
                            personality.selectedPersonality == p
                                ? .white
                                : .primary
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Topic Input

    private var topicInput: some View {
        TextField("What should they talk about?", text: $topicText)
            .textFieldStyle(.plain)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .focused($topicFocused)
            .submitLabel(.go)
            .onSubmit { go() }
    }

    // MARK: - Go / Stop Button

    @ViewBuilder
    private var goStopButton: some View {
        if manager.isSpeaking {
            Button {
                stopPipeline()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
        } else {
            Button {
                go()
            } label: {
                Label(
                    isRunningPipeline ? "Generating…" : "Go",
                    systemImage: isRunningPipeline ? "ellipsis" : "sparkles"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(goDisabled)
        }
    }

    // MARK: - Actions

    private func go() {
        let topic = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty, !isRunningPipeline else { return }
        topicFocused = false

        isRunningPipeline = true

        Task {
            // 1. Generate text with LLM
            manager.unloadModel()
            await personality.generate(prompt: topic)

            let text = personality.generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                isRunningPipeline = false
                return
            }

            // 2. Speak with TTS (uses active voice profile automatically)
            personality.unloadModel()
            await manager.speak(text, voiceProfileName: manager.currentVoiceProfileName)

            isRunningPipeline = false
        }
    }

    private func stopPipeline() {
        manager.stop()
        isRunningPipeline = false
    }
}

#Preview {
    TTSView()
}
