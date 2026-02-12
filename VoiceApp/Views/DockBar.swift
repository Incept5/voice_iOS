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
                        Image(systemName: selectedMode == mode ? mode.filledIcon : mode.icon)
                            .font(.title3)
                        Text(mode.title)
                            .font(.caption2)
                        Circle()
                            .fill(.white)
                            .frame(width: 4, height: 4)
                            .opacity(selectedMode == mode ? 1 : 0)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .foregroundStyle(selectedMode == mode ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                onSettingsTapped()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                    Text("Settings")
                        .font(.caption2)
                    Color.clear
                        .frame(width: 4, height: 4)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        .sensoryFeedback(.selection, trigger: selectedMode)
    }
}
