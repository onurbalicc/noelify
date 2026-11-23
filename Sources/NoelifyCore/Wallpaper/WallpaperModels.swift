import Foundation

/// A stable identity for a physical display.
///
/// On macOS `id` is the display's CoreGraphics UUID, which survives reboots and
/// reconnects (unlike `CGDirectDisplayID`). `name` is only for user-facing messages.
public struct DisplayIdentity: Codable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The subset of macOS desktop-picture options Noelify preserves.
/// Mirrors `NSWorkspace.DesktopImageOptionKey` without importing AppKit.
public struct WallpaperOptions: Codable, Equatable, Sendable {
    /// Raw value of `NSImageScaling`.
    public var imageScaling: Int?
    public var allowClipping: Bool?
    /// sRGB components `[r, g, b, a]` in 0...1.
    public var fillColorRGBA: [Double]?

    public init(imageScaling: Int? = nil, allowClipping: Bool? = nil, fillColorRGBA: [Double]? = nil) {
        self.imageScaling = imageScaling
        self.allowClipping = allowClipping
        self.fillColorRGBA = fillColorRGBA
    }

    /// "Fill screen": scale proportionally up or down, allow clipping.
    /// (`NSImageScaling.scaleProportionallyUpOrDown` == 3)
    public static let fillScreen = WallpaperOptions(imageScaling: 3, allowClipping: true)
}

/// A wallpaper assignment for one display.
public struct DisplayWallpaper: Codable, Equatable, Sendable {
    public var display: DisplayIdentity
    public var imageURL: URL
    public var options: WallpaperOptions

    public init(display: DisplayIdentity, imageURL: URL, options: WallpaperOptions) {
        self.display = display
        self.imageURL = imageURL
        self.options = options
    }
}

/// What Noelify writes to disk before it changes any wallpaper.
/// Only URLs and options are stored — wallpaper files are never copied, moved or modified.
public struct WallpaperBackup: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var createdAt: Date
    public var entries: [DisplayWallpaper]

    public init(version: Int = WallpaperBackup.currentVersion, createdAt: Date = Date(), entries: [DisplayWallpaper]) {
        self.version = version
        self.createdAt = createdAt
        self.entries = entries
    }

    public func entry(for display: DisplayIdentity) -> DisplayWallpaper? {
        entries.first { $0.display.id == display.id }
    }
}
