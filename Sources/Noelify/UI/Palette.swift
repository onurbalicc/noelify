#if os(macOS)
import SwiftUI
import NoelifyCore

/// Noelify design tokens. The Control Center is always rendered in dark appearance,
/// so these colours are tuned for legibility on Midnight Navy (all text pairs ≥ 4.5:1).
enum Palette {
    static let midnightNavy = Color(hex: 0x101B30)
    static let deepNavy = Color(hex: 0x0A1222)
    static let winterBlue = Color(hex: 0x8ABFE6)
    static let snowWhite = Color(hex: 0xF5F9FF)
    static let christmasGold = Color(hex: 0xE8B768)
    static let pineGreen = Color(hex: 0x214F43)
    static let cranberry = Color(hex: 0xA83B4A)

    /// Secondary text on navy (#AFC0D6 on #101B30 ≈ 9:1).
    static let mutedText = Color(hex: 0xAFC0D6)
    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)

    static var background: LinearGradient {
        LinearGradient(colors: [midnightNavy.opacity(0.92), deepNavy.opacity(0.96)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Sky colours for each world's miniature preview tile.
    static func sky(for world: ChristmasWorld) -> [Color] {
        switch world {
        case .village: return [Color(hex: 0x0E1A3A), Color(hex: 0x2A3F75), Color(hex: 0x4A4A7A)]
        case .nordic: return [Color(hex: 0x061226), Color(hex: 0x163B5C), Color(hex: 0x2E7D6E)]
        case .cabin: return [Color(hex: 0x15112A), Color(hex: 0x3A2440), Color(hex: 0x6B3A3A)]
        case .pixel: return [Color(hex: 0x1B1F4B), Color(hex: 0x33407A), Color(hex: 0x5D6BB0)]
        }
    }

    static func accent(for world: ChristmasWorld) -> Color {
        switch world {
        case .village: return christmasGold
        case .nordic: return Color(hex: 0x7EE0C3)
        case .cabin: return Color(hex: 0xF0995E)
        case .pixel: return Color(hex: 0xFFD966)
        }
    }

    static func symbol(for world: ChristmasWorld) -> String {
        switch world {
        case .village: return "house.fill"
        case .nordic: return "moon.stars.fill"
        case .cabin: return "fireplace.fill"
        case .pixel: return "square.grid.3x3.fill"
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
#endif
