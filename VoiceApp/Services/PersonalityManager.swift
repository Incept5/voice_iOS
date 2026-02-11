import Foundation
import MLXAudio
import MLXLLM
import MLXLMCommon
import UIKit

@MainActor
@Observable
final class PersonalityManager {
    static let shared = PersonalityManager()

    // MARK: - State

    var selectedPersonality: Personality = .snoopDogg
    var generatedText = ""
    var isGenerating = false
    var isModelLoaded = false
    var isLoading = false
    var loadingProgress: Double = 0
    var error: String?

    // MARK: - Private

    private var container: ModelContainer?
    private var session: ChatSession?

    private let modelID = "Qwen/Qwen3-1.7B-MLX-4bit"

    private let generateParameters = GenerateParameters(
        maxTokens: 300,
        temperature: 0.7,
        topP: 0.9,
        repetitionPenalty: 1.1
    )

    init() {
        registerForMemoryWarning()
    }

    private func registerForMemoryWarning() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isGenerating else { return }
                print("[PersonalityManager] Memory warning — unloading idle LLM")
                self.unloadModel()
            }
        }
    }

    // MARK: - Model Loading

    func loadModelIfNeeded() async {
        guard container == nil, !isLoading else { return }

        isLoading = true
        loadingProgress = 0
        error = nil

        do {
            let configuration = ModelConfiguration(id: modelID)
            let loaded = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.loadingProgress = progress.fractionCompleted
                }
            }

            container = loaded
            isModelLoaded = true
            isLoading = false
            rebuildSession()
            print("[PersonalityManager] Model loaded: \(modelID)")
        } catch {
            isLoading = false
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

    func generate(userPrompt: String, systemPrompt: String, maxTokens: Int = 300) async {
        guard !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[PersonalityManager] Skipping: empty userPrompt")
            return
        }

        print("[PersonalityManager] generate(userPrompt: \"\(userPrompt.prefix(80))\", maxTokens: \(maxTokens))")

        if container == nil {
            await loadModelIfNeeded()
        }
        guard let container else {
            error = "Model not ready"
            print("[PersonalityManager] Aborting: container nil after loadModelIfNeeded")
            return
        }

        // Build mode-specific parameters
        var params = generateParameters
        params.maxTokens = maxTokens

        // Replace session with the custom system prompt (one session at a time)
        session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params
        )

        guard let session else {
            print("[PersonalityManager] Aborting: session nil after ChatSession init")
            return
        }

        isGenerating = true
        generatedText = ""
        error = nil

        do {
            let stream = session.streamResponse(to: userPrompt)
            var fullResponse = ""

            for try await token in stream {
                fullResponse += token
                generatedText = stripThinkBlock(from: fullResponse)
            }

            print("[PersonalityManager] Raw response (\(fullResponse.count) chars): \"\(fullResponse.prefix(200))\"")
            generatedText = stripThinkBlock(from: fullResponse)
            print("[PersonalityManager] After strip (\(generatedText.count) chars): \"\(generatedText.prefix(200))\"")
        } catch {
            self.error = "Generation failed: \(error.localizedDescription)"
            print("[PersonalityManager] Generate error: \(error)")
        }

        isGenerating = false

        // Restore default personality session
        rebuildSession()
        MLXMemory.clearCache()
    }

    // MARK: - Helpers

    /// Strip `<think>…</think>` blocks from model output.
    /// Only returns actual response content (after `</think>`), never the thinking itself.
    private func stripThinkBlock(from text: String) -> String {
        // Take everything after </think> if present
        if let range = text.range(of: "</think>") {
            let after = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty { return after }
            // Closed think block but nothing after — use think content as fallback
            if let openRange = text.range(of: "<think>") {
                let thought = String(text[openRange.upperBound..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !thought.isEmpty { return thought }
            }
        }

        // Think block opened but never closed — ran out of tokens mid-thought
        // Use the think content as fallback
        if let openRange = text.range(of: "<think>") {
            let thought = String(text[openRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !thought.isEmpty { return thought }
        }

        // No think block at all — return as-is
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
