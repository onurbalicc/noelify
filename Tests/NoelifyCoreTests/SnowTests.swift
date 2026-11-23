import XCTest
@testable import NoelifyCore

private func config(
    _ intensity: SnowIntensity = .medium, _ wind: SnowWind = .calm, _ size: SnowSize = .mixed,
    _ style: SnowStyle = .realistic, power: PowerCondition = .pluggedIn
) -> SnowRenderConfiguration {
    SnowRenderConfiguration(settings: SnowSettings(intensity: intensity, wind: wind, size: size, style: style),
                            power: power)
}

private func field(_ configuration: SnowRenderConfiguration, seed: UInt64 = 7) -> SnowField {
    SnowField(width: 1440, height: 900, configuration: configuration, seed: seed)
}

private extension SnowField {
    mutating func run(seconds: Double, fps: Double = 60) {
        for _ in 0..<Int(seconds * fps) { step(1 / fps) }
    }

    var meanSize: Float { flakes.map(\.size).reduce(0, +) / Float(max(flakes.count, 1)) }
    func meanSize(of layer: SnowLayer) -> Float {
        let sizes = flakes.filter { $0.layer == layer }.map(\.size)
        return sizes.reduce(0, +) / Float(max(sizes.count, 1))
    }
}

final class SnowSettingsTests: XCTestCase {
    func testDefaultsAreLight() {
        XCTAssertEqual(NoelifySettings.default.snow.intensity, .light)
        XCTAssertEqual(NoelifySettings.default.snow.style, .realistic)
    }

    func testEveryCombinationSurvivesRestart() {
        let kv = InMemoryStore()
        for intensity in SnowIntensity.allCases {
            for wind in SnowWind.allCases {
                for size in SnowSize.allCases {
                    for style in SnowStyle.allCases {
                        var s = NoelifySettings.default
                        s.snow = SnowSettings(intensity: intensity, wind: wind, size: size, style: style)
                        SettingsStore(store: kv).save(s)
                        XCTAssertEqual(SettingsStore(store: kv).load(), s)
                    }
                }
            }
        }
    }

    func testPhaseOneSettingsKeepTheirValuesAndGainDefaultSnow() throws {
        let json = #"{"world":"cabin","changesWallpaper":false,"hasConsentedToWallpaperChange":true}"#
        let decoded = try JSONDecoder().decode(NoelifySettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, NoelifySettings(world: .cabin, changesWallpaper: false,
                                                hasConsentedToWallpaperChange: true))
    }

    func testUnknownSnowValuesFallBackIndividually() throws {
        let json = #"{"world":"nordic","snow":{"intensity":"hail","wind":"windy","size":3,"style":"pixel"}}"#
        let decoded = try JSONDecoder().decode(NoelifySettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.world, .nordic)
        XCTAssertEqual(decoded.snow, SnowSettings(intensity: .light, wind: .windy, size: .mixed, style: .pixel))
    }

