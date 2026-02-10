import AVFoundation
import Foundation
import MLXAudio

// MARK: - Voice Profile

struct VoiceProfile: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let audioFilePath: String
    let sampleRate: Int
    let duration: TimeInterval
    let createdAt: Date

    init(name: String, audioFilePath: String, sampleRate: Int, duration: TimeInterval) {
        self.id = UUID()
        self.name = name
        self.audioFilePath = audioFilePath
        self.sampleRate = sampleRate
        self.duration = duration
        self.createdAt = Date()
    }
}

// MARK: - Voice Cloning Manager

/// On-device TTS with voice cloning using Chatterbox-Turbo 4-bit via MLXAudio
@MainActor
@Observable
final class VoiceCloningManager {
    // MARK: - State

    var isSpeaking = false
    var currentSentence = ""
    var error: String?
    var audioLevel: Float = 0

    // Model state
    var isDownloading = false
    var downloadProgress: Double = 0
    var isModelLoaded = false

    // Voice profiles
    var currentVoiceProfileName: String?
    var availableProfiles: [VoiceProfile] = []

    // MARK: - Private

    private var engine: ChatterboxTurboEngine?
    private var preparedVoices: [String: ChatterboxTurboReferenceAudio] = [:]

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var isPlaying = false

    private var currentTask: Task<Void, Never>?
    private var meteringTask: Task<Void, Never>?
    nonisolated(unsafe) private var isCancelled = false

    private let sampleRate = 24000
    private let profilesKey = "voiceProfiles_v1"
    private var _isModelCached = false

    var quantization: ChatterboxTurboQuantization = .q4

    var isModelCached: Bool { _isModelCached }

    var needsDownload: Bool {
        !isModelLoaded && !_isModelCached && engine == nil
    }

    // MARK: - Init

    init() {
        loadSavedProfiles()
        currentVoiceProfileName = UserDefaults.standard.string(forKey: "activeVoiceProfile")
        // Validate persisted profile still exists, auto-select first if not
        if currentVoiceProfileName == nil
            || !availableProfiles.contains(where: { $0.name == currentVoiceProfileName }) {
            currentVoiceProfileName = availableProfiles.first?.name
        }
        if let saved = UserDefaults.standard.string(forKey: "ttsQuantization"),
           let q = ChatterboxTurboQuantization(rawValue: saved) {
            quantization = q
        }
        if UserDefaults.standard.bool(forKey: "voiceModelDownloaded") {
            _isModelCached = true
        }
        print("[VoiceCloning] Active voice profile: \(currentVoiceProfileName ?? "none")")
    }

    // MARK: - Profiles Directory

    private var voiceProfilesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("voice_profiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var profilesFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("voice_profiles.json")
    }

    // MARK: - Model Management

    func loadModel() async throws {
        guard !isModelLoaded && !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        error = nil

        print("[VoiceCloning] Loading model...")

        do {
            engine = ChatterboxTurboEngine(quantization: quantization)

            try await engine?.load { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }

            isDownloading = false
            isModelLoaded = true
            _isModelCached = true

            UserDefaults.standard.set(true, forKey: "voiceModelDownloaded")
            print("[VoiceCloning] Model ready")

            await prepareAllReferenceAudio()
            await warmup()
        } catch {
            isDownloading = false
            self.error = "Failed to load model: \(error.localizedDescription)"
            throw error
        }
    }

    func setQuantization(_ value: ChatterboxTurboQuantization) {
        guard value != quantization else { return }
        quantization = value
        UserDefaults.standard.set(value.rawValue, forKey: "ttsQuantization")
        unloadModel()
    }

    func unloadModel() {
        stop()
        engine = nil
        preparedVoices.removeAll()
        isModelLoaded = false
        MLXMemory.clearCache()
        print("[VoiceCloning] Model unloaded")
    }

    // MARK: - Voice Profile Management

