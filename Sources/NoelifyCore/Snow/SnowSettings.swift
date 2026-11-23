import Foundation

/// How much snow falls.
public enum SnowIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, light, medium, heavy, blizzard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        case .blizzard: return "Blizzard"
        }
    }

    /// Flakes on a 1440 × 900 pt display at full quality.
    var baseFlakeCount: Int {
        switch self {
        case .off: return 0
        case .light: return 80
        case .medium: return 170
        case .heavy: return 330
        case .blizzard: return 640
        }
    }

    /// Heavier snowfall also comes down a little faster.
    var fallSpeedScale: Float {
        switch self {
        case .off, .light: return 1
        case .medium: return 1.08
        case .heavy: return 1.18
        case .blizzard: return 1.4
        }
    }

    /// A blizzard drives the chosen wind harder.
    var windScale: Float { self == .blizzard ? 1.35 : 1 }
}

/// How far the snow is blown sideways.
public enum SnowWind: String, Codable, CaseIterable, Identifiable, Sendable {
    case calm, breeze, windy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .calm: return "Calm"
        case .breeze: return "Breeze"
        case .windy: return "Windy"
        }
    }

    /// Steady sideways speed in points per second.
    var baseSpeed: Float {
        switch self {
        case .calm: return 0
        case .breeze: return 24
        case .windy: return 105
        }
    }

    /// How much gusts add or remove, in points per second.
    var gustSpeed: Float {
        switch self {
        case .calm: return 7
        case .breeze: return 26
        case .windy: return 75
        }
    }
}

public enum SnowSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, mixed, large

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .mixed: return "Mixed"
        case .large: return "Large"
        }
    }

    /// Multiplier range applied to each flake's base diameter.
    var scaleRange: ClosedRange<Float> {
        switch self {
        case .small: return 0.6...0.78
        case .mixed: return 0.75...1.35
        case .large: return 1.5...1.95
        }
    }
}

public enum SnowStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case realistic, soft, magical, pixel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .realistic: return "Realistic"
        case .soft: return "Soft"
        case .magical: return "Magical"
        case .pixel: return "Pixel"
        }
    }
}

/// The user's snowfall preferences. Defaults are deliberately light.
///
/// Decoding is tolerant, like `NoelifySettings`: a missing or unknown value falls back
/// to its own default without affecting the others.
public struct SnowSettings: Codable, Equatable, Sendable {
    public var intensity: SnowIntensity
    public var wind: SnowWind
    public var size: SnowSize
    public var style: SnowStyle

    public init(
        intensity: SnowIntensity = .light,
        wind: SnowWind = .breeze,
        size: SnowSize = .mixed,
        style: SnowStyle = .realistic
    ) {
        self.intensity = intensity
        self.wind = wind
        self.size = size
        self.style = style
    }

    public static let `default` = SnowSettings()

    private enum CodingKeys: String, CodingKey {
        case intensity, wind, size, style
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SnowSettings.default
        intensity = (try? c.decodeIfPresent(SnowIntensity.self, forKey: .intensity)) ?? d.intensity
        wind = (try? c.decodeIfPresent(SnowWind.self, forKey: .wind)) ?? d.wind
        size = (try? c.decodeIfPresent(SnowSize.self, forKey: .size)) ?? d.size
        style = (try? c.decodeIfPresent(SnowStyle.self, forKey: .style)) ?? d.style
    }
}
