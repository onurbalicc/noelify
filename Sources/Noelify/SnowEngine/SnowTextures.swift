#if os(macOS)
import AppKit
import SpriteKit
import NoelifyCore

/// Snowflake textures, drawn in code into one small atlas (256 × 256 px, or 32 × 8 px for
/// pixel art). Sharing one atlas lets SpriteKit draw all snow in a single batch.
///
/// Flakes carry a faint cool shade around their edge. It is invisible on dark windows
/// and is what keeps white snow readable over white ones.
@MainActor
final class SnowTextures {
    struct Entry {
        let texture: SKTexture
        /// Node size relative to the flake's visible diameter (the rest is soft edge).
        let nodeScale: CGFloat
    }

    let isPixelArt: Bool
    private var entries: [SnowSprite: Entry] = [:]

    init(pixelArt: Bool) {
        isPixelArt = pixelArt
        entries = pixelArt ? Self.makePixelEntries() : Self.makeSmoothEntries()
    }

    subscript(sprite: SnowSprite) -> Entry? { entries[sprite] }

    // MARK: - Smooth atlas

    private static let cell = 64
    private static let columns = 4
    private static let shade: [CGFloat] = [0.20, 0.29, 0.44]

    private static func makeSmoothEntries() -> [SnowSprite: Entry] {
        let sprites = SnowSprite.allCases.filter { !$0.isPixelArt }
        let side = cell * columns
        guard let context = makeContext(width: side, height: side) else { return [:] }

        for (index, sprite) in sprites.enumerated() {
            context.saveGState()
            context.translateBy(x: (CGFloat(index % columns) + 0.5) * CGFloat(cell),
                                y: (CGFloat(index / columns) + 0.5) * CGFloat(cell))
            draw(sprite, in: context)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { return [:] }
        let atlas = SKTexture(cgImage: image)
        atlas.usesMipmaps = true

        var result: [SnowSprite: Entry] = [:]
        let unit = 1 / CGFloat(columns)
        for (index, sprite) in sprites.enumerated() {
            let rect = CGRect(x: CGFloat(index % columns) * unit, y: CGFloat(index / columns) * unit,
                              width: unit, height: unit)
            let texture = SKTexture(rect: rect, in: atlas)
            texture.filteringMode = .linear
            result[sprite] = Entry(texture: texture, nodeScale: nodeScale(sprite))
        }
        return result
    }

    private static func nodeScale(_ sprite: SnowSprite) -> CGFloat {
        switch sprite {
        case .glow, .glint: return 1.5
        case .puffA, .puffB: return 1.5
        default: return 1.35
        }
    }

    /// Draws one sprite centred on the origin, inside a ±30 px square.
    private static func draw(_ sprite: SnowSprite, in c: CGContext) {
        switch sprite {
        case .dot:
            shadeDisc(c, radius: 30, strength: 0.30)
            disc(c, radius: 23, stops: [(0, 1), (0.45, 0.96), (0.75, 0.5), (1, 0)])
        case .clumpA: clump(c, seed: 11, lobes: 5)
        case .clumpB: clump(c, seed: 29, lobes: 6)
        case .clumpC: clump(c, seed: 47, lobes: 4)
        case .crystalA:
            crystal(c, branches: [(0.42, 0.30), (0.70, 0.20)], width: 3.4)
        case .crystalB:
            crystal(c, branches: [(0.55, 0.34)], width: 4.0)
        case .bokehA:
            shadeDisc(c, radius: 30, strength: 0.20)
            disc(c, radius: 26, stops: [(0, 0.82), (0.5, 0.78), (0.76, 0.52), (1, 0)])
        case .bokehB:
            shadeDisc(c, radius: 30, strength: 0.16)
            var rng = SplitMix64(seed: 83)
            for _ in 0..<4 {
                c.saveGState()
                c.translateBy(x: rng.offset(7), y: rng.offset(7))
                disc(c, radius: 17 + abs(rng.offset(3)), stops: [(0, 0.5), (0.6, 0.38), (1, 0)])
                c.restoreGState()
            }
        case .puffA:
            shadeDisc(c, radius: 30, strength: 0.16)
            disc(c, radius: 29, stops: [(0, 0.95), (0.25, 0.8), (0.5, 0.42), (0.75, 0.13), (1, 0)])
        case .puffB:
            shadeDisc(c, radius: 30, strength: 0.14)
            c.saveGState()
            c.scaleBy(x: 1, y: 0.84)
            disc(c, radius: 29, stops: [(0, 0.82), (0.4, 0.6), (0.7, 0.2), (1, 0)])
            c.restoreGState()
        case .glow:
            shadeDisc(c, radius: 28, strength: 0.14)
            disc(c, radius: 29, stops: [(0, 0.5), (0.35, 0.24), (0.7, 0.07), (1, 0)])
            disc(c, radius: 10, stops: [(0, 1), (0.5, 0.9), (1, 0)])
        case .glint:
            disc(c, radius: 20, stops: [(0, 0.45), (0.5, 0.12), (1, 0)])
            for angle in [CGFloat(0), .pi / 2] {
                c.saveGState()
                c.rotate(by: angle)
                c.scaleBy(x: 1, y: 0.10)
                disc(c, radius: 29, stops: [(0, 1), (0.3, 0.7), (1, 0)])
                c.restoreGState()
            }
        case .pixelDot, .pixelBlock, .pixelPlus, .pixelFlake:
            break
        }
    }

    private static let core: [CGFloat] = [0.97, 0.985, 1]
    private static let rim: [CGFloat] = [0.76, 0.85, 0.96]

    /// A soft disc. Snow cools from white towards its edge unless a flat colour is given.
    private static func disc(_ c: CGContext, radius: CGFloat, stops: [(CGFloat, CGFloat)],
                             color: [CGFloat]? = nil) {
        let components = stops.flatMap { stop -> [CGFloat] in
            let rgb = color ?? zip(core, rim).map { $0 + ($1 - $0) * stop.0 }
            return rgb + [stop.1]
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorSpace: space, colorComponents: components,
                                        locations: stops.map { $0.0 }, count: stops.count) else { return }
        c.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                             endCenter: .zero, endRadius: radius, options: [])
    }