    func createVoiceProfile(from audioURL: URL, name: String) async throws -> VoiceProfile {
        guard let engine else {
            throw NSError(domain: "VoiceCloning", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        print("[VoiceCloning] Creating profile '\(name)'")

        let destinationURL = voiceProfilesDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try FileManager.default.copyItem(at: audioURL, to: destinationURL)

        let referenceAudio = try await engine.prepareReferenceAudio(from: destinationURL)

        let profile = VoiceProfile(
            name: name,
            audioFilePath: destinationURL.path,
            sampleRate: referenceAudio.sampleRate,
            duration: referenceAudio.duration
        )

        preparedVoices[name] = referenceAudio
        availableProfiles.append(profile)
        saveProfiles()

        print("[VoiceCloning] Profile created: \(name)")
        return profile
    }

    func deleteVoiceProfile(_ profile: VoiceProfile) {
        preparedVoices.removeValue(forKey: profile.name)
        try? FileManager.default.removeItem(atPath: profile.audioFilePath)
        availableProfiles.removeAll { $0.id == profile.id }
        if currentVoiceProfileName == profile.name {
            setActiveProfile(nil)
        }
        saveProfiles()
    }

    func setActiveProfile(_ profile: VoiceProfile?) {
        currentVoiceProfileName = profile?.name
        UserDefaults.standard.set(profile?.name, forKey: "activeVoiceProfile")
    }

    private func loadSavedProfiles() {
        guard let data = try? Data(contentsOf: profilesFileURL),
              let profiles = try? JSONDecoder().decode([VoiceProfile].self, from: data) else { return }
        availableProfiles = profiles
        print("[VoiceCloning] Loaded \(profiles.count) profiles")
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(availableProfiles) else { return }
        try? data.write(to: profilesFileURL, options: .atomic)
    }

    /// Resolve audio file path — handles stale absolute paths from container UUID changes
    private func resolveAudioPath(for profile: VoiceProfile) -> URL? {
        // Try stored path first
        let storedPath = profile.audioFilePath
        if FileManager.default.fileExists(atPath: storedPath) {
            return URL(fileURLWithPath: storedPath)
        }
        // Fall back: reconstruct from filename in current voice_profiles directory
        let filename = URL(fileURLWithPath: storedPath).lastPathComponent
        let resolved = voiceProfilesDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: resolved.path) {
            print("[VoiceCloning] Resolved stale path for '\(profile.name)' → \(resolved.path)")
            return resolved
        }
        print("[VoiceCloning] Audio file missing for '\(profile.name)': \(filename)")
        return nil
    }

    private func getReferenceAudio(for profileName: String?) async throws -> ChatterboxTurboReferenceAudio? {
        guard let name = profileName,
              let profile = availableProfiles.first(where: { $0.name == name }),
              let engine else {
            print("[VoiceCloning] getReferenceAudio: profileName=\(profileName ?? "nil"), profiles=\(availableProfiles.count), engine=\(engine != nil)")
            return nil
        }

        if let cached = preparedVoices[name] { return cached }

        guard let audioURL = resolveAudioPath(for: profile) else { return nil }

        let ref = try await engine.prepareReferenceAudio(from: audioURL)
        preparedVoices[name] = ref
        return ref
    }

    private func prepareAllReferenceAudio() async {
        guard let engine else { return }

        for profile in availableProfiles {
            guard preparedVoices[profile.name] == nil else { continue }
            guard let audioURL = resolveAudioPath(for: profile) else { continue }

            do {
                let ref = try await engine.prepareReferenceAudio(from: audioURL)
                preparedVoices[profile.name] = ref
                print("[VoiceCloning] Prepared reference audio for '\(profile.name)'")
            } catch {
                print("[VoiceCloning] Failed to prepare '\(profile.name)': \(error)")
            }
        }
    }

    /// Silent warmup: run a tiny generation to prime the compute graph so the first real speak is fast
    private func warmup() async {
        guard let engine else { return }
        print("[VoiceCloning] Warming up TTS...")
        do {
            let ref = preparedVoices.values.first
            let stream = engine.generateStreaming("Hello.", referenceAudio: ref)
            for try await _ in stream { break } // consume one chunk then stop
            await engine.stop()
            MLXMemory.clearCache()
            print("[VoiceCloning] Warmup complete")
        } catch {
            print("[VoiceCloning] Warmup failed (non-fatal): \(error)")
        }
    }

    // MARK: - TTS

    func speak(_ text: String, voiceProfileName: String? = nil) async {
        if currentTask != nil {
            stop()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        isCancelled = false

        if engine == nil || !isModelLoaded {
            do {
                try await loadModel()
            } catch {
                self.error = "Model not available"
                return
            }
        }

        guard let engine else {
            self.error = "Model failed to load"
            return
        }

        let cleanText = stripMarkdown(from: text)
        guard !cleanText.isEmpty else { return }

        isSpeaking = true
        let profileName = voiceProfileName ?? currentVoiceProfileName

        currentTask = Task { @MainActor in
            await synthesizeAndPlay(engine: engine, text: cleanText, profileName: profileName)
        }

        await currentTask?.value
        currentTask = nil
    }

    private func synthesizeAndPlay(engine: ChatterboxTurboEngine, text: String, profileName: String?) async {
        guard !isCancelled else { return }

        do {
            let referenceAudio = try await getReferenceAudio(for: profileName)
            print("[VoiceCloning] Reference audio: \(referenceAudio != nil ? "custom profile" : "default (will be auto-loaded)")")

            try setupAudioEngine()
            startMetering()

            print("[VoiceCloning] Starting streaming synthesis for: \"\(text.prefix(50))\"...")
            let stream = engine.generateStreaming(text, referenceAudio: referenceAudio)

            var totalSamples = 0
            var chunksBuffered = 0

            for try await chunk in stream {
                guard !isCancelled else { break }

                let sampleCount = chunk.samples.count
                if sampleCount > 0 {
                    scheduleAudioChunk(chunk.samples)
                    totalSamples += sampleCount
                    chunksBuffered += 1
                    print("[VoiceCloning] Chunk \(chunksBuffered): \(sampleCount) samples (\(String(format: "%.2f", Double(sampleCount) / Double(sampleRate)))s)")

                    if !isPlaying && chunksBuffered >= 1 {
                        playerNode?.play()
                        isPlaying = true
                        print("[VoiceCloning] Playback started")
                    }
                }
            }

            if !isPlaying && chunksBuffered > 0 {
                playerNode?.play()
                isPlaying = true
                print("[VoiceCloning] Playback started (after stream)")
            }

            print("[VoiceCloning] Stream complete: \(chunksBuffered) chunks, \(totalSamples) total samples")

            MLXMemory.clearCache()

            if totalSamples > 0 {
                await waitForPlaybackCompletion()
            }

            let duration = Double(totalSamples) / Double(sampleRate)
            print("[VoiceCloning] Played \(String(format: "%.1f", duration))s of audio")
        } catch {
            if !isCancelled {
                print("[VoiceCloning] Synthesis error: \(error)")
                self.error = error.localizedDescription
            }
        }

        stopAudioEngine()

        if !isCancelled {
            isSpeaking = false
        }
    }

    // MARK: - Audio Engine

    private func setupAudioEngine() throws {
        stopAudioEngine()

        // Ensure audio session is active for playback
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let avEngine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        avEngine.attach(player)

        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        avEngine.connect(player, to: avEngine.mainMixerNode, format: format)

        try avEngine.start()

        self.audioEngine = avEngine
        self.playerNode = player
        self.audioFormat = format
        self.isPlaying = false

        print("[VoiceCloning] Audio engine started (format: \(format))")
    }

    private func scheduleAudioChunk(_ samples: [Float]) {
        guard let playerNode, let format = audioFormat else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            _ = samples.withUnsafeBufferPointer { srcPtr in
                memcpy(channelData, srcPtr.baseAddress!, samples.count * MemoryLayout<Float>.size)
            }
        }

        playerNode.scheduleBuffer(buffer)
    }

    private func waitForPlaybackCompletion() async {
        guard let playerNode, let format = audioFormat else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard let emptyBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else {
                continuation.resume()
                return
            }
            emptyBuffer.frameLength = 1
            playerNode.scheduleBuffer(emptyBuffer) {
                continuation.resume()
            }
        }
    }

