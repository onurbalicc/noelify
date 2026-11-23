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
    private var healthCheck: DispatchWorkItem?
    private var rebuildsLeft = 0

    func show(_ configuration: SnowRenderConfiguration) {
        self.configuration = configuration
        if observers.isEmpty { observeSystem() }
        for overlay in overlays.values { overlay.apply(configuration) }
        rebuildsLeft = 3
        matchScreens()
        scheduleHealthCheck()
    }

    func hide() {
        configuration = nil
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        healthCheck?.cancel()
        healthCheck = nil
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
        if !suspended { scheduleHealthCheck() }
    }

    /// Once, shortly after snow starts or the Mac wakes, makes sure frames are really being
    /// produced, and replaces an overlay whose display link never started. Not a timer:
    /// nothing is scheduled again unless an overlay had to be replaced.
    private func scheduleHealthCheck() {
        healthCheck?.cancel()
        let before = overlays.mapValues(\.frameCount)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkHealth(framesBefore: before) }
        }
        healthCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func checkHealth(framesBefore: [CGDirectDisplayID: Int]) {
        healthCheck = nil
        var replaced = false
        for (id, overlay) in overlays {
            overlay.updatePaused()
            guard overlay.isRendering, overlay.frameCount == framesBefore[id], rebuildsLeft > 0 else { continue }
            NSLog("Noelify: snow was not rendering (\(overlay.stateDescription)); replacing the overlay")
            rebuildsLeft -= 1
            overlay.close()
            overlays[id] = nil
            replaced = true
        }
        if replaced {
            matchScreens()
            scheduleHealthCheck()
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.matchScreens() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.setSuspended(true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.setSuspended(false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.setSuspended(true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.setSuspended(false) }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { controller in
            for overlay in controller.overlays.values { overlay.updatePaused() }
        }
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