    private static func shadeDisc(_ c: CGContext, radius: CGFloat, strength: CGFloat) {
        disc(c, radius: radius, stops: [(0, strength), (0.5, strength * 0.8), (0.75, strength * 0.3), (1, 0)], color: shade)
    }

    /// An irregular cluster of soft lobes — how real falling snow looks at mid distance.
    private static func clump(_ c: CGContext, seed: UInt64, lobes: Int) {
        shadeDisc(c, radius: 30, strength: 0.26)
        var rng = SplitMix64(seed: seed)
        disc(c, radius: 18, stops: [(0, 0.95), (0.55, 0.7), (1, 0)])
        for i in 0..<lobes {
            let angle = (CGFloat(i) + rng.offset(0.35)) / CGFloat(lobes) * 2 * .pi
            let distance = 8.5 + rng.offset(2.5)
            c.saveGState()
            c.translateBy(x: cos(angle) * distance, y: sin(angle) * distance)
            disc(c, radius: 13 + rng.offset(2.5), stops: [(0, 0.8), (0.5, 0.5), (1, 0)])
            c.restoreGState()
        }
    }

    private static func crystal(_ c: CGContext, branches: [(at: CGFloat, length: CGFloat)], width: CGFloat) {
        // A wider shade pass underneath follows the shape of the crystal.
        strokeCrystal(c, branches: branches, width: width + 3.5,
                      color: CGColor(srgbRed: shade[0], green: shade[1], blue: shade[2], alpha: 0.18))
        strokeCrystal(c, branches: branches, width: width,
                      color: CGColor(srgbRed: core[0], green: core[1], blue: core[2], alpha: 1))
        disc(c, radius: 7, stops: [(0, 1), (0.6, 0.8), (1, 0)])
    }

