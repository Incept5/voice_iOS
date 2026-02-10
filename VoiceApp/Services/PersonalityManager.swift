import Foundation
import MLXAudio
import MLXLLM
import MLXLMCommon

@MainActor
@Observable
final class PersonalityManager {
    static let shared = PersonalityManager()

    // MARK: - State

    var selectedPersonality: Personality = .snoopDogg
    var generatedText = ""
    var isGenerating = false
    var isModelLoaded = false
    var isDownloading = false
    var downloadProgress: Double = 0
    var error: String?

    // MARK: - Private

    private var container: ModelContainer?
    private var session: ChatSession?

    private let modelID = "mlx-community/Qwen3-0.6B-4bit"

    private let generateParameters = GenerateParameters(
        maxTokens: 300,
        temperature: 0.7,
        topP: 0.9,
        repetitionPenalty: 1.1
    )

    // MARK: - Model Loading

    func loadModelIfNeeded() async {
        guard container == nil, !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        error = nil

        do {
            let configuration = ModelConfiguration(id: modelID)
            let loaded = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }

            container = loaded
            isModelLoaded = true
            isDownloading = false
            rebuildSession()
            print("[PersonalityManager] Model loaded: \(modelID)")
        } catch {
            isDownloading = false
            self.error = "Failed to load LLM: \(error.localizedDescription)"
            print("[PersonalityManager] Load error: \(error)")
        }
    }

    func unloadModel() {
        session = nil
        container = nil
        isModelLoaded = false
        MLXMemory.clearCache()
        print("[PersonalityManager] Model unloaded")
    }

    // MARK: - Session

    func setPersonality(_ personality: Personality) {
        selectedPersonality = personality
        rebuildSession()
    }

    private func rebuildSession() {
        guard let container else { return }
        session = ChatSession(
            container,
            instructions: selectedPersonality.systemPrompt,
            generateParameters: generateParameters
        )
    }

    // MARK: - Generation

    func generate(prompt: String) async {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if container == nil {
            await loadModelIfNeeded()
        }
        guard let session else {
            error = "Model not ready"
            return
        }

        isGenerating = true
        generatedText = ""
        error = nil

        do {
            let stream = session.streamResponse(to: prompt)
            var fullResponse = ""

            for try await token in stream {
                fullResponse += token
                generatedText = stripThinkBlock(from: fullResponse)
            }

            generatedText = stripThinkBlock(from: fullResponse)
            print("[PersonalityManager] Generated \(generatedText.count) chars")
        } catch {
            self.error = "Generation failed: \(error.localizedDescription)"
            print("[PersonalityManager] Generate error: \(error)")
        }

        isGenerating = false

        // Rebuild session so each generation is independent (avoids Sendable issues with clear())
        rebuildSession()
        MLXMemory.clearCache()
    }

    // MARK: - Helpers

    private func stripThinkBlock(from text: String) -> String {
        // Take everything after </think> if present
        if let range = text.range(of: "</think>") {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Still thinking (opened but not closed) — show nothing yet
        if text.contains("<think>") {
            return ""
        }

        // No think block at all
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