    func testMalformedSnowDoesNotLoseOtherSettings() throws {
        let decoded = try JSONDecoder().decode(NoelifySettings.self, from: Data(#"{"world":"pixel","snow":"x"}"#.utf8))
        XCTAssertEqual(decoded.world, .pixel)
        XCTAssertEqual(decoded.snow, .default)
    }
}

final class SnowRenderConfigurationTests: XCTestCase {
    func testEachIntensityHasMoreFlakes() {
        let counts = SnowIntensity.allCases.map { config($0).flakeCount(width: 1440, height: 900) }
        XCTAssertEqual(counts.first, 0)
        XCTAssertEqual(counts, counts.sorted())
        XCTAssertEqual(Set(counts).count, counts.count)
    }

    func testBatteryReducesWork() {
        let ac = config(.blizzard, power: .pluggedIn), battery = config(.blizzard, power: .battery)
        let low = config(.blizzard, power: .constrained)
        let counts = [low, battery, ac].map { $0.flakeCount(width: 1440, height: 900) }
        XCTAssertTrue(counts[0] < counts[1] && counts[1] < counts[2])
        XCTAssertTrue(low.framesPerSecond < battery.framesPerSecond)
        XCTAssertTrue(battery.framesPerSecond < ac.framesPerSecond)
        XCTAssertTrue(battery.renderScale < ac.renderScale)
    }

    func testOnlyFastSnowOnPowerRunsAtSixtyFrames() {
        XCTAssertEqual(SnowRenderConfiguration(settings: .default, power: .pluggedIn).framesPerSecond, 30)
        XCTAssertEqual(config(.light, .windy).framesPerSecond, 60)
        XCTAssertEqual(config(.blizzard).framesPerSecond, 60)
        XCTAssertEqual(config(.blizzard, .windy, .mixed, .pixel).framesPerSecond, 30)
        XCTAssertEqual(config(.blizzard, .windy, power: .battery).framesPerSecond, 30)
    }

    func testCountScalesWithAreaWithinLimits() {
        let c = config()
        XCTAssertGreaterThan(c.flakeCount(width: 2560, height: 1440), c.flakeCount(width: 1440, height: 900))
        XCTAssertEqual(c.flakeCount(width: 20_000, height: 20_000), c.flakeCount(width: 10_000, height: 10_000))
        XCTAssertEqual(c.flakeCount(width: 0, height: 900), 0)
    }
}

final class SnowFieldTests: XCTestCase {
    func testUsesAllThreeLayersWithParallax() {
        let f = field(config(.blizzard))
        for layer in SnowLayer.allCases { XCTAssertTrue(f.flakes.contains { $0.layer == layer }) }
        XCTAssertLessThan(f.meanSize(of: .far), f.meanSize(of: .mid))
        XCTAssertLessThan(f.meanSize(of: .mid), f.meanSize(of: .near))
    }

    func testNearFlakesFallFaster() {
        var f = field(config(.blizzard))
        let before = f.flakes
        f.run(seconds: 0.5)
        func meanDrop(_ layer: SnowLayer) -> Float {
            let drops = zip(before, f.flakes).filter { $0.0.layer == layer && $0.1.y < $0.0.y }.map { $0.0.y - $0.1.y }
            return drops.reduce(0, +) / Float(max(drops.count, 1))
        }
        XCTAssertLessThan(meanDrop(.far), meanDrop(.mid))
        XCTAssertLessThan(meanDrop(.mid), meanDrop(.near))
    }

    func testFlakesStayNearTheDisplayForever() {
        var f = field(config(.blizzard, .windy))
        for _ in 0..<120 {
            f.run(seconds: 1, fps: 30)
            for flake in f.flakes {
                XCTAssertTrue(flake.x.isFinite && flake.y.isFinite)
                XCTAssertTrue((-80...1520).contains(flake.x), "x \(flake.x)")
                XCTAssertTrue((-80...980).contains(flake.y), "y \(flake.y)")
                XCTAssertTrue((0...1).contains(flake.opacity))
            }
        }
        XCTAssertEqual(f.flakes.count, f.targetCount)
    }

    func testSnowStaysEvenlySpreadInStrongWind() {
        var f = field(config(.blizzard, .windy))
        f.run(seconds: 90, fps: 30)
        let left = f.flakes.filter { $0.x < 720 }.count
        let top = f.flakes.filter { $0.y > 450 }.count
        XCTAssertTrue((0.36...0.64).contains(Double(left) / Double(f.flakes.count)), "left \(left)")
        XCTAssertTrue((0.36...0.64).contains(Double(top) / Double(f.flakes.count)), "top \(top)")
    }

    func testReenteringFlakesArriveFromOutsideTheDisplay() {
        var f = field(config(.heavy, .windy))
        f.run(seconds: 3)
        var arrivals = 0
        for _ in 0..<600 {
            let before = f.flakes
            f.step(1 / 60)
            for (a, b) in zip(before, f.flakes) where abs(a.x - b.x) > 40 || abs(a.y - b.y) > 40 {
                arrivals += 1
                let outside = b.x < 0 || b.x > 1440 || b.y > 900
                XCTAssertTrue(outside, "popped in at \(b.x), \(b.y)")
            }
        }
        XCTAssertGreaterThan(arrivals, 20)
    }

    func testWindPushesSnowSideways() {
        func sidewaysSpeed(_ wind: SnowWind) -> Float {
            var f = field(config(.heavy, wind))
            f.run(seconds: 2)
            var total: Float = 0, samples: Float = 0
            for _ in 0..<600 {
                let before = f.flakes
                f.step(1 / 60)
                for (a, b) in zip(before, f.flakes) where abs(a.x - b.x) < 40 {
                    total += (b.x - a.x) * 60
                    samples += 1
                }
            }
            return total / samples
        }
        let calm = sidewaysSpeed(.calm), breeze = sidewaysSpeed(.breeze), windy = sidewaysSpeed(.windy)
        XCTAssertLessThan(abs(calm), 10)
        XCTAssertGreaterThan(breeze, abs(calm) + 6)
        XCTAssertGreaterThan(windy, breeze + 25)
    }

    func testChangingWindEasesInInsteadOfJumping() {
        var f = field(config(.medium, .calm))
        f.run(seconds: 3)
        f.apply(config(.medium, .windy))
        let before = f.flakes
        f.step(1 / 60)
        for (a, b) in zip(before, f.flakes) where abs(a.x - b.x) < 40 {
            XCTAssertLessThan(abs(b.x - a.x) * 60, 70)
        }
    }

    func testSizeSettingChangesFlakeSize() {
        for style in SnowStyle.allCases {
            let small = field(config(.heavy, .calm, .small, style)).meanSize
            let mixed = field(config(.heavy, .calm, .mixed, style)).meanSize
            let large = field(config(.heavy, .calm, .large, style)).meanSize
            XCTAssertLessThan(small, mixed, "\(style)")
            XCTAssertLessThan(mixed, large, "\(style)")
        }
    }

    func testEachStyleDrawsWithItsOwnSprites() {
        let sprites = SnowStyle.allCases.map { Set(field(config(.blizzard, .calm, .mixed, $0)).flakes.map(\.sprite)) }
        for i in sprites.indices {
            for j in sprites.indices where j > i { XCTAssertTrue(sprites[i].isDisjoint(with: sprites[j])) }
        }
        XCTAssertTrue(sprites[SnowStyle.allCases.firstIndex(of: .pixel)!].allSatisfy(\.isPixelArt))
    }

    func testChangingIntensityAddsAndFadesOutFlakes() {
        var f = field(config(.light))
        f.run(seconds: 3)
        let light = f.flakes.count
        f.apply(config(.heavy))
        XCTAssertEqual(f.flakes.count, f.targetCount)
        f.run(seconds: 3)
        f.apply(config(.light))
        XCTAssertGreaterThan(f.flakes.count, light, "flakes fade out rather than vanish")
        f.run(seconds: 2)
        XCTAssertEqual(f.flakes.count, light)
    }

    func testRapidIntensityChangesSettleOnTheRightCount() {
        var f = field(config(.light))
        for i in 0..<200 {
            f.apply(config(SnowIntensity.allCases[i % SnowIntensity.allCases.count]))
            f.step(1 / 60)
        }
        f.apply(config(.medium))
        f.run(seconds: 3)
        XCTAssertEqual(f.flakes.count, f.targetCount)
    }

    func testRestylingKeepsPositions() {
        var f = field(config(.medium))
        f.run(seconds: 3)
        let before = f.flakes
        f.apply(config(.medium, .calm, .mixed, .magical))
        XCTAssertEqual(before.map(\.x), f.flakes.map(\.x))
        XCTAssertEqual(before.map(\.y), f.flakes.map(\.y))
        XCTAssertNotEqual(before.map(\.sprite), f.flakes.map(\.sprite))
    }

    func testLongPausesAreClamped() {
        var f = field(config())
        f.run(seconds: 3)
        let before = f.flakes
        f.step(3600) // a Mac waking from sleep
        for (a, b) in zip(before, f.flakes) where b.y <= a.y { XCTAssertLessThan(a.y - b.y, 30) }
        f.step(0); f.step(-1); f.step(.nan); f.step(.infinity)
        XCTAssertTrue(f.flakes.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testResizeSpreadsSnowOverTheNewDisplay() {
        var f = field(config(.heavy))
        f.run(seconds: 3)
        f.resize(width: 2560, height: 1440)
        XCTAssertEqual(f.flakes.filter { !$0.isLeaving }.count, f.targetCount)
        XCTAssertTrue(f.flakes.contains { $0.x > 1600 })
        f.resize(width: 800, height: 600)
        f.run(seconds: 3)
        XCTAssertEqual(f.flakes.count, f.targetCount)
        XCTAssertTrue(f.flakes.allSatisfy { $0.x < 880 && $0.y < 680 })
    }

    func testSameSeedReproducesAndDifferentSeedsDiffer() {
        var a = field(config(), seed: 1), b = field(config(), seed: 1), c = field(config(), seed: 2)
        a.run(seconds: 1); b.run(seconds: 1); c.run(seconds: 1)
        XCTAssertEqual(a.flakes.map(\.x), b.flakes.map(\.x))
        XCTAssertNotEqual(a.flakes.map(\.x), c.flakes.map(\.x))
    }

    func testMotionDoesNotLoop() {
        var f = field(config(.light, .breeze))
        f.run(seconds: 5)
        let start = f.flakes.map(\.x)
        for _ in 0..<60 {
            f.run(seconds: 1, fps: 30)
            XCTAssertNotEqual(start, f.flakes.map(\.x))
        }
    }

    func testOffMeansNoFlakes() {
        XCTAssertTrue(field(config(.off)).flakes.isEmpty)
    }
}

final class SnowEffectModuleTests: XCTestCase {
    private final class FakeHost: SnowOverlayHost {
        var isShowing = false
        var shown: [SnowRenderConfiguration] = []
        var hides = 0
        func show(_ configuration: SnowRenderConfiguration) { isShowing = true; shown.append(configuration) }
        func hide() { isShowing = false; hides += 1 }
    }

    private final class FakePower: PowerMonitor {
        var condition = PowerCondition.pluggedIn
        var onChange: (() -> Void)?
        var starts = 0
        func start(onChange: @escaping () -> Void) { starts += 1; self.onChange = onChange }
        func stop() { onChange = nil }
    }

    private let host = FakeHost()
    private let power = FakePower()
    private lazy var module = SnowEffectModule(host: host, power: power)

    private func settings(_ intensity: SnowIntensity, _ style: SnowStyle = .realistic) -> NoelifySettings {
        NoelifySettings(snow: SnowSettings(intensity: intensity, style: style))
    }

    func testStartShowsChosenSettingsAndStopReleasesEverything() throws {
        try module.start(with: settings(.heavy, .magical))
        XCTAssertEqual(host.shown.last?.settings, SnowSettings(intensity: .heavy, style: .magical))
        module.stop()
        XCTAssertFalse(host.isShowing)
        XCTAssertNil(power.onChange, "power notifications stop too")
    }

    func testUpdatesOnlyWhenSnowChanges() throws {
        try module.start(with: settings(.light))
        var s = settings(.light)
        s.world = .cabin
        module.update(with: s)
        XCTAssertEqual(host.shown.count, 1)
        module.update(with: settings(.heavy))
        XCTAssertEqual(host.shown.count, 2)
    }

    func testIntensityOffHidesOverlayAndComesBack() throws {
        try module.start(with: settings(.light))
        module.update(with: settings(.off))
        XCTAssertFalse(host.isShowing)
        module.update(with: settings(.light))
        XCTAssertTrue(host.isShowing)
    }

    func testStartingWithIntensityOffShowsNothing() throws {
        try module.start(with: settings(.off))
        XCTAssertTrue(host.shown.isEmpty)
    }

    func testPowerChangesReconfigureRunningSnow() throws {
        try module.start(with: settings(.medium))
        power.condition = .battery
        power.onChange?()
        XCTAssertEqual(host.shown.last?.power, .battery)
        power.onChange?()
        XCTAssertEqual(host.shown.count, 2, "unchanged power is ignored")
    }

    func testNothingHappensAfterStop() throws {
        try module.start(with: settings(.medium))
        let staleCallback = power.onChange
        module.stop()
        module.stop()
        module.update(with: settings(.heavy))
        staleCallback?()
        XCTAssertFalse(host.isShowing)
        XCTAssertEqual(host.shown.count, 1)
        XCTAssertEqual(host.hides, 1)
    }

    func testRepeatedStartDoesNotSubscribeTwice() throws {
        try module.start(with: settings(.medium))
        try module.start(with: settings(.medium))
        XCTAssertEqual(power.starts, 1)
        XCTAssertEqual(host.shown.count, 1)
    }

    func testRapidToggling() throws {
        for _ in 0..<500 {
            try module.start(with: settings(.medium))
            module.stop()
        }
        XCTAssertFalse(host.isShowing)
        XCTAssertEqual(host.shown.count, host.hides)
    }
}
