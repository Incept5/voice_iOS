// Copyright © Anthony DePasquale
// SpeechGenerationModel conformance for ChatterboxTurboEngine
// Enables compatibility with upstream mlx-audio-swift SDK

import Foundation
@preconcurrency import MLX
import MLXLMCommon

// MARK: - SpeechGenerationModel Protocol

/// Protocol matching upstream mlx-audio-swift SDK for TTS model interoperability.
///
/// This allows ChatterboxTurbo to be used with the same interface as Soprano, Marvis,
/// and other upstream TTS models.
///
/// Note: This protocol is not MainActor-isolated to match the upstream signature.
/// Implementations handle actor isolation internally.
public protocol SpeechGenerationModel: AnyObject {
    var sampleRate: Int { get }

    /// Generate audio from text
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voice: Voice identifier (unused by Chatterbox)
    ///   - refAudio: Reference audio for voice cloning
    ///   - refText: Reference text (unused by Chatterbox)
    ///   - language: Language code (unused by Chatterbox)
    ///   - generationParameters: Generation parameters (temperature, topP, etc.)
    /// - Returns: Generated audio as MLXArray
    func generate(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters
    ) async throws -> MLXArray

    /// Generate audio as a stream of events
    func generateStream(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters
    ) -> AsyncThrowingStream<SpeechGenerationEvent, Error>
}

// MARK: - Generation Events

/// Events emitted during speech generation (matching upstream AudioGeneration)
public enum SpeechGenerationEvent: @unchecked Sendable {
    /// A generated token ID
    case token(Int)
    /// Generation statistics
    case info(SpeechGenerationInfo)
    /// Audio chunk (for streaming) - MLXArray is not Sendable but handled safely
    case audio(MLXArray)
}

/// Information about the generation process
public struct SpeechGenerationInfo: Sendable {
    public let promptTokenCount: Int
    public let generationTokenCount: Int
    public let prefillTime: TimeInterval
    public let generateTime: TimeInterval
    public let tokensPerSecond: Double
    public let peakMemoryUsage: Double

    public init(
        promptTokenCount: Int = 0,
        generationTokenCount: Int = 0,
        prefillTime: TimeInterval = 0,
        generateTime: TimeInterval = 0,
        tokensPerSecond: Double = 0,
        peakMemoryUsage: Double = 0
    ) {
        self.promptTokenCount = promptTokenCount
        self.generationTokenCount = generationTokenCount
        self.prefillTime = prefillTime
        self.generateTime = generateTime
        self.tokensPerSecond = tokensPerSecond
        self.peakMemoryUsage = peakMemoryUsage
    }

    public var summary: String {
        """
        Prompt: \(promptTokenCount) tokens, \(String(format: "%.3f", prefillTime))s
        Generation: \(generationTokenCount) tokens, \(String(format: "%.2f", tokensPerSecond)) tokens/s, \(String(format: "%.3f", generateTime))s
        Peak Memory: \(String(format: "%.2f", peakMemoryUsage)) GB
        """
    }
}

// MARK: - Reference Audio Cache

/// LRU cache for pre-computed voice conditioning
/// Avoids re-computing expensive conditioning for repeated reference audio
private actor ReferenceAudioCache {
    struct CacheEntry {
        let conditionals: ChatterboxTurboConditionals
        let sampleRate: Int
        let sampleCount: Int
        var lastAccess: Date
    }

    private var cache: [Int: CacheEntry] = [:]  // Key: hash of audio samples
    private let maxEntries: Int

    init(maxEntries: Int = 8) {
        self.maxEntries = maxEntries
    }

    /// Get cached conditionals for audio, or nil if not cached
    func get(audioHash: Int) -> CacheEntry? {
        guard var entry = cache[audioHash] else { return nil }
        entry.lastAccess = Date()
        cache[audioHash] = entry
        return entry
    }

    /// Store conditionals in cache
    func set(audioHash: Int, entry: CacheEntry) {
        // Evict oldest if at capacity
        if cache.count >= maxEntries {
            let oldest = cache.min { $0.value.lastAccess < $1.value.lastAccess }
            if let oldestKey = oldest?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }
        cache[audioHash] = entry
    }

    /// Clear all cached entries
    func clear() {
        cache.removeAll()
    }
}

// MARK: - ChatterboxTurboEngine Conformance

extension ChatterboxTurboEngine: @preconcurrency SpeechGenerationModel {
    /// Reference audio cache (shared across all instances via static)
    private static let conditioningCache = ReferenceAudioCache(maxEntries: 8)

    /// Sample rate for generated audio (24kHz for Chatterbox)
    nonisolated public var sampleRate: Int {
        provider.sampleRate
    }

    nonisolated public func generate(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters
    ) async throws -> MLXArray {
        // Convert MLXArray to [Float] (Sendable) before crossing isolation boundary
        let refAudioSamples: [Float]? = refAudio?.asArray(Float.self)

        // Run on MainActor since ChatterboxTurboEngine is MainActor-isolated
        return try await generateOnMainActor(
            text: text,
            refAudioSamples: refAudioSamples,
            generationParameters: generationParameters
        )
    }

