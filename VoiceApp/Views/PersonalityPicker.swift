import SwiftUI

struct PersonalityPicker: View {
    @Bindable var personality: PersonalityManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Personality.allCases) { p in
                    Button {
                        personality.setPersonality(p)
                    } label: {
                        HStack(spacing: 4) {
                            Text(p.icon)
                            Text(p.rawValue)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            personality.selectedPersonality == p
                                ? Color.accentColor
                                : Color(.systemGray5)
                        )
                        .foregroundStyle(
                            personality.selectedPersonality == p
                                ? .white
                                : .primary
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
