import XCTest
@testable import NoelifyCore

final class WallpaperManagerTests: XCTestCase {
    private var temp: TempDirectory!
    private var backend: FakeWallpaperBackend!
    private var store: WallpaperBackupStore!
    private var owned: URL!
    private var village: URL!
    private var nordic: URL!

    override func setUp() {
        temp = TempDirectory()
        owned = temp.url.appendingPathComponent("Wallpapers", isDirectory: true)
        village = owned.appendingPathComponent("noelify-village.png")
        nordic = owned.appendingPathComponent("noelify-nordic.png")
        store = WallpaperBackupStore(fileURL: temp.url.appendingPathComponent("wallpaper-backup.json"))

        backend = FakeWallpaperBackend(displays: [Fixtures.main, Fixtures.external])
        backend.wallpapers[Fixtures.main.id] = DisplayWallpaper(
            display: Fixtures.main, imageURL: Fixtures.userPicture, options: Fixtures.userOptions)
        backend.wallpapers[Fixtures.external.id] = DisplayWallpaper(
            display: Fixtures.external, imageURL: Fixtures.userPicture2, options: .fillScreen)
        backend.existingFiles = [Fixtures.userPicture, Fixtures.userPicture2, village, nordic]
    }

    private func makeManager() -> WallpaperManager {
        WallpaperManager(backend: backend, store: store, ownedDirectory: owned)
    }

