import SwiftUI

struct CaptionOverlay: View {
    let text: String
    let isError: Bool

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isError ? .red : .white)
                .lineLimit(6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial.opacity(0.85))
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
