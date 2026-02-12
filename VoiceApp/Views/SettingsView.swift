import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var manager = VoiceCloningManager.shared

    var body: some View {
        NavigationStack {
            List {
                // MARK: - TTS Model
                Section {
                    if manager.isModelLoaded {
                        Label("Model Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if manager.isLoading {
                        HStack {
                            ProgressView(value: manager.loadingProgress)
                            Text("\(Int(manager.loadingProgress * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            Task { try? await manager.loadModel() }
                        } label: {
                            Label("Load Model", systemImage: "arrow.down.circle")
                        }
                    }
                } header: {
                    Text("Chatterbox Turbo")
                }

                // MARK: - Default Voice
                Section {
                    Picker("Voice", selection: Binding(
                        get: { manager.currentVoiceProfileName ?? "" },
                        set: { manager.currentVoiceProfileName = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Default").tag("")
                        ForEach(manager.availableProfiles) { profile in
                            Text(profile.name).tag(profile.name)
                        }
                    }
                } header: {
                    Text("Default Voice")
                } footer: {
                    Text("Voice used for TTS playback. \"Default\" uses the built-in engine voice.")
                }

                // MARK: - General
                Section {
                    Button {
                        hasSeenOnboarding = false
                        dismiss()
                    } label: {
                        Label("Replay Onboarding", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("General")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Voice")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("On-device AI powered by MLX")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
