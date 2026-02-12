import SwiftUI

struct FunControlsView: View {
    @Bindable var personality: PersonalityManager
    @Binding var topicText: String
    let pipelineLabel: String?
    let isSpeaking: Bool
    let voiceProfileName: String?
    let onGo: () -> Void
    let onStop: () -> Void

    @FocusState private var topicFocused: Bool

    private var pipelineActive: Bool { pipelineLabel != nil }

    private var goDisabled: Bool {
        topicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pipelineActive
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Personality")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                PersonalityPicker(personality: personality)
            }

            if let voiceName = voiceProfileName {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                    Text(voiceName)
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            TextField("What should they talk about?", text: $topicText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .focused($topicFocused)
                .submitLabel(.go)
                .onSubmit {
                    if !goDisabled { onGo() }
                }

            if isSpeaking {
                Button {
                    onStop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    topicFocused = false
                    onGo()
                } label: {
                    HStack(spacing: 8) {
                        if pipelineActive {
                            ProgressView()
                                .controlSize(.small)
                            Text(pipelineLabel ?? "")
                        } else {
                            Label("Go", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(goDisabled)
            }
        }
        .toolbar {
            if topicFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { topicFocused = false }
                }
            }
        }
    }
}
