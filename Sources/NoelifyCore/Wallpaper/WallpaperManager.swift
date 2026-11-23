import Foundation

/// Result of applying a Christmas wallpaper.
public struct WallpaperApplyReport: Equatable, Sendable {
    public var applied: [DisplayIdentity] = []
    public var failed: [DisplayIdentity: String] = [:]

    public var isFullSuccess: Bool { failed.isEmpty && !applied.isEmpty }
}

/// What happened to one display during a restore.
public enum DisplayRestoreOutcome: Equatable, Sendable {
    case restored
    /// The display is not connected right now. The backup is kept so it can be restored later.
    case displayNotConnected
    /// The original image no longer exists (deleted, moved, or an unmounted volume).
    case originalFileMissing(URL)
    case failed(String)

    /// Whether retrying later could still succeed.
    public var isRetryable: Bool {
        switch self {
        case .displayNotConnected, .failed: return true
        case .restored, .originalFileMissing: return false
        }
    }
}

public struct WallpaperRestoreReport: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var display: DisplayIdentity
        public var outcome: DisplayRestoreOutcome
    }

    public var items: [Item] = []
    /// True when there was no backup to restore (nothing had been changed).
    public var nothingToRestore = false
    /// The backup file exists but could not be read.
    public var backupUnreadable: String?

    public var isComplete: Bool {
        backupUnreadable == nil && items.allSatisfy { $0.outcome == .restored }
    }

    /// A plain-language summary suitable for showing to the user. Never claims success it didn't have.
    public var summary: String {
        if let reason = backupUnreadable {
            return "Your wallpaper backup could not be read (\(reason)). Your original wallpaper was not restored — you can set it again in System Settings › Wallpaper."
        }
        if nothingToRestore { return "Your wallpaper was not changed, so there was nothing to restore." }
        if isComplete { return "Your original wallpaper was restored." }

        var parts: [String] = []
        let restored = items.filter { $0.outcome == .restored }.map(\.display.name)
        if !restored.isEmpty { parts.append("Restored on \(restored.joined(separator: ", ")).") }
        for item in items {
            switch item.outcome {
            case .restored: break
            case .displayNotConnected:
                parts.append("\(item.display.name) is not connected — it will be restored when you reconnect it and choose Restore.")
            case .originalFileMissing(let url):
                parts.append("The original picture for \(item.display.name) (\(url.lastPathComponent)) no longer exists, so it could not be restored.")
            case .failed(let reason):
                parts.append("Restoring \(item.display.name) failed: \(reason)")
            }
        }
        return parts.joined(separator: " ")
    }
}

/// Safely swaps desktop wallpapers and restores the originals.
///
/// Safety rules (all covered by tests):
/// 1. A backup is written to disk *before* the first wallpaper change. If that write
///    fails, no wallpaper is changed.
/// 2. The backup is never overwritten by a later change (e.g. switching worlds),
///    so it always holds the user's real original — never a Noelify wallpaper.
/// 3. Wallpapers inside Noelify's own wallpaper folder are never recorded as "originals".
/// 4. Image files are only referenced by URL — never copied over, moved or deleted.
/// 5. The backup is deleted only when nothing is left that a retry could restore.
public final class WallpaperManager {
    private let backend: WallpaperBackend
    private let store: WallpaperBackupStore
    private let ownedDirectory: URL?

    /// - Parameter ownedDirectory: Folder holding Noelify's installed wallpapers.
    public init(backend: WallpaperBackend, store: WallpaperBackupStore, ownedDirectory: URL?) {
        self.backend = backend
        self.store = store
        self.ownedDirectory = ownedDirectory?.standardizedFileURL
    }

    /// Whether a backup exists — i.e. Noelify changed a wallpaper and has not fully restored it.
    public var hasBackup: Bool { store.exists }

