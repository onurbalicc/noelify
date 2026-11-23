import Foundation

/// The operating-system surface the Wallpaper Manager depends on.
/// The app provides an `NSWorkspace` implementation; tests provide a fake.
public protocol WallpaperBackend: AnyObject {
    /// Currently connected displays.
    func connectedDisplays() -> [DisplayIdentity]

    /// The wallpaper macOS reports for `display` (current Space), if any.
    func currentWallpaper(for display: DisplayIdentity) -> DisplayWallpaper?

    /// Sets the wallpaper for `display`. Must not modify the image file itself.
    func setWallpaper(_ imageURL: URL, options: WallpaperOptions, for display: DisplayIdentity) throws

    /// Whether a file exists at `url` (used to detect originals that were deleted or moved).
    func fileExists(at url: URL) -> Bool
}

public enum WallpaperError: Error, Equatable, CustomStringConvertible {
    case backupFailed(String)
    case noDisplays
    case wallpaperFileMissing(URL)

    public var description: String {
        switch self {
        case .backupFailed(let reason):
            return "Could not save a backup of your current wallpaper (\(reason)). Nothing was changed."
        case .noDisplays:
            return "No displays were found."
        case .wallpaperFileMissing(let url):
            return "The Christmas wallpaper file is missing: \(url.lastPathComponent)"
        }
    }
}
