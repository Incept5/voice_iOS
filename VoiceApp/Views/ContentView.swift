import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Speak", systemImage: "waveform") {
                TTSView()
            }

            Tab("Voice", systemImage: "mic.fill") {
                VoiceSetupView()
            }
        }
    }
}

#Preview {
    ContentView()
}
