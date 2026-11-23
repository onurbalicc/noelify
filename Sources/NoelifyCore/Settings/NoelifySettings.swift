import Foundation

/// All user-facing preferences. Persisted as JSON.
///
/// Decoding is tolerant: any missing key falls back to its default, so adding
/// new settings in later versions never wipes a user's existing preferences.
public struct NoelifySettings: Codable, Equatable, Sendable {
    /// The selected Christmas World.
    public var world: ChristmasWorld
    /// Whether Christmas Mode is allowed to change the desktop wallpaper.
    public var changesWallpaper: Bool
    /// The user has explicitly agreed (once) that Noelify may change the wallpaper.
    public var hasConsentedToWallpaperChange: Bool
    /// Snowfall preferences.
    public var snow: SnowSettings

    public init(
        world: ChristmasWorld = .village,
        changesWallpaper: Bool = true,
        hasConsentedToWallpaperChange: Bool = false,
        snow: SnowSettings = .default
    ) {
        self.world = world
        self.changesWallpaper = changesWallpaper
        self.hasConsentedToWallpaperChange = hasConsentedToWallpaperChange
        self.snow = snow
    }

    public static let `default` = NoelifySettings()

    private enum CodingKeys: String, CodingKey {
        case world, changesWallpaper, hasConsentedToWallpaperChange, snow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NoelifySettings.default
        // An unknown world (e.g. from a newer version) falls back to the default.
        world = (try? c.decodeIfPresent(ChristmasWorld.self, forKey: .world)) ?? d.world
        changesWallpaper = try c.decodeIfPresent(Bool.self, forKey: .changesWallpaper) ?? d.changesWallpaper
        hasConsentedToWallpaperChange = try c.decodeIfPresent(Bool.self, forKey: .hasConsentedToWallpaperChange)
            ?? d.hasConsentedToWallpaperChange
        snow = (try? c.decodeIfPresent(SnowSettings.self, forKey: .snow)) ?? d.snow
    }
}