    /// Applies `imageURL` to every connected display, backing up originals first.
    @discardableResult
    public func apply(imageURL: URL, options: WallpaperOptions = .fillScreen) throws -> WallpaperApplyReport {
        guard backend.fileExists(at: imageURL) else { throw WallpaperError.wallpaperFileMissing(imageURL) }
        let displays = backend.connectedDisplays()
        guard !displays.isEmpty else { throw WallpaperError.noDisplays }

        let covered = try ensureBackup(for: displays)

        var report = WallpaperApplyReport()
        for display in displays {
            // Never change a display whose original we could not record — we couldn't restore it.
            guard covered.contains(display.id) else {
                report.failed[display] = "Its current wallpaper could not be read, so it was left unchanged."
                continue
            }
            do {
                try backend.setWallpaper(imageURL, options: options, for: display)
                report.applied.append(display)
            } catch {
                report.failed[display] = String(describing: error)
            }
        }
        return report
    }

    /// Restores the original wallpapers recorded in the backup.
    public func restore() -> WallpaperRestoreReport {
        var report = WallpaperRestoreReport()
        let backup: WallpaperBackup
        do {
            guard let loaded = try store.load() else {
                report.nothingToRestore = true
                return report
            }
            backup = loaded
        } catch {
            report.backupUnreadable = String(describing: error)
            return report
        }

        let connected = Set(backend.connectedDisplays().map(\.id))
        for entry in backup.entries {
            let outcome: DisplayRestoreOutcome
            if !connected.contains(entry.display.id) {
                outcome = .displayNotConnected
            } else if !backend.fileExists(at: entry.imageURL) {
                outcome = .originalFileMissing(entry.imageURL)
            } else {
                do {
                    try backend.setWallpaper(entry.imageURL, options: entry.options, for: entry.display)
                    outcome = .restored
                } catch {
                    outcome = .failed(String(describing: error))
                }
            }
            report.items.append(.init(display: entry.display, outcome: outcome))
        }

        let retryable = backup.entries.indices.filter { report.items[$0].outcome.isRetryable }
        if retryable.isEmpty {
            try? store.delete()
        } else {
            // Keep only what can still be restored later.
            var remaining = backup
            remaining.entries = retryable.map { backup.entries[$0] }
            try? store.save(remaining)
        }
        return report
    }

    /// Forgets the backup without restoring (explicit user choice only).
    public func discardBackup() throws {
        try store.delete()
    }

    // MARK: - Private

    /// Records the current wallpaper of every display that isn't in the backup yet.
    /// Existing entries are never replaced.
    /// - Returns: IDs of displays that are safe to change (their original is backed up,
    ///   or they already show a Noelify wallpaper).
    private func ensureBackup(for displays: [DisplayIdentity]) throws -> Set<String> {
        var backup: WallpaperBackup
        do {
            backup = try store.load() ?? WallpaperBackup(entries: [])
        } catch {
            // Refuse to continue: overwriting an unreadable backup could lose the original.
            throw WallpaperError.backupFailed("existing backup is unreadable: \(error)")
        }

        var covered = Set<String>()
        var changed = false
        for display in displays {
            if backup.entry(for: display) != nil {
                covered.insert(display.id)
                continue
            }
            guard let current = backend.currentWallpaper(for: display) else { continue }
            if isOwned(current.imageURL) {
                // Already a Noelify wallpaper (e.g. after a lost backup): safe to switch, but never an "original".
                covered.insert(display.id)
                continue
            }
            backup.entries.append(current)
            covered.insert(display.id)
            changed = true
        }

        if changed {
            do {
                try store.save(backup)
            } catch {
                throw WallpaperError.backupFailed(String(describing: error))
            }
        }
        return covered
    }

    private func isOwned(_ url: URL) -> Bool {
        guard let ownedDirectory else { return false }
        let path = url.standardizedFileURL.path
        let dir = ownedDirectory.path.hasSuffix("/") ? ownedDirectory.path : ownedDirectory.path + "/"
        return path.hasPrefix(dir)
    }
}