    private func stopAudioEngine() {
        stopMetering()
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        audioFormat = nil
        isPlaying = false
        audioLevel = 0
    }

    // MARK: - Metering

    private func startMetering() {
        meteringTask?.cancel()

        meteringTask = Task { @MainActor in
            var phase: Float = 0
            var targetLevel: Float = 0.7
            var currentLevel: Float = 0

            while !Task.isCancelled {
                if self.isPlaying {
                    phase += Float.random(in: 0.08...0.15)
                    let baseWave = 0.5 + 0.3 * sin(phase)
                    let microPulse = Float.random(in: -0.2...0.3)
                    let emphasis: Float = Float.random(in: 0...1) > 0.85 ? Float.random(in: 0.2...0.4) : 0
                    targetLevel = max(0.3, min(1.0, baseWave + microPulse + emphasis))
                    currentLevel += (targetLevel - currentLevel) * 0.3
                    self.audioLevel = currentLevel
                } else {
                    currentLevel *= 0.80
                    self.audioLevel = currentLevel
                    phase = 0
                }

                try? await Task.sleep(nanoseconds: 16_666_667) // ~60fps
            }
        }
    }

    private func stopMetering() {
        meteringTask?.cancel()
        meteringTask = nil

        Task { @MainActor in
            for _ in 0..<10 {
                self.audioLevel *= 0.7
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            self.audioLevel = 0
        }
    }

    // MARK: - Controls

    func stop() {
        isCancelled = true
        isSpeaking = false
        isPlaying = false

        stopAudioEngine()

        currentTask?.cancel()
        currentTask = nil
        currentSentence = ""
        audioLevel = 0

        Task { @MainActor in
            await engine?.stop()
        }
    }

    // MARK: - Text Processing

    private func stripMarkdown(from text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_([^_]+)_", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^[\\-\\*]\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^\\d+\\.\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\u{2014}", with: ",")
        result = result.replacingOccurrences(of: "\u{2013}", with: ",")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Shared Instance

extension VoiceCloningManager {
    static let shared = VoiceCloningManager()
}