    func testApplyWritesBackupBeforeChangingAndCoversAllDisplays() throws {
        let manager = makeManager()
        let report = try manager.apply(imageURL: village)

        XCTAssertTrue(report.isFullSuccess)
        XCTAssertEqual(Set(report.applied), [Fixtures.main, Fixtures.external])
        let backup = try XCTUnwrap(store.load())
        XCTAssertEqual(backup.entry(for: Fixtures.main)?.imageURL, Fixtures.userPicture)
        XCTAssertEqual(backup.entry(for: Fixtures.main)?.options, Fixtures.userOptions)
        XCTAssertEqual(backup.entry(for: Fixtures.external)?.imageURL, Fixtures.userPicture2)
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, village)
    }

    func testSwitchingWorldsNeverOverwritesTheOriginalBackup() throws {
        let manager = makeManager()
        try manager.apply(imageURL: village)
        try manager.apply(imageURL: nordic)

        let backup = try XCTUnwrap(store.load())
        XCTAssertEqual(backup.entries.count, 2)
        XCTAssertEqual(backup.entry(for: Fixtures.main)?.imageURL, Fixtures.userPicture)
    }

    func testRestoreReturnsOriginalsWithOptionsAndDeletesBackup() throws {
        let manager = makeManager()
        try manager.apply(imageURL: village)
        let report = manager.restore()

        XCTAssertTrue(report.isComplete, report.summary)
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, Fixtures.userPicture)
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.options, Fixtures.userOptions)
        XCTAssertEqual(backend.wallpapers[Fixtures.external.id]?.imageURL, Fixtures.userPicture2)
        XCTAssertFalse(store.exists)
        XCTAssertEqual(report.summary, "Your original wallpaper was restored.")
    }

    func testRestoreWithoutBackupChangesNothing() {
        let report = makeManager().restore()
        XCTAssertTrue(report.nothingToRestore)
        XCTAssertTrue(backend.setCalls.isEmpty)
    }

    func testBackupFailurePreventsAnyWallpaperChange() throws {
        // Make the backup path unwritable by placing a regular file where its directory should be.
        let blocker = temp.url.appendingPathComponent("blocked")
        try Data("x".utf8).write(to: blocker)
        store = WallpaperBackupStore(fileURL: blocker.appendingPathComponent("backup.json"))

        XCTAssertThrowsError(try makeManager().apply(imageURL: village)) { error in
            guard case WallpaperError.backupFailed = error else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertTrue(backend.setCalls.isEmpty)
    }

    func testCorruptBackupIsNeverOverwritten() throws {
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try makeManager().apply(imageURL: village))
        XCTAssertTrue(backend.setCalls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), Data("not json".utf8))

        let report = makeManager().restore()
        XCTAssertNotNil(report.backupUnreadable)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(store.exists, "an unreadable backup must be kept for manual recovery")
    }

    func testNoelifyWallpaperIsNeverRecordedAsOriginal() throws {
        backend.wallpapers[Fixtures.main.id]?.imageURL = village // e.g. backup was lost after a crash
        let manager = makeManager()
        try manager.apply(imageURL: nordic)

        let backup = try XCTUnwrap(store.load())
        XCTAssertNil(backup.entry(for: Fixtures.main))
        XCTAssertNotNil(backup.entry(for: Fixtures.external))
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, nordic)
    }

    func testDisplayWithUnreadableWallpaperIsLeftUnchanged() throws {
        backend.unreadableDisplayIDs = [Fixtures.external.id]
        let report = try makeManager().apply(imageURL: village)

        XCTAssertEqual(report.applied, [Fixtures.main])
        XCTAssertNotNil(report.failed[Fixtures.external])
        XCTAssertEqual(backend.wallpapers[Fixtures.external.id]?.imageURL, Fixtures.userPicture2)
    }

    func testDisconnectedDisplayKeepsItsBackupForLater() throws {
        let manager = makeManager()
        try manager.apply(imageURL: village)
        backend.displays = [Fixtures.main]

        let first = manager.restore()
        XCTAssertFalse(first.isComplete)
        XCTAssertTrue(first.summary.contains("Studio Display is not connected"), first.summary)
        let remaining = try XCTUnwrap(store.load())
        XCTAssertEqual(remaining.entries.map(\.display), [Fixtures.external])

        backend.displays = [Fixtures.main, Fixtures.external]
        let second = manager.restore()
        XCTAssertTrue(second.isComplete)
        XCTAssertEqual(backend.wallpapers[Fixtures.external.id]?.imageURL, Fixtures.userPicture2)
        XCTAssertFalse(store.exists)
    }

    func testMissingOriginalIsReportedNotClaimedAsRestored() throws {
        let manager = makeManager()
        try manager.apply(imageURL: village)
        backend.existingFiles.remove(Fixtures.userPicture)

        let report = manager.restore()
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.items.first { $0.display == Fixtures.main }?.outcome,
                       .originalFileMissing(Fixtures.userPicture))
        XCTAssertEqual(backend.wallpapers[Fixtures.main.id]?.imageURL, village)
        XCTAssertFalse(store.exists, "nothing retryable remains")
    }

    func testFailedRestoreIsRetryable() throws {
        let manager = makeManager()
        try manager.apply(imageURL: village)
        backend.failingDisplayIDs = [Fixtures.main.id]

        XCTAssertFalse(manager.restore().isComplete)
        XCTAssertTrue(store.exists)

        backend.failingDisplayIDs = []
        XCTAssertTrue(manager.restore().isComplete)
    }

    func testDisplayConnectedLaterIsBackedUpOnNextApply() throws {
        backend.displays = [Fixtures.main]
        let manager = makeManager()
        try manager.apply(imageURL: village)
        backend.displays = [Fixtures.main, Fixtures.external]
        try manager.apply(imageURL: village)

        let backup = try XCTUnwrap(store.load())
        XCTAssertEqual(backup.entry(for: Fixtures.external)?.imageURL, Fixtures.userPicture2)
        XCTAssertEqual(backup.entry(for: Fixtures.main)?.imageURL, Fixtures.userPicture)
    }

    func testMissingChristmasWallpaperThrowsWithoutChanges() {
        let missing = owned.appendingPathComponent("nope.png")
        XCTAssertThrowsError(try makeManager().apply(imageURL: missing))
        XCTAssertTrue(backend.setCalls.isEmpty)
        XCTAssertFalse(store.exists)
    }

    func testBackupSurvivesProcessRestart() throws {
        try makeManager().apply(imageURL: village)
        // A brand-new manager (as after a crash + relaunch) still sees and restores the backup.
        let relaunched = WallpaperManager(backend: backend, store: WallpaperBackupStore(fileURL: store.fileURL),
                                          ownedDirectory: owned)
        XCTAssertTrue(relaunched.hasBackup)
        XCTAssertTrue(relaunched.restore().isComplete)
    }
}
