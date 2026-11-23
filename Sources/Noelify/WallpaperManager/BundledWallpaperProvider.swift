#if os(macOS)
import Foundation
import NoelifyCore

/// Installs wallpapers shipped inside `Noelify.app/Contents/Resources/Wallpapers`
/// into Noelify's Application Support folder and hands out their URLs.
///
/// Only files inside Noelify's own `Wallpapers` folder are ever written or replaced.
final class BundledWallpaperProvider: WallpaperProvider {
    /// Development preview art used until a world's final wallpaper ships (Phase 3).
    static let previewResourceName = "noelify-preview"
    private static let extensions = ["heic", "png", "jpg"]

    private let bundle: Bundle
    private let installDirectory: URL
    private let fileManager = FileManager.default

    init(bundle: Bundle = .main, installDirectory: URL) {
        self.bundle = bundle
        self.installDirectory = installDirectory
    }

    func wallpaperURL(for world: ChristmasWorld) -> URL? {
        install(world.wallpaperResourceName) ?? install(Self.previewResourceName)
    }

    /// True when `world` has no final wallpaper yet and the preview art would be used.
    func usesPreviewArt(for world: ChristmasWorld) -> Bool {
        bundledURL(world.wallpaperResourceName) == nil && bundledURL(Self.previewResourceName) != nil
    }

    private func bundledURL(_ name: String) -> URL? {
        for ext in Self.extensions {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Wallpapers") {
                return url
            }
        }
        return nil
    }

    private func install(_ name: String) -> URL? {
        guard let source = bundledURL(name) else { return nil }
        let destination = installDirectory.appendingPathComponent(source.lastPathComponent)
        do {
            try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                if fileSize(source) == fileSize(destination) { return destination }
                // An older copy of *our own* file (path is inside our folder by construction).
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            return destination
        } catch {
            NSLog("Noelify: could not install wallpaper \(name): \(error)")
            return nil
        }
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
#endif
