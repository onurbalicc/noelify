import XCTest
@testable import NoelifyCore

final class ChristmasModeCoordinatorTests: XCTestCase {
    private var temp: TempDirectory!
    private var backend: FakeWallpaperBackend!
    private var provider: FakeProvider!
    private var manager: WallpaperManager!
    private var module: FakeModule!

    override func setUp() {
        temp = TempDirectory()
        let owned = temp.url.appendingPathComponent("Wallpapers")
        backend = FakeWallpaperBackend(displays: [Fixtures.main])
        backend.wallpapers[Fixtures.main.id] = DisplayWallpaper(
            display: Fixtures.main, imageURL: Fixtures.userPicture, options: Fixtures.userOptions)
        provider = FakeProvider()
        for world in ChristmasWorld.allCases {
            let url = owned.appendingPathComponent("\(world.wallpaperResourceName).png")
            provider.urls[world] = url
            backend.existingFiles.insert(url)
        }
        backend.existingFiles.insert(Fixtures.userPicture)
        manager = WallpaperManager(
            backend: backend,
            store: WallpaperBackupStore(fileURL: temp.url.appendingPathComponent("backup.json")),
            ownedDirectory: owned)
        module = FakeModule(name: "snow")
    }

    private func makeCoordinator(_ settings: NoelifySettings) -> ChristmasModeCoordinator {
        ChristmasModeCoordinator(wallpaperManager: manager, wallpaperProvider: provider,
                                 modules: [module], settings: settings)
    }

    private let consented = NoelifySettings(world: .village, changesWallpaper: true, hasConsentedToWallpaperChange: true)

    func testWallpaperIsNeverChangedWithoutConsent() {
        let c = makeCoordinator(NoelifySettings(changesWallpaper: true, hasConsentedToWallpaperChange: false))
        let report = c.activate()
        XCTAssertEqual(report.wallpaper, .notRequested)
        XCTAssertTrue(backend.setCalls.isEmpty)
        XCTAssertTrue(c.isActive)
    }

    func testActivateAndDeactivateRoundTrip() {
        let c = makeCoordinator(consented)
        guard case .applied(let applied) = c.activate().wallpaper else { return XCTFail() }
        XCTAssertTrue(applied.isFullSuccess)
        XCTAssertEqual(module.events, ["start:village"])

        let restore = c.deactivate()
        XCTAssertTrue(restore.isComplete)
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(module.events, ["start:village", "stop"])
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, Fixtures.userPicture)
    }

    func testChangingWorldWhileActiveSwapsWallpaperAndUpdatesModules() {
        let c = makeCoordinator(consented)
        c.activate()
        var s = consented
        s.world = .nordic
        let result = c.update(settings: s)
        guard case .applied? = result.activation?.wallpaper else { return XCTFail() }
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, provider.urls[.nordic])
        XCTAssertEqual(module.events.last, "update:nordic")
        XCTAssertTrue(c.deactivate().isComplete)
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, Fixtures.userPicture)
    }

    func testTurningOffWallpaperWhileActiveRestoresImmediately() {
        let c = makeCoordinator(consented)
        c.activate()
        var s = consented
        s.changesWallpaper = false
        XCTAssertEqual(c.update(settings: s).restore?.isComplete, true)
        XCTAssertTrue(c.isActive)
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, Fixtures.userPicture)
    }

    func testUnavailableWallpaperIsReportedHonestly() {
        provider.urls[.pixel] = nil
        var s = consented
        s.world = .pixel
        XCTAssertEqual(makeCoordinator(s).activate().wallpaper, .unavailable(.pixel))
        XCTAssertTrue(backend.setCalls.isEmpty)
    }

    func testFailingModuleIsReportedAndOthersStillRun() {
        module.shouldFail = true
        let c = makeCoordinator(consented)
        let report = c.activate()
        XCTAssertNotNil(report.moduleFailures["snow"])
        XCTAssertTrue(c.isActive)
        c.deactivate()
        XCTAssertFalse(module.events.contains("stop"), "a module that failed to start is not stopped")
    }

    func testDeactivateIsSafeWhenInactive() {
        let report = makeCoordinator(consented).deactivate()
        XCTAssertTrue(report.nothingToRestore)
    }
}

final class SettingsTests: XCTestCase {
    func testRoundTrip() {
        let store = SettingsStore(store: InMemoryStore())
        XCTAssertEqual(store.load(), .default)
        let s = NoelifySettings(world: .cabin, changesWallpaper: false, hasConsentedToWallpaperChange: true)
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(NoelifySettings.self, from: Data(#"{"world":"nordic"}"#.utf8))
        XCTAssertEqual(decoded.world, .nordic)
        XCTAssertEqual(decoded.changesWallpaper, NoelifySettings.default.changesWallpaper)
    }

    func testUnknownWorldFallsBackToDefault() throws {
        let decoded = try JSONDecoder().decode(NoelifySettings.self, from: Data(#"{"world":"mars"}"#.utf8))
        XCTAssertEqual(decoded.world, .village)
    }

    func testGarbageDataLoadsDefaults() {
        let kv = InMemoryStore()
        kv.setData(Data("garbage".utf8), forKey: SettingsStore.key)
        XCTAssertEqual(SettingsStore(store: kv).load(), .default)
    }
}
