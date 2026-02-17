import AVFoundation
import Foundation
import MLXAudio
import UIKit

// MARK: - Voice Profile

struct VoiceProfile: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let audioFilePath: String // Stores filename only; legacy data may contain full paths
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

// MARK: - Sendable Wrapper

/// Wraps a non-Sendable value for use across isolation boundaries.
/// Used to pass @MainActor-isolated values (engine, player, format) into Task.detached
/// where we know the operations are thread-safe (AVAudioPlayerNode.scheduleBuffer/play).
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Voice Cloning Manager

/// On-device TTS with voice cloning using Chatterbox-Turbo 4-bit via MLXAudio
@MainActor
@Observable
final class VoiceCloningManager {
    // MARK: - State

    var isSpeaking = false
    var error: String?
    var audioLevel: Float = 0

    // Model state
    var isLoading = false
    var modelDownloadProgress: Double = 0
    var tokenizerDownloadProgress: Double = 0
    var isModelLoaded = false

    // Profile saving state
    var isSavingProfile = false

    // Voice profiles
    var currentVoiceProfileName: String?
    var availableProfiles: [VoiceProfile] = []

    // MARK: - Private

    private var engine: ChatterboxTurboEngine?
    private var preparedVoices: [String: ChatterboxTurboReferenceAudio] = [:]

    private var audioPlayer: AVAudioPlayer?
    private var meteringTask: Task<Void, Never>?

    private var currentTask: Task<Void, Never>?
    private var speakGeneration = 0

    private let sampleRate = 24000
    private let profilesDirectory: URL
    private let profilesFileURL: URL

    var isModelCached: Bool {
        UserDefaults.standard.bool(forKey: "voiceModelDownloaded")
    }