    @MainActor
    private func generateOnMainActor(
        text: String,
        refAudioSamples: [Float]?,
        generationParameters: GenerateParameters
    ) async throws -> MLXArray {
        // Reconstruct MLXArray on MainActor if samples were provided
        let refAudio: MLXArray? = refAudioSamples.map { MLXArray($0) }

        // Get or compute reference audio conditioning
        let referenceAudio = try await resolveReferenceAudio(refAudio: refAudio)

        // Apply generation parameters
        self.temperature = generationParameters.temperature
        self.topP = generationParameters.topP

        // Generate audio
        let result = try await generate(text, referenceAudio: referenceAudio)

        // Convert AudioResult to MLXArray
        guard let samples = result.samples else {
            throw TTSError.invalidArgument("No audio samples generated")
        }
        return MLXArray(samples)
    }

    nonisolated public func generateStream(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters
    ) -> AsyncThrowingStream<SpeechGenerationEvent, Error> {
        // Convert MLXArray to [Float] (Sendable) before crossing isolation boundary
        let refAudioSamples: [Float]? = refAudio?.asArray(Float.self)

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    // Reconstruct MLXArray on MainActor if samples were provided
                    let refAudio: MLXArray? = refAudioSamples.map { MLXArray($0) }

                    // Get or compute reference audio conditioning
                    let referenceAudio = try await self.resolveReferenceAudio(refAudio: refAudio)

                    // Apply generation parameters
                    self.temperature = generationParameters.temperature
                    self.topP = generationParameters.topP

                    let startTime = Date()
                    var totalSamples = 0

                    // Stream audio chunks
                    let stream = self.generateStreaming(text, referenceAudio: referenceAudio)

                    for try await chunk in stream {
                        guard !Task.isCancelled else { break }
                        totalSamples += chunk.samples.count
                        continuation.yield(.audio(MLXArray(chunk.samples)))
                    }

                    // Emit generation info
                    let elapsed = Date().timeIntervalSince(startTime)
                    let info = SpeechGenerationInfo(
                        generationTokenCount: totalSamples,
                        generateTime: elapsed,
                        tokensPerSecond: Double(totalSamples) / max(elapsed, 0.001),
                        peakMemoryUsage: Double(GPU.activeMemory) / 1e9
                    )
                    continuation.yield(.info(info))

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Resolve reference audio to ChatterboxTurboReferenceAudio, using cache when possible
    @MainActor
    private func resolveReferenceAudio(refAudio: MLXArray?) async throws -> ChatterboxTurboReferenceAudio? {
        guard let refAudio = refAudio else {
            // No reference audio provided - use default
            return nil
        }

        // Compute hash of audio samples for cache lookup
        let audioHash = computeAudioHash(refAudio)

        // Check cache first
        if let cached = await Self.conditioningCache.get(audioHash: audioHash) {
            print("[SpeechGenerationModel] Using cached conditioning (hash: \(audioHash))")
            return ChatterboxTurboReferenceAudio(
                conditionals: cached.conditionals,
                sampleRate: cached.sampleRate,
                sampleCount: cached.sampleCount,
                description: "Cached reference"
            )
        }

        // Not cached - prepare reference audio
        print("[SpeechGenerationModel] Computing conditioning for new reference audio (hash: \(audioHash))")

        // Convert MLXArray to [Float] for prepareReferenceAudio
        let samples = refAudio.asArray(Float.self)
        let sampleRate = 24000  // Assume 24kHz for Chatterbox

        let prepared = try await prepareReferenceAudio(fromSamples: samples, sampleRate: sampleRate)

        // Cache the result
        let cacheEntry = ReferenceAudioCache.CacheEntry(
            conditionals: prepared.conditionals,
            sampleRate: prepared.sampleRate,
            sampleCount: samples.count,
            lastAccess: Date()
        )
        await Self.conditioningCache.set(audioHash: audioHash, entry: cacheEntry)

        return prepared
    }

    /// Compute a hash of audio samples for cache lookup
    /// Uses sampling to avoid hashing entire audio buffer
    private func computeAudioHash(_ audio: MLXArray) -> Int {
        let samples = audio.asArray(Float.self)
        guard !samples.isEmpty else { return 0 }

        // Sample at fixed intervals + include length for fast but unique hash
        var hasher = Hasher()
        hasher.combine(samples.count)

        // Sample 16 points evenly distributed
        let step = max(1, samples.count / 16)
        for i in stride(from: 0, to: samples.count, by: step) {
            hasher.combine(samples[i].bitPattern)
        }

        // Include first and last samples
        hasher.combine(samples.first?.bitPattern ?? 0)
        hasher.combine(samples.last?.bitPattern ?? 0)

        return hasher.finalize()
    }
}
