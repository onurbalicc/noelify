import Foundation

/// The three parallax layers.
public enum SnowLayer: UInt8, CaseIterable, Sendable {
    case far, mid, near

    /// Base diameter in points, before the Snow Size setting.
    var diameter: ClosedRange<Float> {
        switch self {
        case .far: return 2.2...3.6
        case .mid: return 4.2...6.8
        case .near: return 8.5...14
        }
    }

    /// Fall speed in points per second.
    var fallSpeed: ClosedRange<Float> {
        switch self {
        case .far: return 24...40
        case .mid: return 46...72
        case .near: return 84...128
        }
    }

    /// Distant flakes fade into the air; the nearest ones are out of focus and translucent.
    var opacity: ClosedRange<Float> {
        switch self {
        case .far: return 0.38...0.62
        case .mid: return 0.66...0.92
        case .near: return 0.36...0.62
        }
    }

    /// Parallax: the same wind moves near flakes further across the screen.
    var windResponse: ClosedRange<Float> {
        switch self {
        case .far: return 0.4...0.55
        case .mid: return 0.75...1
        case .near: return 1.2...1.55
        }
    }

    var sway: ClosedRange<Float> {
        switch self {
        case .far: return 2...6
        case .mid: return 5...13
        case .near: return 9...20
        }
    }
}

/// Which small picture a flake is drawn with. The renderer generates these in code.
public enum SnowSprite: UInt8, CaseIterable, Sendable {
    case dot, clumpA, clumpB, clumpC
    case crystalA, crystalB, bokehA, bokehB
    case puffA, puffB, glow, glint
    case pixelDot, pixelBlock, pixelPlus, pixelFlake

    public var isPixelArt: Bool { rawValue >= SnowSprite.pixelDot.rawValue }

    /// Round sprites look the same at any angle, so the renderer can skip rotating them.
    public var rotates: Bool {
        switch self {
        case .clumpA, .clumpB, .clumpC, .crystalA, .crystalB, .bokehB: return true
        default: return false
        }
    }

    /// Side length of the pixel-art bitmap, in art pixels.
    public var pixelGridSize: Int {
        switch self {
        case .pixelBlock: return 2
        case .pixelPlus: return 3
        case .pixelFlake: return 5
        default: return 1
        }
    }
}

/// Subtle tint, used by the Magical style only.
public enum SnowTint: UInt8, Sendable {
    case white, ice, gold
}

public struct Snowflake: Sendable {
    public internal(set) var x: Float = 0
    public internal(set) var y: Float = 0
    /// Drawn diameter in points.
    public internal(set) var size: Float = 0
    public internal(set) var opacity: Float = 0
    public internal(set) var rotation: Float = 0
    public internal(set) var sprite: SnowSprite = .dot
    public internal(set) var tint: SnowTint = .white
    public internal(set) var layer: SnowLayer = .far

    var baseOpacity: Float = 0
    var fallSpeed: Float = 0
    var windResponse: Float = 0
    var sway: Float = 0
    var swayRate: Float = 0
    var swayPhase: Float = 0
    var spin: Float = 0
    var twinkleRate: Float = 0
    var twinkleDepth: Float = 0
    /// 0 = invisible, 1 = fully faded in. Starts negative to stagger arrivals.
    var presence: Float = 0
    var isLeaving = false
}

/// The snowfall simulation for one display. Coordinates are points, origin bottom-left.
///
/// The flake count is fixed for a given configuration: a flake that drifts off one edge
/// re-enters — with newly rolled properties — at the edge the snow is coming from. That
/// keeps the density even at any wind speed and allocates nothing while running.
public struct SnowField: Sendable {
    public private(set) var flakes: [Snowflake] = []
    /// Bumped whenever sprites, sizes or the number of flakes change in bulk.
    public private(set) var styleGeneration = 0
    public private(set) var width: Float
    public private(set) var height: Float
    public private(set) var configuration: SnowRenderConfiguration

    /// Edge length of one art pixel in the Pixel style, in points.
    public static let pixelUnit: Float = 3

    private var random: SnowRandom
    private let gustNoise: SmoothNoise
    private let squallNoise: SmoothNoise
    private var time: Double = 0
    private var gusts = [Float](repeating: 0, count: SnowField.gustBands + 1)
    /// Eased towards the chosen wind so changing the setting doesn't jerk the snow.
    private var windBase: Float
    private var windGust: Float
    private var fallScale: Float

    private static let gustBands = 12
    private static let margin: Float = 24

    public init(
        width: Double,
        height: Double,
        configuration: SnowRenderConfiguration,
        seed: UInt64 = UInt64.random(in: .min ... .max)
    ) {
        self.width = Float(max(width, 1))
        self.height = Float(max(height, 1))
        self.configuration = configuration
        random = SnowRandom(seed: seed)
        gustNoise = SmoothNoise(seed: SnowRandom.mix(seed &+ 1))
        squallNoise = SmoothNoise(seed: SnowRandom.mix(seed &+ 2))
        windBase = configuration.settings.wind.baseSpeed * configuration.settings.intensity.windScale
        windGust = configuration.settings.wind.gustSpeed * configuration.settings.intensity.windScale
        fallScale = configuration.settings.intensity.fallSpeedScale
        matchTargetCount()
    }

