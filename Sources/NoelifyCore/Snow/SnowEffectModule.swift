import Foundation

/// Puts snow on screen. Implemented with AppKit + SpriteKit in the app target.
public protocol SnowOverlayHost: AnyObject {
    /// Shows the snow, or updates what is already showing. Must never create a second
    /// overlay for a display that already has one.
    func show(_ configuration: SnowRenderConfiguration)
    /// Stops rendering and releases every window, view and texture.
    func hide()
}

/// Reports whether the Mac is plugged in, on battery, or short on power.
public protocol PowerMonitor: AnyObject {
    var condition: PowerCondition { get }
    /// Begins delivering changes on the main thread.
    func start(onChange: @escaping () -> Void)
    func stop()
}

/// The Living Snow Engine as a Christmas Mode effect.
public final class SnowEffectModule: EffectModule {
    public let name = "Snow"

    private let host: SnowOverlayHost
    private let power: PowerMonitor
    private var settings: SnowSettings?
    private var shown: SnowRenderConfiguration?

    public init(host: SnowOverlayHost, power: PowerMonitor) {
        self.host = host
        self.power = power
    }

    public func start(with settings: NoelifySettings) throws {
        let wasRunning = self.settings != nil
        self.settings = settings.snow
        if !wasRunning {
            power.start { [weak self] in self?.refresh() }
        }
        refresh()
    }

    public func update(with settings: NoelifySettings) {
        guard self.settings != nil else { return }
        self.settings = settings.snow
        refresh()
    }

    public func stop() {
        guard settings != nil else { return }
        settings = nil
        shown = nil
        power.stop()
        host.hide()
    }

    private func refresh() {
        guard let settings else { return }
        guard settings.intensity != .off else {
            // "Off" means nothing on screen at all, not an empty overlay that still renders.
            if shown != nil {
                shown = nil
                host.hide()
            }
            return
        }
        let configuration = SnowRenderConfiguration(settings: settings, power: power.condition)
        guard configuration != shown else { return }
        shown = configuration
        host.show(configuration)
    }
}
