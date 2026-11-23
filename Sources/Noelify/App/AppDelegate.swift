#if os(macOS)
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Touch the model so crash-recovery state is evaluated at launch, not on first click.
        _ = AppModel.shared

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.screensDidChange() }
        }

        Diagnostics.runIfRequested()
    }

    /// Quitting always leaves the Mac as we found it: effects stop and the wallpaper is restored.
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.prepareForTermination()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}
#endif