    /// How many flakes this display should have (leaving flakes not included).
    public var targetCount: Int {
        configuration.flakeCount(width: Double(width), height: Double(height))
    }

    // MARK: - Changes

    public mutating func apply(_ new: SnowRenderConfiguration) {
        guard new != configuration else { return }
        let restyle = new.settings.style != configuration.settings.style
            || new.settings.size != configuration.settings.size
        configuration = new
        if restyle {
            for i in flakes.indices {
                var f = flakes[i]
                rollAppearance(&f)
                f.presence = min(f.presence, random.value(in: -0.4...0))
                flakes[i] = f
            }
            styleGeneration += 1
        }
        matchTargetCount()
    }

    /// Adapts to a new display size, keeping flakes spread over the whole area.
    public mutating func resize(width newWidth: Double, height newHeight: Double) {
        let w = Float(max(newWidth, 1)), h = Float(max(newHeight, 1))
        guard w != width || h != height else { return }
        let sx = w / width, sy = h / height
        for i in flakes.indices {
            flakes[i].x *= sx
            flakes[i].y *= sy
        }
        width = w
        height = h
        matchTargetCount()
    }

    // MARK: - Simulation

    /// Advances the snowfall. Long gaps (sleep, paused rendering) are clamped so flakes never jump.
    public mutating func step(_ elapsed: Double) {
        guard elapsed > 0, elapsed.isFinite else { return }
        let dt = Float(min(elapsed, 0.1))
        time += Double(dt)
        easeWind(dt)
        updateGusts()

        let bandScale = Float(Self.gustBands) / width
        let t = Float(time.truncatingRemainder(dividingBy: 4096))
        var anyGone = false

        for i in flakes.indices {
            // Work on a copy of one flake: avoids repeated array uniqueness checks.
            var f = flakes[i]

            let phase = f.swayPhase + t * f.swayRate
            // Two unrelated frequencies: the path never visibly repeats.
            let drift = f.sway * (sin(phase) + 0.45 * sin(phase * 2.618 + f.swayPhase))
            let band = min(max(f.x * bandScale, 0), Float(Self.gustBands) - 0.001)
            let lower = Int(band)
            let gust = gusts[lower] + (gusts[lower + 1] - gusts[lower]) * (band - Float(lower))

            f.x += (gust * f.windResponse + drift) * dt
            f.y -= f.fallSpeed * fallScale * (1 + 0.14 * sin(phase * 0.73 + 1.3)) * dt
            f.rotation += f.spin * dt

            f.presence = f.isLeaving ? f.presence - dt * 1.6 : min(f.presence + dt * 0.9, 1)
            if f.isLeaving && f.presence <= 0 { anyGone = true }
            f.opacity = currentOpacity(f, time: t)

            let edge = Self.margin + f.size * 0.5
            if f.y < -edge {
                enterFromTop(&f)
            } else if f.x > width + edge {
                enterFromSide(&f, left: true)
            } else if f.x < -edge {
                enterFromSide(&f, left: false)
            }
            flakes[i] = f
        }
        if anyGone {
            flakes.removeAll { $0.isLeaving && $0.presence <= 0 }
            styleGeneration += 1
        }
    }

    // MARK: - Private

    private mutating func easeWind(_ dt: Float) {
        let intensity = configuration.settings.intensity
        let k = min(dt * 1.2, 1)
        windBase += (configuration.settings.wind.baseSpeed * intensity.windScale - windBase) * k
        windGust += (configuration.settings.wind.gustSpeed * intensity.windScale - windGust) * k
        fallScale += (intensity.fallSpeedScale - fallScale) * k
    }

    /// Wind at evenly spaced points across the display. Gusts travel along it.
    private mutating func updateGusts() {
        let squall = squallNoise.value(at: time * 0.045)
        for i in gusts.indices {
            let x = Double(i) / Double(Self.gustBands) * Double(width) / 620
            let gust = gustNoise.value(at: time * 0.22 - x)
            gusts[i] = windBase * (1 + 0.35 * squall) + windGust * (0.75 * gust + 0.25 * squall)
        }
    }

    private func currentOpacity(_ f: Snowflake, time: Float) -> Float {
        guard f.presence > 0 else { return 0 }
        var value = f.baseOpacity * f.presence
        if f.twinkleDepth > 0 {
            value *= 1 - f.twinkleDepth * (0.5 + 0.5 * sin(time * f.twinkleRate + f.swayPhase * 3))
        }
        return value
    }

