#if os(macOS)
import Foundation

/// File locations Noelify owns. Everything lives under
/// `~/Library/Application Support/Noelify/` — nothing is written anywhere else.
enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Noelify", isDirectory: true)
    }

    /// Installed copies of the bundled wallpapers. Kept outside the .app so the desktop
    /// picture keeps working if the app is moved, and so it is never mistaken for a user original.
    static var wallpapers: URL { supportDirectory.appendingPathComponent("Wallpapers", isDirectory: true) }

    /// The wallpaper backup (also the crash-recovery marker).
    static var wallpaperBackup: URL { supportDirectory.appendingPathComponent("wallpaper-backup.json") }
}
#endif
