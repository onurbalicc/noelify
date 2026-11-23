#if os(macOS)
import SpriteKit
import NoelifyCore

/// Draws one display's `SnowField`. Holds one sprite per flake and reuses them throughout.
@MainActor
final class SnowScene: SKScene {
    private(set) var field: SnowField
    /// Frames simulated since the scene was created (used by diagnostics).
    private(set) var frameCount = 0

    /// Called after each frame's update while set (only during warm-up).
    var onFrame: (() -> Void)?

    private var sprites: [SKSpriteNode] = []
    private var textures: SnowTextures
    private var boundGeneration = -1
    private var lastTime: TimeInterval?

    init(size: CGSize, configuration: SnowRenderConfiguration) {
        field = SnowField(width: size.width, height: size.height, configuration: configuration)
        textures = SnowTextures(pixelArt: configuration.settings.style == .pixel)
        super.init(size: size)
        scaleMode = .fill
        backgroundColor = .clear
        bindSprites()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("SnowScene is created in code only") }

    func apply(_ configuration: SnowRenderConfiguration) {
        let needsPixelArt = configuration.settings.style == .pixel
        field.apply(configuration)
        if needsPixelArt != textures.isPixelArt {
            textures = SnowTextures(pixelArt: needsPixelArt)
            boundGeneration = -1
        }
        bindSprites()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 1, size.height > 1 else { return }
        field.resize(width: size.width, height: size.height)
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        frameCount += 1
        field.step(elapsed)
        bindSprites()
        place()
        onFrame?()
    }

    // MARK: - Private

    /// Matches sprites to flakes after the flakes were added, removed or restyled.
    private func bindSprites() {
        guard boundGeneration != field.styleGeneration else { return }
        boundGeneration = field.styleGeneration

        let flakes = field.flakes
        while sprites.count > flakes.count { sprites.removeLast().removeFromParent() }
        while sprites.count < flakes.count {
            let sprite = SKSpriteNode()
            sprite.alpha = 0
            sprites.append(sprite)
            addChild(sprite)
        }
        for (flake, sprite) in zip(flakes, sprites) {
            guard let entry = textures[flake.sprite] else { continue }
            if sprite.texture !== entry.texture { sprite.texture = entry.texture }
            let side = CGFloat(flake.size) * entry.nodeScale
            sprite.size = CGSize(width: side, height: side)
            sprite.zRotation = CGFloat(flake.rotation)
            switch flake.tint {
            case .white:
                sprite.colorBlendFactor = 0
            case .ice:
                sprite.color = NSColor(srgbRed: 0.72, green: 0.87, blue: 1, alpha: 1)
                sprite.colorBlendFactor = 0.75
            case .gold:
                sprite.color = NSColor(srgbRed: 1, green: 0.88, blue: 0.66, alpha: 1)
                sprite.colorBlendFactor = 0.75
            }
        }
    }

    private func place() {
        let flakes = field.flakes
        if textures.isPixelArt {
            let unit = SnowField.pixelUnit
            for i in 0..<min(flakes.count, sprites.count) {
                let flake = flakes[i], sprite = sprites[i]
                sprite.position = CGPoint(x: CGFloat((flake.x / unit).rounded() * unit),
                                          y: CGFloat((flake.y / unit).rounded() * unit))
                setAlpha(sprite, flake.opacity)
            }
        } else {
            for i in 0..<min(flakes.count, sprites.count) {
                let flake = flakes[i], sprite = sprites[i]
                sprite.position = CGPoint(x: CGFloat(flake.x), y: CGFloat(flake.y))
                if flake.sprite.rotates { sprite.zRotation = CGFloat(flake.rotation) }
                setAlpha(sprite, flake.opacity)
            }
        }
    }

    private func setAlpha(_ sprite: SKSpriteNode, _ opacity: Float) {
        let alpha = CGFloat(opacity)
        if abs(sprite.alpha - alpha) > 0.004 { sprite.alpha = alpha }
    }
}
#endif
