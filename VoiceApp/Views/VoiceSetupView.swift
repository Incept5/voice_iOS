import SwiftUI

/// Record a voice sample and manage voice profiles
struct VoiceSetupView: View {
    @State private var recorder = AudioRecorder()
    @State private var manager = VoiceCloningManager.shared
    @State private var profileName = ""
    @State private var showingNamePrompt = false
    @State private var recordedURL: URL?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Model Section
                Section {
                    if manager.isModelLoaded {
                        Label("Model Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if manager.isDownloading {
                        HStack {
                            ProgressView(value: manager.downloadProgress)
                            Text("\(Int(manager.downloadProgress * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            Task { try? await manager.loadModel() }
                        } label: {
                            Label(
                                manager.isModelCached ? "Load Model" : "Download Model",
                                systemImage: "arrow.down.circle"
                            )
                        }
                    }
                } header: {
                    Text("Chatterbox Turbo")
                }

                // MARK: - Recording Section
                Section {
                    if recorder.isRecording {
                        VStack(spacing: 12) {
                            // Level indicator
                            HStack(spacing: 2) {
                                ForEach(0..<20, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(barColor(for: i, level: recorder.audioLevel))
                                        .frame(width: 8, height: 24)
                                        .scaleEffect(y: Float(i) < recorder.audioLevel * 20 ? 1.0 : 0.3, anchor: .bottom)
                                        .animation(.easeOut(duration: 0.1), value: recorder.audioLevel)
                                }
                            }
                            .frame(height: 24)

                            Text(formatDuration(recorder.recordingDuration))
                                .font(.title2.monospacedDigit())

                            Text("Record 15-30 seconds of your voice")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        Button(role: .destructive) {
                            stopRecording()
                        } label: {
                            Label("Stop Recording", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    } else if let url = recordedURL {
                        HStack {
                            Label("Recording Ready", systemImage: "waveform")
                            Spacer()
                            Text(formatDuration(recorder.recordingDuration))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            showingNamePrompt = true
                        } label: {
                            Label("Save as Voice Profile", systemImage: "person.crop.circle.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!manager.isModelLoaded)

                        Button(role: .destructive) {
                            recorder.deleteRecording()
                            recordedURL = nil
                        } label: {
                            Label("Discard", systemImage: "trash")
                        }
                    } else {
                        Button {
                            recorder.startRecording()
                        } label: {
                            Label("Start Recording", systemImage: "mic.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if let error = recorder.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Voice Sample")
                } footer: {
                    Text("Speak naturally for 15-30 seconds. Read a passage or talk about your day.")
                }

                // MARK: - Profiles Section
                Section {
                    if manager.availableProfiles.isEmpty {
                        Text("No voice profiles yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.availableProfiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.headline)
                                    Text("\(String(format: "%.1f", profile.duration))s sample")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if manager.currentVoiceProfileName == profile.name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    Button("Select") {
                                        manager.setActiveProfile(profile)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                manager.deleteVoiceProfile(manager.availableProfiles[index])
                            }
                        }
                    }
                } header: {
                    Text("Voice Profiles")
                }
            }
            .navigationTitle("Voice")
            .alert("Name Your Voice", isPresented: $showingNamePrompt) {
                TextField("Voice name", text: $profileName)
                Button("Save") { saveProfile() }
                Button("Cancel", role: .cancel) { profileName = "" }
            } message: {
                Text("Enter a name for this voice profile.")
            }
        }
    }

    private func stopRecording() {
        recordedURL = recorder.stopRecording()
    }

    private func saveProfile() {
        guard let url = recordedURL, !profileName.isEmpty else { return }

        Task {
            do {
                let profile = try await manager.createVoiceProfile(from: url, name: profileName)
                manager.setActiveProfile(profile)
                recordedURL = nil
                profileName = ""
                recorder.deleteRecording()
            } catch {
                manager.error = error.localizedDescription
            }
        }
    }

    private func barColor(for index: Int, level: Float) -> Color {
        let threshold = Float(index) / 20.0
        guard threshold < level else { return Color.gray.opacity(0.3) }

        if threshold < 0.5 {
            return .green
        } else if threshold < 0.75 {
            return .yellow
        } else {
            return .red
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VoiceSetupView()
}