    private mutating func matchTargetCount() {
        let target = targetCount
        var staying = 0
        // Flakes already on their way out come back before new ones are made.
        for i in flakes.indices {
            if staying < target {
                flakes[i].isLeaving = false
                staying += 1
            } else {
                flakes[i].isLeaving = true
            }
        }
        guard staying < target else { return }
        flakes.reserveCapacity(target)
        for _ in staying..<target {
            var f = Snowflake()
            f.layer = pickLayer()
            rollAppearance(&f)
            f.x = random.value(in: 0...width)
            f.y = random.value(in: 0...height)
            f.presence = -random.value(in: 0...1.8)
            flakes.append(f)
        }
        styleGeneration += 1
    }

    private mutating func pickLayer() -> SnowLayer {
        let roll = random.unit()
        if roll < 0.5 { return .far }
        return roll < 0.86 ? .mid : .near
    }

    private mutating func enterFromTop(_ f: inout Snowflake) {
        rollMotion(&f)
        f.x = random.value(in: 0...width)
        f.y = height + Self.margin + f.size * 0.5
    }

    private mutating func enterFromSide(_ f: inout Snowflake, left: Bool) {
        rollMotion(&f)
        let edge = Self.margin + f.size * 0.5
        f.x = left ? -edge : width + edge
        f.y = random.value(in: 0...(height + Self.margin))
    }

    /// How a flake moves. Re-rolled on every pass so no flake repeats its path.
    private mutating func rollMotion(_ f: inout Snowflake) {
        let layer = f.layer
        f.windResponse = random.value(in: layer.windResponse)
        f.sway = random.value(in: layer.sway)
        f.swayRate = random.value(in: 0.35...1.1)
        f.swayPhase = random.value(in: 0...(2 * .pi))
        f.spin = random.value(in: -0.7...0.7)
        f.fallSpeed = random.value(in: layer.fallSpeed)
        switch configuration.settings.style {
        case .realistic:
            break
        case .soft:
            f.fallSpeed *= 0.72
            f.sway *= 1.3
            f.swayRate *= 0.75
        case .magical:
            f.fallSpeed *= 0.62
            f.sway *= 1.55
            f.swayRate *= 0.8
        case .pixel:
            f.sway *= 0.6
        }
    }

    private mutating func rollAppearance(_ f: inout Snowflake) {
        rollMotion(&f)
        let layer = f.layer
        f.size = random.value(in: layer.diameter) * random.value(in: configuration.settings.size.scaleRange)
        f.baseOpacity = random.value(in: layer.opacity)
        f.rotation = random.value(in: 0...(2 * .pi))
        f.tint = .white
        f.twinkleDepth = 0
        f.twinkleRate = 0

        switch configuration.settings.style {
        case .realistic:
            switch layer {
            case .far:
                f.sprite = .dot
            case .mid:
                let roll = random.unit()
                f.sprite = roll < 0.3 ? .clumpA : roll < 0.55 ? .clumpB : roll < 0.78 ? .clumpC : .dot
            case .near:
                f.sprite = random.chance(0.55) ? .bokehA : .bokehB
            }
        case .soft:
            f.sprite = random.chance(0.5) ? .puffA : .puffB
            f.size *= 1.45
            f.baseOpacity *= 0.82
        case .magical:
            rollMagical(&f)
        case .pixel:
            rollPixel(&f)
        }
    }

    private mutating func rollMagical(_ f: inout Snowflake) {
        let roll = random.unit()
        f.tint = roll < 0.16 ? .gold : roll < 0.5 ? .ice : .white
        f.twinkleRate = random.value(in: 0.8...2.2)
        switch f.layer {
        case .far:
            f.sprite = random.chance(0.14) ? .glint : .glow
            f.size *= 2.1
            f.twinkleDepth = 0.6
        case .mid:
            let isCrystal = random.chance(0.6)
            f.sprite = isCrystal ? (random.chance(0.5) ? .crystalA : .crystalB) : .glow
            f.size *= 1.8
            f.twinkleDepth = 0.3
        case .near:
            f.sprite = random.chance(0.5) ? .crystalA : .crystalB
            f.size *= 1.25
            f.baseOpacity = min(f.baseOpacity * 1.1, 0.65)
            f.twinkleDepth = 0.2
        }
    }

    /// Pixel flakes are whole art pixels: the size setting picks bigger bitmaps and pixels.
    private mutating func rollPixel(_ f: inout Snowflake) {
        switch f.layer {
        case .far:
            f.sprite = .pixelDot
            f.baseOpacity = 0.55
        case .mid:
            f.sprite = random.chance(0.6) ? .pixelBlock : .pixelPlus
            f.baseOpacity = 0.8
        case .near:
            f.sprite = random.chance(0.75) ? .pixelFlake : .pixelPlus
            f.baseOpacity = 0.92
        }
        let pixels: Float
        switch configuration.settings.size {
        case .small: pixels = 2
        case .mixed: pixels = f.layer != .near && random.chance(0.25) ? 4 : 3
        case .large: pixels = 5
        }
        f.size = Float(f.sprite.pixelGridSize) * pixels
        f.rotation = 0
        f.spin = 0
    }
}
