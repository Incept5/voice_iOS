import SwiftUI

struct DockBar: View {
    @Binding var selectedMode: AppMode
    let onSettingsTapped: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                        Text(mode.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedMode == mode ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                onSettingsTapped()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                    Text("Settings")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }
}
