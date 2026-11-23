import Foundation

/// A visual or audio effect that runs while Christmas Mode is on
/// (snow, lights, window snow, decorations, ambience...).
///
/// Modules must release all windows, timers and audio in `stop()`.
public protocol EffectModule: AnyObject {
    var name: String { get }
    func start(with settings: NoelifySettings) throws
    func update(with settings: NoelifySettings)
    func stop()
}

/// Supplies the wallpaper file for a world, or `nil` if none is installed.
public protocol WallpaperProvider: AnyObject {
    func wallpaperURL(for world: ChristmasWorld) -> URL?
}

/// What the user should be told after turning Christmas Mode on or changing settings.
public struct ActivationReport: Equatable, Sendable {
    public enum WallpaperResult: Equatable, Sendable {
        case notRequested
        case applied(WallpaperApplyReport)
        case unavailable(ChristmasWorld)
        case failed(String)
    }

    public var wallpaper: WallpaperResult = .notRequested
    public var moduleFailures: [String: String] = [:]
}

/// Turns Christmas Mode on and off and keeps running effects in sync with settings.
///
/// Call from the main thread only.
public final class ChristmasModeCoordinator {
    public private(set) var isActive = false

    private let wallpaperManager: WallpaperManager
    private let wallpaperProvider: WallpaperProvider
    private let modules: [EffectModule]
    private var runningModules: [EffectModule] = []
    private var settings: NoelifySettings

    public init(
        wallpaperManager: WallpaperManager,
        wallpaperProvider: WallpaperProvider,
        modules: [EffectModule],
        settings: NoelifySettings
    ) {
        self.wallpaperManager = wallpaperManager
        self.wallpaperProvider = wallpaperProvider
        self.modules = modules
        self.settings = settings
    }

    public var hasWallpaperBackup: Bool { wallpaperManager.hasBackup }

    @discardableResult
    public func activate() -> ActivationReport {
        var report = ActivationReport()
        guard !isActive else { return report }
        isActive = true

        report.wallpaper = applyWallpaperIfWanted()

        for module in modules {
            do {
                try module.start(with: settings)
                runningModules.append(module)
            } catch {
                report.moduleFailures[module.name] = String(describing: error)
            }
        }
        return report
    }

    /// Stops all effects and restores the original wallpaper.
    @discardableResult
    public func deactivate() -> WallpaperRestoreReport {
        // Stop effects even if we think we're inactive: deactivation must always be safe.
        for module in runningModules.reversed() { module.stop() }
        runningModules.removeAll()
        isActive = false
        return wallpaperManager.restore()
    }

    /// Applies new settings. Returns a report when the wallpaper was affected.
    @discardableResult
    public func update(settings newSettings: NoelifySettings) -> (activation: ActivationReport?, restore: WallpaperRestoreReport?) {
        let old = settings
        settings = newSettings
        guard isActive else { return (nil, nil) }

        for module in runningModules { module.update(with: newSettings) }

        if old.changesWallpaper && !newSettings.changesWallpaper {
            return (nil, wallpaperManager.restore())
        }
        let wallpaperInputsChanged = old.world != newSettings.world
            || old.changesWallpaper != newSettings.changesWallpaper
            || old.hasConsentedToWallpaperChange != newSettings.hasConsentedToWallpaperChange
        if newSettings.changesWallpaper && wallpaperInputsChanged {
            var report = ActivationReport()
            report.wallpaper = applyWallpaperIfWanted()
            return (report, nil)
        }
        return (nil, nil)
    }

    /// Re-applies the wallpaper, e.g. after a display is connected.
    @discardableResult
    public func refreshWallpaper() -> ActivationReport.WallpaperResult {
        guard isActive else { return .notRequested }
        return applyWallpaperIfWanted()
    }

    // MARK: - Private

    private func applyWallpaperIfWanted() -> ActivationReport.WallpaperResult {
        guard settings.changesWallpaper, settings.hasConsentedToWallpaperChange else { return .notRequested }
        guard let url = wallpaperProvider.wallpaperURL(for: settings.world) else {
            return .unavailable(settings.world)
        }
        do {
            return .applied(try wallpaperManager.apply(imageURL: url))
        } catch {
            return .failed(String(describing: error))
        }
    }
}
