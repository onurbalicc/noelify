#if os(macOS)
import AppKit
import NoelifyCore

/// Keeps exactly one snow overlay per connected display while snow is showing.
@MainActor
final class SnowOverlayController {
    private(set) var overlays: [CGDirectDisplayID: SnowOverlayWindow] = [:]
    private var configuration: SnowRenderConfiguration?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var isSuspended = false

    func show(_ configuration: SnowRenderConfiguration) {
        self.configuration = configuration
        if observers.isEmpty { observeSystem() }
        for overlay in overlays.values { overlay.apply(configuration) }
        matchScreens()
    }

    func hide() {
        configuration = nil
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        isSuspended = false
        for overlay in overlays.values { overlay.close() }
        overlays.removeAll()
    }

    /// Adds, moves and removes overlays to match the connected displays.
    private func matchScreens() {
        guard let configuration else { return }
        var connected: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            connected.insert(id)
            if let overlay = overlays[id] {
                overlay.move(to: screen)
            } else {
                let overlay = SnowOverlayWindow(screen: screen, configuration: configuration)
                overlay.setSuspended(isSuspended)
                overlays[id] = overlay
            }
        }
        for (id, overlay) in overlays where !connected.contains(id) {
            overlay.close()
            overlays[id] = nil
        }
    }

    private func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        for overlay in overlays.values { overlay.setSuspended(suspended) }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.matchScreens() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.setSuspended(true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.setSuspended(false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.setSuspended(true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.setSuspended(false) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping @MainActor (SnowOverlayController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        observers.append((center, token))
    }
}

/// Bridges the main-thread-only core to AppKit's main actor.
final class MacSnowOverlayHost: SnowOverlayHost {
    let controller: SnowOverlayController

    @MainActor
    init() { controller = SnowOverlayController() }

    func show(_ configuration: SnowRenderConfiguration) {
        MainActor.assumeIsolated { controller.show(configuration) }
    }

    func hide() {
        MainActor.assumeIsolated { controller.hide() }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
#endif
