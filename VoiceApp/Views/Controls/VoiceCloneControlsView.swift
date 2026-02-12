import SwiftUI

struct VoiceCloneControlsView: View {
    @Bindable var manager: VoiceCloningManager
    @Binding var showVoiceSetup: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "mic.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.currentVoiceProfileName ?? "Default Voice")
                        .font(.headline)
                    Text(profileSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                showVoiceSetup = true
            } label: {
                Label("Record Voice Sample", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)

            if !manager.availableProfiles.isEmpty {
                Button {
                    showVoiceSetup = true
                } label: {
                    Label("Manage Profiles", systemImage: "person.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var profileSubtitle: String {
        let count = manager.availableProfiles.count
        if count == 0 {
            return "No saved profiles"
        } else if count == 1 {
            return "1 saved profile"
        } else {
            return "\(count) saved profiles"
        }
    }
}
