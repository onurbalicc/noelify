import Foundation

/// Persists the wallpaper backup as a small JSON file.
///
/// The file lives in Noelify's own Application Support folder and doubles as a
/// crash marker: if it exists at launch, a previous session changed the wallpaper
/// and never restored it.
public final class WallpaperBackupStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public var exists: Bool { fileManager.fileExists(atPath: fileURL.path) }

    /// Returns the stored backup. A corrupt file is reported as an error rather than
    /// silently ignored, so we never "forget" a user's original wallpaper.
    public func load() throws -> WallpaperBackup? {
        guard exists else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WallpaperBackup.self, from: data)
    }

    /// Writes atomically (temp file + rename) so a crash mid-write cannot corrupt it.
    public func save(_ backup: WallpaperBackup) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        try data.write(to: fileURL, options: .atomic)
        // Readable by the user only.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func delete() throws {
        guard exists else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
