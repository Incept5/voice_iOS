import SwiftUI
import AVFoundation
import MLXAudio

@main
struct VoiceApp: App {
    init() {
        configureAudioSession()
        MLXMemory.configure(cacheLimit: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("[VoiceApp] Audio session configuration failed: \(error)")
        }
    }
}
