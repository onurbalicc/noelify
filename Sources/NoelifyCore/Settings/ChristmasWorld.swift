import Foundation

/// The selectable Christmas Worlds (themes).
public enum ChristmasWorld: String, Codable, CaseIterable, Identifiable, Sendable {
    case village
    case nordic
    case cabin
    case pixel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .village: return "Christmas Village"
        case .nordic: return "Nordic Night"
        case .cabin: return "Cozy Cabin"
        case .pixel: return "Pixel Christmas"
        }
    }

    public var shortName: String {
        switch self {
        case .village: return "Village"
        case .nordic: return "Nordic"
        case .cabin: return "Cabin"
        case .pixel: return "Pixel"
        }
    }

    public var tagline: String {
        switch self {
        case .village: return "Lantern-lit streets and a town square tree"
        case .nordic: return "Aurora skies over a frozen lake"
        case .cabin: return "Warm windows deep in a snowy forest"
        case .pixel: return "A nostalgic 16-bit winter town"
        }
    }

    /// Base file name (without extension) of the bundled wallpaper for this world.
    public var wallpaperResourceName: String { "noelify-\(rawValue)" }
}
