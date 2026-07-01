import SwiftUI

enum Theme {
    static let gradientStart = Color(red: 0.42, green: 0.27, blue: 0.93)
    static let gradientEnd = Color(red: 0.93, green: 0.31, blue: 0.61)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [gradientStart.opacity(0.18), gradientEnd.opacity(0.12), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [gradientStart, gradientEnd], startPoint: .leading, endPoint: .trailing)
    }
}

struct CardBackground: ViewModifier {
    var tint: Color = Theme.gradientStart

    func body(content: Content) -> some View {
        content
            .padding()
            .background(tint.opacity(0.12))
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            }
    }
}

extension View {
    func cardBackground(tint: Color = Theme.gradientStart) -> some View {
        modifier(CardBackground(tint: tint))
    }

    func appBackground() -> some View {
        background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