    private static func strokeCrystal(_ c: CGContext, branches: [(at: CGFloat, length: CGFloat)],
                                      width: CGFloat, color: CGColor) {
        let arm: CGFloat = 25
        let path = CGMutablePath()
        for i in 0..<6 {
            let turn = CGAffineTransform(rotationAngle: CGFloat(i) * .pi / 3)
            path.move(to: .zero, transform: turn)
            path.addLine(to: CGPoint(x: 0, y: arm), transform: turn)
            for branch in branches {
                let start = CGPoint(x: 0, y: arm * branch.at)
                for side in [CGFloat(-1), 1] {
                    path.move(to: start, transform: turn)
                    path.addLine(to: CGPoint(x: side * sin(.pi / 3) * arm * branch.length,
                                             y: start.y + cos(.pi / 3) * arm * branch.length), transform: turn)
                }
            }
        }
        c.setLineCap(.round)
        c.setLineWidth(width)
        c.setStrokeColor(color)
        c.addPath(path)
        c.strokePath()
    }

    // MARK: - Pixel atlas

    private static let pixelArt: [(SnowSprite, [String])] = [
        (.pixelDot, ["#"]),
        (.pixelBlock, ["##", "#+"]),
        (.pixelPlus, [".+.", "+#+", ".+."]),
        (.pixelFlake, ["#.#.#", ".+#+.", "##+##", ".+#+.", "#.#.#"]),
    ]

    private static func makePixelEntries() -> [SnowSprite: Entry] {
        let cell = 8, width = cell * 4
        guard let context = makeContext(width: width, height: cell) else { return [:] }
        for (index, art) in pixelArt.enumerated() {
            let lines = art.1
            func isFilled(_ x: Int, _ y: Int) -> Bool {
                lines.indices.contains(y) && (0..<lines.count).contains(x) && Array(lines[y])[x] != "."
            }
            // One art pixel of outline on every side: keeps flakes visible over white.
            for y in -1...lines.count {
                for x in -1...lines.count {
                    let color: CGColor
                    if isFilled(x, y) {
                        color = Array(lines[y])[x] == "#"
                            ? CGColor(srgbRed: 0.97, green: 0.985, blue: 1, alpha: 1)
                            : CGColor(srgbRed: 0.80, green: 0.89, blue: 0.99, alpha: 1)
                    } else if isFilled(x - 1, y) || isFilled(x + 1, y) || isFilled(x, y - 1) || isFilled(x, y + 1) {
                        color = CGColor(srgbRed: shade[0], green: shade[1], blue: shade[2], alpha: 0.16)
                    } else {
                        continue
                    }
                    context.setFillColor(color)
                    context.fill(CGRect(x: index * cell + x + 1, y: y + 1, width: 1, height: 1))
                }
            }
        }
        guard let image = context.makeImage() else { return [:] }
        let atlas = SKTexture(cgImage: image)
        atlas.filteringMode = .nearest
        var result: [SnowSprite: Entry] = [:]
        for (index, art) in pixelArt.enumerated() {
            let side = CGFloat(art.1.count + 2)
            let rect = CGRect(x: CGFloat(index) / 4, y: 0, width: side / CGFloat(width), height: side / CGFloat(cell))
            let texture = SKTexture(rect: rect, in: atlas)
            texture.filteringMode = .nearest
            result[art.0] = Entry(texture: texture, nodeScale: side / CGFloat(art.1.count))
        }
        return result
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

private extension SplitMix64 {
    /// Uniform in -range...range.
    mutating func offset(_ range: CGFloat) -> CGFloat {
        (CGFloat(next() % 10_000) / 5_000 - 1) * range
    }
}
#endif
