import Foundation
@testable import NoelifyCore

final class FakeWallpaperBackend: WallpaperBackend {
    struct SetError: Error, CustomStringConvertible {
        var description: String { "simulated failure" }
    }

    var displays: [DisplayIdentity]
    var wallpapers: [String: DisplayWallpaper] = [:]
    var existingFiles: Set<URL> = []
    var failingDisplayIDs: Set<String> = []
    var unreadableDisplayIDs: Set<String> = []
    private(set) var setCalls: [(URL, DisplayIdentity)] = []

    init(displays: [DisplayIdentity]) {
        self.displays = displays
    }

    func connectedDisplays() -> [DisplayIdentity] { displays }

    func currentWallpaper(for display: DisplayIdentity) -> DisplayWallpaper? {
        unreadableDisplayIDs.contains(display.id) ? nil : wallpapers[display.id]
    }

    func setWallpaper(_ imageURL: URL, options: WallpaperOptions, for display: DisplayIdentity) throws {
        if failingDisplayIDs.contains(display.id) { throw SetError() }
        setCalls.append((imageURL, display))
        wallpapers[display.id] = DisplayWallpaper(display: display, imageURL: imageURL, options: options)
    }

    func fileExists(at url: URL) -> Bool { existingFiles.contains(url) }
}

final class FakeProvider: WallpaperProvider {
    var urls: [ChristmasWorld: URL] = [:]
    func wallpaperURL(for world: ChristmasWorld) -> URL? { urls[world] }
}

final class FakeModule: EffectModule {
    let name: String
    var shouldFail = false
    private(set) var events: [String] = []
    init(name: String) { self.name = name }

    struct Failure: Error {}
    func start(with settings: NoelifySettings) throws {
        if shouldFail { throw Failure() }
        events.append("start:\(settings.world.rawValue)")
    }
    func update(with settings: NoelifySettings) { events.append("update:\(settings.world.rawValue)") }
    func stop() { events.append("stop") }
}

/// A temporary directory removed when the fixture is deinitialised.
final class TempDirectory {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("noelify-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

enum Fixtures {
    static let main = DisplayIdentity(id: "UUID-MAIN", name: "Built-in Retina Display")
    static let external = DisplayIdentity(id: "UUID-EXT", name: "Studio Display")

    static let userPicture = URL(fileURLWithPath: "/Users/test/Pictures/Lake.jpg")
    static let userPicture2 = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")
    static let userOptions = WallpaperOptions(imageScaling: 1, allowClipping: false, fillColorRGBA: [0.1, 0.2, 0.3, 1])
}
