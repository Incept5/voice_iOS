import SwiftUI

struct HomeView: View {
    @State private var manager = VoiceCloningManager.shared
    @State private var personality = PersonalityManager.shared
    @State private var calendarProvider = CalendarProvider()
    @State private var screenTimeProvider = ScreenTimeProvider()

    @State private var selectedMode: AppMode = .fun
    @State private var showSettings = false
    @State private var topicText = ""
    @State private var pipelinePhase: PipelinePhase = .idle

    private enum PipelinePhase: Equatable {
        case idle, generating, loadingVoice
    }

    // MARK: - Caption

    private var captionText: String {
        if let error = manager.error ?? personality.error {
            return error
        }
        // Only show model-loading progress outside the pipeline.
        // During the pipeline the button already communicates state.
        if pipelinePhase == .idle {
            if manager.isLoading {
                return "Loading TTS model\u{2026} \(Int(manager.loadingProgress * 100))%"
            }
            if personality.isLoading {
                return "Loading LLM\u{2026} \(Int(personality.loadingProgress * 100))%"
            }
        }
        if personality.isGenerating || !personality.generatedText.isEmpty {
            return personality.generatedText
        }
        return ""
    }

    private var captionIsError: Bool {
        (manager.error ?? personality.error) != nil
    }

    private var pipelineActive: Bool {
        pipelinePhase != .idle
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Sphere + Caption
            ZStack(alignment: .bottom) {
                SphereView(
                    isActive: manager.isSpeaking,
                    audioLevel: manager.audioLevel
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                CaptionOverlay(text: captionText, isError: captionIsError)
            }
            .background(Color.black)
            .animation(.easeInOut(duration: 0.25), value: captionText.isEmpty)

            // Mode-specific controls
            controlsForCurrentMode
                .padding()
                .layoutPriority(1)

            // Dock
            DockBar(selectedMode: $selectedMode) {
                showSettings = true
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Controls Switch

    @ViewBuilder
    private var controlsForCurrentMode: some View {
        switch selectedMode {
        case .fun:
            FunControlsView(
                personality: personality,
                topicText: $topicText,
                pipelineActive: pipelineActive,
                isSpeaking: manager.isSpeaking,
                voiceProfileName: manager.currentVoiceProfileName,
                onGo: { goFun() },
                onStop: { stopPipeline() }
            )

        case .schedule:
            ScheduleControlsView(
                calendar: calendarProvider,
                pipelineActive: pipelineActive,
                isSpeaking: manager.isSpeaking,
                onBriefMe: { userPrompt, systemPrompt in
                    goWithPrompts(userPrompt: userPrompt, systemPrompt: systemPrompt)
                },
                onStop: { stopPipeline() }
            )

        case .screenTime:
            ScreenTimeControlsView(
                screenTime: screenTimeProvider,
                pipelineActive: pipelineActive,
                isSpeaking: manager.isSpeaking,
                onRoast: { userPrompt, systemPrompt in
                    goWithPrompts(userPrompt: userPrompt, systemPrompt: systemPrompt)
                },
                onStop: { stopPipeline() }
            )
        }
    }

    // MARK: - Pipeline Actions

    private func goFun() {
        let topic = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty, pipelinePhase == .idle else { return }

        manager.clearError()
        personality.error = nil
        pipelinePhase = .generating

        Task {
            let system = PromptBuilder.funSystemPrompt(personality: personality.selectedPersonality)
            let user = PromptBuilder.funUserPrompt(topic: topic)
            await personality.generate(userPrompt: user, systemPrompt: system, maxTokens: 500)
            await speakGeneratedText()
        }
    }

    private func goWithPrompts(userPrompt: String, systemPrompt: String) {
        guard pipelinePhase == .idle else { return }

        manager.clearError()
        personality.error = nil
        pipelinePhase = .generating

        Task {
            await personality.generate(userPrompt: userPrompt, systemPrompt: systemPrompt, maxTokens: 500)
            await speakGeneratedText()
        }
    }

    private func speakGeneratedText() async {
        let text = PromptBuilder.normalizeForTTS(
            personality.generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        print("[Pipeline] generatedText: \(text.count) chars, error: \(personality.error ?? "none")")
        guard !text.isEmpty else {
            // Only set generic error if personality didn't already set a specific one
            if personality.error == nil {
                personality.error = "No response generated. Try again."
            }
            pipelinePhase = .idle
            return
        }

        // Free LLM memory (~300MB) before loading TTS
        personality.unloadModel()

        // Give MLX memory pool time to reclaim freed allocations
        // before the TTS model allocates its own weights.
        try? await Task.sleep(nanoseconds: 300_000_000)

        pipelinePhase = .loadingVoice
        print("[Pipeline] Starting TTS: \(text.count) chars, voice: \(manager.currentVoiceProfileName ?? "default")")
        await manager.speak(text, voiceProfileName: manager.currentVoiceProfileName)
        print("[Pipeline] TTS complete, error: \(manager.error ?? "none")")
        pipelinePhase = .idle
    }

    private func stopPipeline() {
        manager.stop()
        pipelinePhase = .idle
    }
}

#Preview {
    HomeView()
}
