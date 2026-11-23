#if os(macOS)
import AppKit
import SpriteKit
import NoelifyCore

/// A transparent panel that covers one display, lets every click through and can never
/// take keyboard focus.
@MainActor
final class SnowPanel: NSPanel {
    init(screenFrame: NSRect) {
        super.init(contentRect: screenFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        // Above app windows; below the Dock, the menu bar, menus and the Control Center.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would otherwise push the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Shows an `SKView` enlarged to fill this view, so SpriteKit can draw at a reduced
/// resolution while the scene keeps working in full-size points.
@MainActor
private final class SnowContainerView: NSView {
    let snowView: SKView
    var renderScale: CGFloat { didSet { needsLayout = true } }
    var usesNearest = false { didSet { needsLayout = true } }

    init(frame: NSRect, snowView: SKView, renderScale: CGFloat) {
        self.snowView = snowView
        self.renderScale = renderScale
        super.init(frame: frame)
        wantsLayer = true
        addSubview(snowView)
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SnowContainerView is created in code only") }

    override func layout() {
        super.layout()
        snowView.frame = CGRect(x: 0, y: 0, width: bounds.width * renderScale, height: bounds.height * renderScale)
        guard let layer else { return }
        // Core Animation scales around the layer's anchor point (AppKit uses a corner);
        // the translation makes it scale around the origin wherever the anchor is.
        let grow = 1 / renderScale
        var transform = CATransform3DMakeTranslation(layer.anchorPoint.x * bounds.width * (grow - 1),
                                                     layer.anchorPoint.y * bounds.height * (grow - 1), 0)
        transform = CATransform3DScale(transform, grow, grow, 1)
        layer.sublayerTransform = transform
        snowView.layer?.magnificationFilter = usesNearest ? .nearest : .linear
    }
}

/// The snow on one display: panel, SpriteKit view and scene, created and released together.
@MainActor
final class SnowOverlayWindow {
    let panel: SnowPanel
    private let view: SKView
    private let container: SnowContainerView
    private let scene: SnowScene
    private var occlusionObserver: NSObjectProtocol?
    private var isSuspended = false
    private static let warmUpFrames = 4
    private var framesUntilReveal = SnowOverlayWindow.warmUpFrames

    /// The snow is fully shown (not still warming up).
    var isRevealed: Bool { container.alphaValue == 1 }
    var frameCount: Int { scene.frameCount }
    var flakeCount: Int { scene.field.flakes.count }
    var isRendering: Bool { !view.isPaused }
    var stateDescription: String {
        "paused \(view.isPaused), suspended \(isSuspended), visible \(panel.occlusionState.contains(.visible)), scene paused \(scene.isPaused)"
    }
    /// Where the snow ends up inside the panel, as Core Animation sees it.
    var drawnRect: CGRect {
        guard let snow = view.layer, let root = container.layer else { return .null }
        return snow.convert(snow.bounds, to: root)
    }
    /// Frame buffer size in pixels.
    var drawableSize: CGSize { (view.layer as? CAMetalLayer)?.drawableSize ?? .zero }
    /// For diagnostics: the scene exactly as SpriteKit draws it.
    func snapshot() -> CGImage? { view.texture(from: scene)?.cgImage() }

    init(screen: NSScreen, configuration: SnowRenderConfiguration) {
        panel = SnowPanel(screenFrame: screen.frame)
        view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = false
        container = SnowContainerView(frame: view.frame, snowView: view,
                                      renderScale: configuration.renderScale)
        container.usesNearest = configuration.settings.style == .pixel
        view.preferredFramesPerSecond = configuration.framesPerSecond
        scene = SnowScene(size: screen.frame.size, configuration: configuration)
        panel.contentView = container
        // Nothing SpriteKit draws while it warms up may reach the screen.
        container.alphaValue = 0
        scene.onFrame = { [weak self] in self?.revealWhenReady() }

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePaused() }
        }
        // The panel isn't reported visible until the window server has seen it, so start
        // unpaused and let occlusion changes pause rendering from here on.
        panel.orderFrontRegardless()
        // Presented last so SpriteKit ties its display link to the display the panel is on.
        view.presentScene(scene)
    }

    func apply(_ configuration: SnowRenderConfiguration) {
        view.preferredFramesPerSecond = configuration.framesPerSecond
        if container.renderScale != configuration.renderScale { hideUntilReady() }
        container.renderScale = configuration.renderScale
        container.usesNearest = configuration.settings.style == .pixel
        scene.apply(configuration)
    }

    func move(to screen: NSScreen) {
        guard panel.frame != screen.frame else { return }
        hideUntilReady()
        panel.setFrame(screen.frame, display: true)
        scene.size = screen.frame.size
    }

    /// Stops rendering while the display is asleep or another user is on screen.
    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        updatePaused()
    }

    func close() {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        scene.onFrame = nil
        // Off screen first: a view losing its scene may draw one opaque frame.
        container.alphaValue = 0
        panel.orderOut(nil)
        view.isPaused = true
        scene.removeAllChildren()
        view.presentScene(nil)
        panel.contentView = nil
        panel.close()
    }

    private func hideUntilReady() {
        container.alphaValue = 0
        framesUntilReveal = Self.warmUpFrames
        scene.onFrame = { [weak self] in self?.revealWhenReady() }
    }

    /// Fades the snow in once a few complete frames have been drawn.
    private func revealWhenReady() {
        framesUntilReveal -= 1
        guard framesUntilReveal <= 0 else { return }
        scene.onFrame = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            container.animator().alphaValue = 1
        }
    }

    /// Re-reads the current state, in case a change arrived without a notification.
    func updatePaused() {
        let paused = isSuspended || !panel.occlusionState.contains(.visible)
        if view.isPaused != paused { view.isPaused = paused }
    }
}
#endif
