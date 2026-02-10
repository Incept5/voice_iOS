import SwiftUI

/// Text-to-speech view with particle sphere animation
struct TTSView: View {
    @State private var manager = VoiceCloningManager.shared
    @State private var inputText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // MARK: - Sphere (flexible height)
                    SphereView(
                        isActive: manager.isSpeaking,
                        audioLevel: manager.audioLevel
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 160)
                    .background(Color.black)

                    // MARK: - Status
                    if manager.isDownloading {
                        ProgressView(value: manager.downloadProgress) {
                            Text("Downloading model...")
                                .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    if let error = manager.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    if let voiceName = manager.currentVoiceProfileName {
                        Text("Voice: \(voiceName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 8)

                    // MARK: - Input
                    VStack(spacing: 12) {
                        TextField("Enter text to speak...", text: $inputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { generate() }

                        HStack(spacing: 12) {
                            if manager.isSpeaking {
                                Button {
                                    manager.stop()
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.large)
                            } else {
                                Button {
                                    generate()
                                } label: {
                                    Label("Speak", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !manager.isModelLoaded)
                            }
                        }
                    }
                    .padding()
                }
            }
            .onTapGesture {
                isTextFieldFocused = false
            }
            .navigationTitle("Speak")
            .toolbar {
                if isTextFieldFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isTextFieldFocused = false
                        }
                    }
                }
                if !manager.isModelLoaded && !manager.isDownloading {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { try? await manager.loadModel() }
                        } label: {
                            Label(
                                manager.isModelCached ? "Load" : "Download",
                                systemImage: "arrow.down.circle"
                            )
                        }
                    }
                }
            }
        }
    }

    private func generate() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isTextFieldFocused = false

        Task {
            await manager.speak(text)
        }
    }
}

#Preview {
    TTSView()
}
