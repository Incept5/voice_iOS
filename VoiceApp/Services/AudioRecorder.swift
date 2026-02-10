import AVFoundation
import Foundation

/// AVAudioRecorder wrapper for capturing voice samples on iOS
@MainActor
@Observable
final class AudioRecorder: NSObject {
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var audioLevel: Float = 0
    var error: String?
    var recordedFileURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var startTime: Date?

    private let sampleRate: Double = 24000 // Chatterbox native sample rate

    /// Start recording a voice sample
    func startRecording() {
        error = nil
        recordedFileURL = nil
        recordingDuration = 0

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            self.error = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_sample_\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            if recorder.record() {
                audioRecorder = recorder
                recordedFileURL = fileURL
                isRecording = true
                startTime = Date()
                startLevelMetering()
                print("[AudioRecorder] Recording started: \(fileURL.lastPathComponent)")
            } else {
                self.error = "Failed to start recording"
            }
        } catch {
            self.error = "Recording error: \(error.localizedDescription)"
        }
    }

    /// Stop recording and return the file URL
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        audioRecorder?.stop()
        stopLevelMetering()
        isRecording = false

        if let start = startTime {
            recordingDuration = Date().timeIntervalSince(start)
        }

        print("[AudioRecorder] Recording stopped: \(String(format: "%.1f", recordingDuration))s")
        return recordedFileURL
    }

    /// Delete the recorded file
    func deleteRecording() {
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
            recordedFileURL = nil
        }
        recordingDuration = 0
    }

    private func startLevelMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                recorder.updateMeters()
                // Convert from dB (-160 to 0) to 0-1 range
                let avgPower = recorder.averagePower(forChannel: 0)
                let normalizedLevel = max(0, (avgPower + 50) / 50) // -50dB to 0dB mapped to 0-1
                self.audioLevel = normalizedLevel

                if let start = self.startTime {
                    self.recordingDuration = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func stopLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.error = "Recording failed"
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.error = error?.localizedDescription ?? "Encoding error"
        }
    }
}
