#if os(macOS)
import AppKit
import Combine
import NoelifyCore

/// A message shown at the top of the Control Center.
struct Banner: Equatable, Identifiable {
    enum Kind: Equatable { case info, success, warning, error, recovery }
    let id = UUID()
    var kind: Kind
    var title: String
    var message: String

    static func == (lhs: Banner, rhs: Banner) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.message == rhs.message
    }
}

/// UI-facing state for Noelify. All mutations happen on the main actor.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var settings: NoelifySettings
    @Published private(set) var isActive = false
    @Published private(set) var hasWallpaperBackup = false
    @Published var banner: Banner?
    /// Shown inline when the user turns on Christmas Mode before agreeing to wallpaper changes.
    @Published private(set) var isAskingWallpaperConsent = false

    private let settingsStore: SettingsStore
    private let provider: BundledWallpaperProvider
    private let snowHost: MacSnowOverlayHost
    private let coordinator: ChristmasModeCoordinator
    private var screenChangeWork: DispatchWorkItem?

    private init() {
        settingsStore = SettingsStore(store: UserDefaultsStore(defaults: Diagnostics.settingsDefaults ?? .standard))
        let loaded = settingsStore.load()
        settings = loaded

        provider = BundledWallpaperProvider(installDirectory: AppPaths.wallpapers)
        let manager = WallpaperManager(
            backend: MacWallpaperBackend(),
            store: WallpaperBackupStore(fileURL: AppPaths.wallpaperBackup),
            ownedDirectory: AppPaths.wallpapers
        )
        snowHost = MacSnowOverlayHost()
        let snow = SnowEffectModule(host: snowHost, power: Diagnostics.powerOverride ?? MacPowerMonitor())
        coordinator = ChristmasModeCoordinator(
            wallpaperManager: manager,
            wallpaperProvider: provider,
            modules: [snow], // Window snow, lights and decorations join here in later phases.
            settings: loaded
        )

        // Christmas Mode always starts OFF. A leftover backup means the last session ended
        // (crash, force quit, power loss) without restoring the user's wallpaper.
        hasWallpaperBackup = coordinator.hasWallpaperBackup
        if hasWallpaperBackup {
            banner = Banner(
                kind: .recovery,
                title: "Restore your wallpaper?",
                message: "Noelify didn't close normally last time, so your original wallpaper may still be replaced."
            )
        }
    }

    // MARK: - Derived state

    var usesPreviewArt: Bool { provider.usesPreviewArt(for: settings.world) }

    /// The overlays currently on screen (read by diagnostics).
    var snowOverlays: [SnowOverlayWindow] { Array(snowHost.controller.overlays.values) }

    // MARK: - Christmas Mode

    func setChristmasMode(_ on: Bool) {
        if on {
            guard !isActive else { return }
            if settings.changesWallpaper && !settings.hasConsentedToWallpaperChange {
                isAskingWallpaperConsent = true
                return
            }
            activate()
        } else {
            isAskingWallpaperConsent = false
            guard isActive || coordinator.hasWallpaperBackup else { return }
            let report = coordinator.deactivate()
            isActive = false
            present(report)
        }
    }

    /// The user agreed that Noelify may change (and later restore) the wallpaper.
    func grantWallpaperConsent() {
        isAskingWallpaperConsent = false
        mutateSettings { $0.hasConsentedToWallpaperChange = true; $0.changesWallpaper = true }
        activate()
    }

    /// The user wants Christmas Mode without touching the wallpaper.
    func activateWithoutWallpaper() {
        isAskingWallpaperConsent = false
        mutateSettings { $0.changesWallpaper = false }
        activate()
    }

    func cancelConsent() {
        isAskingWallpaperConsent = false
    }

    // MARK: - Settings

    func selectWorld(_ world: ChristmasWorld) {
        mutateSettings { $0.world = world }
    }

    func setChangesWallpaper(_ enabled: Bool) {
        if enabled && !settings.hasConsentedToWallpaperChange && isActive {
            isAskingWallpaperConsent = true
            return
        }
        mutateSettings { $0.changesWallpaper = enabled }
    }

    func setSnow<Value>(_ keyPath: WritableKeyPath<SnowSettings, Value>, to value: Value) {
        mutateSettings { $0.snow[keyPath: keyPath] = value }
    }

    // MARK: - Recovery

    /// Restores the backed-up wallpaper (used from the recovery banner and the Restore button).
    func restoreOriginalWallpaper() {
        let report = coordinator.deactivate()
        isActive = false
        present(report)
    }

    func dismissBanner() {
        banner = nil
    }

    // MARK: - System events

    func screensDidChange() {
        // Displays often fire several changes in a row; settle before reapplying.
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.present(self.coordinator.refreshWallpaper(), quietOnSuccess: true)
                self.hasWallpaperBackup = self.coordinator.hasWallpaperBackup
            }
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func prepareForTermination() {
        screenChangeWork?.cancel()
        if isActive || coordinator.hasWallpaperBackup {
            let report = coordinator.deactivate()
            if !report.isComplete && !report.nothingToRestore {
                NSLog("Noelify: wallpaper restore at quit was incomplete: \(report.summary)")
            }
        }
    }

    // MARK: - Private

    private func activate() {
        let report = coordinator.activate()
        isActive = coordinator.isActive
        present(report.wallpaper, quietOnSuccess: false)
        if !report.moduleFailures.isEmpty {
            let names = report.moduleFailures.keys.sorted().joined(separator: ", ")
            banner = Banner(kind: .warning, title: "Some effects couldn't start", message: names)
        }
        hasWallpaperBackup = coordinator.hasWallpaperBackup
    }

    private func mutateSettings(_ change: (inout NoelifySettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        settingsStore.save(updated)

        let result = coordinator.update(settings: updated)
        if let activation = result.activation { present(activation.wallpaper, quietOnSuccess: true) }
        if let restore = result.restore { present(restore) }
        hasWallpaperBackup = coordinator.hasWallpaperBackup
    }

    private func present(_ result: ActivationReport.WallpaperResult, quietOnSuccess: Bool) {
        switch result {
        case .notRequested:
            if !quietOnSuccess { banner = nil }
        case .applied(let report):
            if report.failed.isEmpty {
                if !quietOnSuccess || banner?.kind == .recovery { banner = nil }
            } else {
                let details = report.failed
                    .sorted { $0.key.name < $1.key.name }
                    .map { "\($0.key.name): \($0.value)" }
                    .joined(separator: "\n")
                banner = Banner(kind: .warning, title: "Wallpaper changed on some displays only", message: details)
            }
        case .unavailable(let world):
            banner = Banner(kind: .info, title: "No wallpaper for \(world.displayName) yet",
                            message: "Your wallpaper was left unchanged.")
        case .failed(let message):
            banner = Banner(kind: .error, title: "Wallpaper not changed", message: message)
        }
    }

    private func present(_ report: WallpaperRestoreReport) {
        hasWallpaperBackup = coordinator.hasWallpaperBackup
        if report.nothingToRestore {
            banner = nil
        } else if report.isComplete {
            banner = Banner(kind: .success, title: "Welcome back", message: report.summary)
        } else {
            banner = Banner(kind: .warning, title: "Wallpaper only partly restored", message: report.summary)
        }
    }
}
#endif
