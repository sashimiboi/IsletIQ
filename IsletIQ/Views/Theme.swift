import SwiftUI

enum Theme {
    // Brand
    static let primary = Color(red: 0.0, green: 0.2, blue: 0.627)         // #0033a0
    static let primaryDark = Color(red: 0.0, green: 0.176, blue: 0.56)    // #002d8f
    static let accent = Color(red: 0.36, green: 0.7, blue: 0.8)           // #5cb3cc teal
    static let teal = accent

    // Backgrounds
    static let bg = Color(red: 0.965, green: 0.97, blue: 0.98)            // slightly cool gray
    static let cardBg = Color.white
    static let muted = Color(red: 0.95, green: 0.955, blue: 0.965)

    // Text
    static let textPrimary = Color(red: 0.08, green: 0.09, blue: 0.12)
    static let textSecondary = Color(red: 0.4, green: 0.42, blue: 0.47)
    static let textTertiary = Color(red: 0.58, green: 0.6, blue: 0.64)

    // Border
    static let border = Color.black.opacity(0.08)

    // Status
    static let low = Color(red: 0.92, green: 0.3, blue: 0.3)
    static let normal = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let elevated = Color(red: 0.95, green: 0.65, blue: 0.2)
    static let high = Color(red: 0.83, green: 0.09, blue: 0.24)

    // Radius
    static let cardRadius: CGFloat = 14
    static let iconRadius: CGFloat = 8
    static let pillRadius: CGFloat = 10

    static func statusColor(_ status: GlucoseStatus) -> Color {
        switch status {
        case .low: low
        case .normal: normal
        case .elevated: elevated
        case .high: high
        }
    }
}

// MARK: - Card

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.cardBg)
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            )
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }

    func glowCard(color: Color = Theme.primary, intensity: CGFloat = 0.15) -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Icon Box (rounded square with tinted background)

struct IconBox: View {
    let icon: String
    var color: Color = Theme.primary
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.4))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}
