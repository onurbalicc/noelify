#if os(macOS)
import Foundation
import IOKit.ps
import NoelifyCore

/// Reads the power source, Low Power Mode and thermal state. Event-driven: no polling,
/// no permissions. Main thread only.
final class MacPowerMonitor: PowerMonitor {
    private var onChange: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []

    var condition: PowerCondition {
        let process = ProcessInfo.processInfo
        if process.isLowPowerModeEnabled { return .constrained }
        if process.thermalState == .serious || process.thermalState == .critical { return .constrained }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return .pluggedIn }
        return type == kIOPSBatteryPowerValue ? .battery : .pluggedIn
    }

    func start(onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<MacPowerMonitor>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
                     ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.onChange?() })
        }
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        onChange = nil
    }

    deinit { stop() }
}
#endif
