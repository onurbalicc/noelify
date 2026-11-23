#if os(macOS)
import AppKit
import NoelifyCore

/// `WallpaperBackend` implemented with public `NSWorkspace` desktop-picture APIs only.
///
/// Known platform limits (documented in docs/PLATFORM_LIMITS.md):
/// - macOS reports and sets the picture of the *current Space* on each display.
/// - Aerial / "Shuffle" / system-managed wallpapers aren't exposed as files by the
///   public API, so they can only be restored as the still image macOS reports.
final class MacWallpaperBackend: WallpaperBackend {
    enum BackendError: Error, CustomStringConvertible {
        case displayNotFound(String)
        var description: String {
            switch self {
            case .displayNotFound(let name): return "\(name) is no longer connected."
            }
        }
    }

    private let workspace = NSWorkspace.shared

    func connectedDisplays() -> [DisplayIdentity] {
        NSScreen.screens.compactMap(Self.identity(of:))
    }

    func currentWallpaper(for display: DisplayIdentity) -> DisplayWallpaper? {
        guard let screen = screen(for: display),
              let url = workspace.desktopImageURL(for: screen)
        else { return nil }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        return DisplayWallpaper(display: display, imageURL: url, options: Self.wallpaperOptions(from: options))
    }

    func setWallpaper(_ imageURL: URL, options: WallpaperOptions, for display: DisplayIdentity) throws {
        guard let screen = screen(for: display) else { throw BackendError.displayNotFound(display.name) }
        try workspace.setDesktopImageURL(imageURL, for: screen, options: Self.dictionary(from: options))
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Display identity

    private func screen(for display: DisplayIdentity) -> NSScreen? {
        NSScreen.screens.first { Self.identity(of: $0)?.id == display.id }
    }

    static func identity(of screen: NSScreen) -> DisplayIdentity? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)

        let id: String
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let cfString = CFUUIDCreateString(kCFAllocatorDefault, uuid) {
            id = cfString as String
        } else {
            id = "display-\(displayID)"
        }
        return DisplayIdentity(id: id, name: screen.localizedName)
    }

    // MARK: - Options conversion

    static func wallpaperOptions(from dict: [NSWorkspace.DesktopImageOptionKey: Any]) -> WallpaperOptions {
        var options = WallpaperOptions()
        options.imageScaling = (dict[.imageScaling] as? NSNumber)?.intValue
        options.allowClipping = (dict[.allowClipping] as? NSNumber)?.boolValue
        if let color = (dict[.fillColor] as? NSColor)?.usingColorSpace(.sRGB) {
            options.fillColorRGBA = [
                Double(color.redComponent), Double(color.greenComponent),
                Double(color.blueComponent), Double(color.alphaComponent),
            ]
        }
        return options
    }

    static func dictionary(from options: WallpaperOptions) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var dict: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = options.imageScaling { dict[.imageScaling] = NSNumber(value: scaling) }
        if let clipping = options.allowClipping { dict[.allowClipping] = NSNumber(value: clipping) }
        if let rgba = options.fillColorRGBA, rgba.count == 4 {
            dict[.fillColor] = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }
        return dict
    }
}
#endif