    // MARK: - Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        profilesDirectory = docs.appendingPathComponent("voice_profiles")
        profilesFileURL = docs.appendingPathComponent("voice_profiles.json")
        try? FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)

        loadSavedProfiles()
        currentVoiceProfileName = UserDefaults.standard.string(forKey: "activeVoiceProfile")
        if currentVoiceProfileName == nil
            || !availableProfiles.contains(where: { $0.name == currentVoiceProfileName })
        {
            currentVoiceProfileName = availableProfiles.first?.name
        }

        registerForMemoryWarning()
        print("[VoiceCloning] Active voice profile: \(currentVoiceProfileName ?? "none")")
    }

    private func registerForMemoryWarning() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isSpeaking else { return }
                print("[VoiceCloning] Memory warning — unloading idle TTS model")
                self.unloadModel()
            }
        }
    }

    // MARK: - Audio URL Resolution

    /// Resolves the audio file URL for a profile. Handles both filename-only (new)
    /// and legacy absolute paths by always extracting just the filename.
    private func audioURL(for profile: VoiceProfile) -> URL {
        let filename = URL(fileURLWithPath: profile.audioFilePath).lastPathComponent
        return profilesDirectory.appendingPathComponent(filename)
    }

    // MARK: - Model Management

    func loadModel() async throws {
        guard !isModelLoaded && !isLoading else { return }

        isLoading = true
        modelDownloadProgress = 0
        tokenizerDownloadProgress = 0
        error = nil

        print("[VoiceCloning] Loading model...")

        do {
            engine = ChatterboxTurboEngine(quantization: .q4)

            try await engine?.load(
                modelProgressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.modelDownloadProgress = progress.fractionCompleted
                    }
                },
                tokenizerProgressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.tokenizerDownloadProgress = progress.fractionCompleted
                    }
                }
            )

            isLoading = false
            isModelLoaded = true
            UserDefaults.standard.set(true, forKey: "voiceModelDownloaded")
            print("[VoiceCloning] Model ready")

            await prepareAllReferenceAudio()
        } catch {
            isLoading = false
            self.error = "Failed to load model: \(error.localizedDescription)"
            throw error
        }
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
            throw NSError(
                domain: "VoiceCloning", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        isSavingProfile = true
        defer { isSavingProfile = false }

        print("[VoiceCloning] Creating profile '\(name)'")

        let fileName = "\(UUID().uuidString).wav"
        let destinationURL = profilesDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: audioURL, to: destinationURL)

        let referenceAudio = try await engine.prepareReferenceAudio(from: destinationURL)

        let profile = VoiceProfile(
            name: name,
            audioFilePath: fileName,
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
        let url = audioURL(for: profile)
        try? FileManager.default.removeItem(at: url)
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
            let profiles = try? JSONDecoder().decode([VoiceProfile].self, from: data)
        else { return }
        availableProfiles = profiles
        print("[VoiceCloning] Loaded \(profiles.count) profiles")
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(availableProfiles) else { return }
        try? data.write(to: profilesFileURL, options: .atomic)
    }

    private func getReferenceAudio(for profileName: String?) async throws
        -> ChatterboxTurboReferenceAudio?
    {
        guard let name = profileName,
            let profile = availableProfiles.first(where: { $0.name == name }),
            let engine
        else {
            return nil
        }

        if let cached = preparedVoices[name] { return cached }

        let url = audioURL(for: profile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[VoiceCloning] Audio file missing for '\(name)'")
            return nil
        }

        let ref = try await engine.prepareReferenceAudio(from: url)
        preparedVoices[name] = ref
        return ref
    }

    private func prepareAllReferenceAudio() async {
        guard let engine else { return }

        for profile in availableProfiles {
            guard preparedVoices[profile.name] == nil else { continue }
            let url = audioURL(for: profile)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            do {
                let ref = try await engine.prepareReferenceAudio(from: url)
                preparedVoices[profile.name] = ref
                print("[VoiceCloning] Prepared reference audio for '\(profile.name)'")
            } catch {
                print("[VoiceCloning] Failed to prepare '\(profile.name)': \(error)")
            }
        }
    }

    // MARK: - TTS

    func speak(_ text: String, voiceProfileName: String? = nil) async {
        // Bump generation so stale completions don't clear our task reference
        speakGeneration += 1
        let myGeneration = speakGeneration

        if currentTask != nil {
            stop()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        print("[VoiceCloning] speak() — \(text.count) chars, voice: \(voiceProfileName ?? "default")")

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
        guard !cleanText.isEmpty else {
            print("[VoiceCloning] speak() — text empty after stripMarkdown")
            self.error = "Nothing to say."
            return
        }

        isSpeaking = true
        error = nil
        let profileName = voiceProfileName ?? currentVoiceProfileName

        // Use an unstructured Task so stop() can cancel it independently
        let task = Task { @MainActor in
            await self.synthesizeAndPlay(engine: engine, text: cleanText, profileName: profileName)
        }
        currentTask = task

        await task.value

        // Only clear if we're still the current generation (not superseded by a new speak())
        if speakGeneration == myGeneration {
            currentTask = nil
        }
    }

    private func synthesizeAndPlay(
        engine: ChatterboxTurboEngine, text: String, profileName: String?
    ) async {
        guard !Task.isCancelled else { return }

        do {
            let referenceAudio = try await getReferenceAudio(for: profileName)
            print("[VoiceCloning] Reference audio: \(referenceAudio?.description ?? "using default")")

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            // Stream sentence-by-sentence: play each chunk as it's generated
            print("[VoiceCloning] Streaming audio for \(text.count) chars...")
            let stream = engine.generateStreaming(text, referenceAudio: referenceAudio)
            var chunkIndex = 0

            for try await chunk in stream {
                guard !Task.isCancelled else { break }

                let samples = chunk.samples
                guard !samples.isEmpty else { continue }

                chunkIndex += 1
                print("[VoiceCloning] Chunk \(chunkIndex): \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / Double(sampleRate)))s)")

                let url = try Self.saveTempWAV(samples: samples, sampleRate: chunk.sampleRate)
                let player = try AVAudioPlayer(contentsOf: url)
                player.isMeteringEnabled = true
                self.audioPlayer = player
                player.play()

                // Wait for this chunk to finish playing
                while player.isPlaying, !Task.isCancelled {
                    player.updateMeters()
                    let power = player.averagePower(forChannel: 0)
                    audioLevel = max(0, min(1, (power + 50) / 50))
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                self.audioPlayer = nil
                try? FileManager.default.removeItem(at: url)
            }

            if chunkIndex == 0, !Task.isCancelled {
                self.error = "No audio generated. Try a different phrase."
                print("[VoiceCloning] WARNING: 0 chunks produced")
            }

            audioLevel = 0
        } catch {
            if !Task.isCancelled {
                print("[VoiceCloning] Synthesis error: \(error)")
                self.error = error.localizedDescription
            }
        }

        MLXMemory.clearCache()

        if !Task.isCancelled {
            isSpeaking = false
        }
    }

    /// Write Float samples to a temporary 16-bit WAV file for AVAudioPlayer.
    private nonisolated static func saveTempWAV(samples: [Float], sampleRate: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let numSamples = samples.count
        let bitsPerSample: Int = 16
        let bytesPerSample = bitsPerSample / 8
        let dataSize = numSamples * bytesPerSample
        let fileSize = 44 + dataSize  // WAV header is 44 bytes

        var data = Data(capacity: fileSize)

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * bytesPerSample).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bytesPerSample).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Convert Float [-1,1] → Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        try data.write(to: url)
        return url
    }

    // MARK: - Controls

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        isSpeaking = false

        audioPlayer?.stop()
        audioPlayer = nil
        meteringTask?.cancel()
        meteringTask = nil
        audioLevel = 0

        Task {
            await engine?.stop()
        }
    }

    func clearError() {
        error = nil
    }

    // MARK: - Text Processing

    private func stripMarkdown(from text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "__([^_]+)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "_([^_]+)_", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "(?m)^[\\-\\*]\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "(?m)^\\d+\\.\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\u{2014}", with: ",")
        result = result.replacingOccurrences(of: "\u{2013}", with: ",")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Shared Instance

extension VoiceCloningManager {
    static let shared = VoiceCloningManager()
}
