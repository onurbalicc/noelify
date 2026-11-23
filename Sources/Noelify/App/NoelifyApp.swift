#if os(macOS)
import SwiftUI

/// Noelify lives entirely in the menu bar (LSUIElement = YES: no Dock icon, no main window).
@main
@MainActor
struct NoelifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            ControlCenterView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.isActive ? "snowflake.circle.fill" : "snowflake")
                .accessibilityLabel(model.isActive ? "Noelify — Christmas Mode on" : "Noelify")
        }
        .menuBarExtraStyle(.window)
    }
}
#else
/// Noelify's app target is macOS-only. On other platforms only `NoelifyCore`
/// (and its tests) are meaningful; this stub keeps `swift build`/`swift test` working.
@main
enum NoelifyUnsupportedPlatform {
    static func main() {
        print("Noelify is a macOS app. Build it on macOS 13 or later.")
    }
}
#endif
