#if os(macOS)
import AppKit
import SwiftUI
import NoelifyCore

/// Self-test and benchmark for the snow engine, run only when asked for:
///
///     Noelify.app/Contents/MacOS/Noelify --snow-diagnostics <output folder> \
///         [--power pluggedIn|battery|constrained] [--seconds 6] [--checks-only | --benchmark-only]
///
/// Drives the real `AppModel`, module and overlay, but keeps its settings in a separate
/// preferences domain and never changes the wallpaper. Captures only Noelify's own
/// drawing, never the screen. Writes `report.txt` and PNGs, then quits
/// (exit status 1 if a check failed). See docs/TESTING.md.
@MainActor
enum Diagnostics {
    static let settingsDomain = "app.noelify.Noelify.diagnostics"

    static var settingsDefaults: UserDefaults? {
        outputDirectory == nil ? nil : UserDefaults(suiteName: settingsDomain)
    }

    static var powerOverride: PowerMonitor? {
        guard outputDirectory != nil, let value = argument(after: "--power"),
              let condition = PowerCondition(rawValue: value) else { return nil }
        return FixedPower(condition: condition)
    }

    static func runIfRequested() {
        guard let outputDirectory else { return }
        Task { @MainActor in
            let run = DiagnosticsRun(
                model: .shared,
                output: outputDirectory,
                seconds: argument(after: "--seconds").flatMap(Double.init) ?? 6,
                checks: !CommandLine.arguments.contains("--benchmark-only"),
                benchmarks: !CommandLine.arguments.contains("--checks-only")
            )
            let passed = await run.perform()
            // Let the report reach the disk, then leave through the normal quit path.
            UserDefaults(suiteName: settingsDomain)?.synchronize()
            if passed { NSApp.terminate(nil) } else { exit(1) }
        }
    }

    private static var outputDirectory: URL? {
        argument(after: "--snow-diagnostics").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func argument(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1]
    }

    private final class FixedPower: PowerMonitor {
        let condition: PowerCondition
        init(condition: PowerCondition) { self.condition = condition }
        func start(onChange: @escaping () -> Void) {}
        func stop() {}
    }
}

@MainActor
private final class DiagnosticsRun {
    private let model: AppModel
    private let output: URL
    private let seconds: Double
    private let runsChecks: Bool
    private let runsBenchmark: Bool
    private var lines: [String] = []
    private var failures = 0

    init(model: AppModel, output: URL, seconds: Double, checks: Bool, benchmarks: Bool) {
        self.model = model
        self.output = output
        self.seconds = seconds
        runsChecks = checks
        runsBenchmark = benchmarks
    }

    func perform() async -> Bool {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let screens = NSScreen.screens
            .map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.backingScaleFactor))x" }
            .joined(separator: ", ")
        log("Noelify snow diagnostics · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(screens)")
        log("loaded snow settings: \(describe(model.settings.snow))")
        model.setChangesWallpaper(false)
        await pause(1)

        await measure("idle before first use")
        // Benchmark first: snapshots taken by the checks would inflate the memory figures.
        if runsBenchmark { await benchmark() }
        if runsChecks {
            await checkToggling()
            await checkRenderLoop()
            await checkOverlay()
            await checkSettings()
            await checkRendering()
            renderControlCenter()
        }

        // Left in the diagnostics domain so a second run can confirm they were saved.
        set(SnowSettings(intensity: .heavy, wind: .windy, size: .large, style: .magical))
        log(failures == 0 ? "RESULT: all checks passed" : "RESULT: \(failures) check(s) FAILED")
        return failures == 0
    }

    // MARK: - Checks

    private func checkToggling() async {
        set(.default)
        var mostOverlays = 0
        for i in 0..<60 {
            model.setChristmasMode(true)
            mostOverlays = max(mostOverlays, snowWindowCount)
            if i % 7 == 0 { await pause(0.05) }
            model.setChristmasMode(false)
        }
        check("60 rapid on/off cycles never show more than one overlay per display",
              mostOverlays == NSScreen.screens.count, "\(mostOverlays)")
        check("no overlay window is left when off", snowWindowCount == 0, "\(snowWindowCount)")
        model.setChristmasMode(true)
        model.setChristmasMode(true)
        check("turning on twice keeps one overlay per display", snowWindowCount == NSScreen.screens.count)
    }

    private func checkRenderLoop() async {
        var stuck: [String] = []
        for i in 0..<25 {
            model.setChristmasMode(false)
            await pause(i % 2 == 0 ? 0 : 0.1)
            model.setChristmasMode(true)
            await pause(1)
            if let overlay = model.snowOverlays.first, overlay.frameCount < 5 {
                stuck.append("cycle \(i): \(overlay.frameCount) frames, \(overlay.stateDescription)")
            }
        }
        check("the render loop starts every time in 25 restarts", stuck.isEmpty, stuck.joined(separator: "; "))

        guard let overlay = model.snowOverlays.first else { return }
        overlay.panel.orderOut(nil)
        await pause(1)
        let hidden = overlay.frameCount
        await pause(1)
        check("rendering stops while the overlay can't be seen", overlay.frameCount - hidden <= 1,
              "\(overlay.frameCount - hidden) frames, \(overlay.stateDescription)")
        overlay.panel.orderFrontRegardless()
        await pause(1.5)
        check("rendering resumes when it can be seen again", overlay.frameCount - hidden > 5,
              "\(overlay.frameCount - hidden) frames, \(overlay.stateDescription)")
    }

    private func checkOverlay() async {
        model.setChristmasMode(true)
        await pause(2.5)
        guard let overlay = model.snowOverlays.first else { return check("overlay exists", false) }
        let panel = overlay.panel
        check("overlay is visible", panel.isVisible && panel.occlusionState.contains(.visible))
        check("snow was revealed after warming up", overlay.isRevealed)
        check("overlay covers the whole display", NSScreen.screens.contains { $0.frame == panel.frame })
        check("snow fills the panel",
              overlay.drawnRect.insetBy(dx: -1, dy: -1).contains(NSRect(origin: .zero, size: panel.frame.size)),
              "\(overlay.drawnRect), frame buffer \(overlay.drawableSize)")
        check("overlay ignores the mouse", panel.ignoresMouseEvents)
        check("overlay cannot take keyboard focus", !panel.canBecomeKey && !panel.canBecomeMain)
        check("Noelify did not become the active app", !NSApp.isActive)
        check("overlay sits above app windows and below the Dock and menu bar",
              panel.level.rawValue > NSWindow.Level.normal.rawValue
                && panel.level.rawValue < Int(CGWindowLevelForKey(.dockWindow))
                && panel.level.rawValue < NSWindow.Level.mainMenu.rawValue)

        // Ask the window server who would receive a click at a grid of points.
        var hits = 0, points = 0
        let frame = panel.frame
        for column in 0..<24 {
            for row in 0..<16 {
                let point = NSPoint(x: frame.minX + (CGFloat(column) + 0.5) * frame.width / 24,
                                    y: frame.minY + (CGFloat(row) + 0.5) * frame.height / 16)
                points += 1
                if NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == panel.windowNumber { hits += 1 }
            }
        }
        check("clicks at \(points) points all go to what is underneath", hits == 0, "\(hits) hit the overlay")

        // The same probe must see the panel when it does accept clicks, or it proves nothing.
        panel.ignoresMouseEvents = false
        await pause(0.3)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let seen = NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: 0) == panel.windowNumber
        panel.ignoresMouseEvents = true
        await pause(0.3)
        check("click probe control: an overlay that accepts clicks is detected", seen)
    }

    private func checkSettings() async {
        guard model.snowOverlays.first != nil else { return }
        var last = 0
        for intensity in SnowIntensity.allCases where intensity != .off {
            set(SnowSettings(intensity: intensity))
            await pause(1.2)
            let count = model.snowOverlays.first?.flakeCount ?? 0
            check("intensity \(intensity.rawValue) has more flakes than the one before", count > last, "\(count)")
            last = count
        }
        set(SnowSettings(intensity: .off))
        await pause(0.2)
        check("intensity off removes the overlay while Christmas Mode stays on",
              model.isActive && snowWindowCount == 0)
        set(.default)
        await pause(0.5)
        check("leaving intensity off brings the overlay back", snowWindowCount == NSScreen.screens.count)
    }

    private func checkRendering() async {
        let variants: [(String, SnowSettings)] =
            SnowStyle.allCases.map { ("style-\($0.rawValue)", SnowSettings(intensity: .heavy, style: $0)) }
            + SnowSize.allCases.map { ("size-\($0.rawValue)", SnowSettings(intensity: .medium, size: $0)) }
            + SnowWind.allCases.map { ("wind-\($0.rawValue)", SnowSettings(intensity: .medium, wind: $0)) }
            + SnowIntensity.allCases.dropFirst().map { ("intensity-\($0.rawValue)", SnowSettings(intensity: $0)) }
        for (name, settings) in variants {
            set(settings)
            await pause(3)
            guard let overlay = model.snowOverlays.first, let image = overlay.snapshot() else {
                check("\(name) renders", false, "no image")
                continue
            }
            let coverage = opaqueFraction(image)
            check("\(name) draws snow", coverage > 0.0005 && coverage < 0.35,
                  String(format: "%.2f%% of the display covered", coverage * 100))
            save(image, "\(name).png")
        }
        // Two frames apart in time must differ, or nothing is animating.
        set(SnowSettings(intensity: .medium))
        await pause(1.5)
        if let overlay = model.snowOverlays.first, let a = overlay.snapshot()?.dataProvider?.data {
            await pause(0.5)
            let b = overlay.snapshot()?.dataProvider?.data
            check("snow is animated", b.map { !CFEqual(a, $0) } ?? false)
        }
    }

    // MARK: - Benchmark

    private func benchmark() async {
        model.setChristmasMode(true)
        for style in [SnowStyle.realistic] {
            for intensity in SnowIntensity.allCases where intensity != .off {
                set(SnowSettings(intensity: intensity, style: style))
                await measure("\(intensity.rawValue) / \(style.rawValue)")
            }
        }
        for style in SnowStyle.allCases where style != .realistic {
            set(SnowSettings(intensity: .medium, style: style))
            await measure("medium / \(style.rawValue)")
        }
        set(SnowSettings(intensity: .off))
        await measure("Christmas Mode on, snow off")
        model.setChristmasMode(false)
        await measure("Christmas Mode off")
        check("no overlay window is left after the benchmark", snowWindowCount == 0)
    }

    private func measure(_ name: String) async {
        await pause(3) // settle: fades, texture uploads
        let frames = model.snowOverlays.first?.frameCount ?? 0
        let cpu = Self.cpuSeconds()
        let start = ProcessInfo.processInfo.systemUptime
        await pause(seconds)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let cpuPercent = (Self.cpuSeconds() - cpu) / elapsed * 100
        let overlay = model.snowOverlays.first
        let fps = overlay.map { Double($0.frameCount - frames) / elapsed } ?? 0
        log(String(format: "%@ · CPU %.1f%% of one core · memory %.0f MB · %.1f fps · %d flakes",
                   ("perf  " + name).padding(toLength: 36, withPad: " ", startingAt: 0),
                   cpuPercent, Self.footprintMB(), fps, overlay?.flakeCount ?? 0)
            + (overlay.map { $0.isRendering ? "" : " · PAUSED (\($0.stateDescription))" } ?? ""))
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    /// The "Memory" figure Activity Monitor shows.
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    // MARK: - Helpers

    private var snowWindowCount: Int { NSApp.windows.filter { $0 is SnowPanel && $0.isVisible }.count }

    private func set(_ snow: SnowSettings) { model.setSnow(\.self, to: snow) }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        if !passed { failures += 1 }
        log("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " (\(detail))")")
    }

    private func log(_ line: String) {
        lines.append(line)
        print(line)
        fflush(stdout)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    private func describe(_ s: SnowSettings) -> String {
        "\(s.intensity.rawValue), \(s.wind.rawValue), \(s.size.rawValue), \(s.style.rawValue)"
    }

    private func opaqueFraction(_ image: CGImage) -> Double {
        let width = 480, height = max(1, 480 * image.height / max(image.width, 1))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        return Double(pixels.lazy.filter { $0 > 40 }.count) / Double(pixels.count)
    }

    /// Saves the snow over a dark half and a white half, since it must read on both.
    private func save(_ image: CGImage, _ name: String) {
        let size = CGSize(width: image.width, height: image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        c.setFillColor(CGColor(srgbRed: 0.06, green: 0.11, blue: 0.19, alpha: 1))
        c.fill(CGRect(origin: .zero, size: size))
        c.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        c.fill(CGRect(x: size.width * 0.7, y: 0, width: size.width * 0.3, height: size.height))
        c.draw(image, in: CGRect(origin: .zero, size: size))
        if let result = c.makeImage() { write(NSBitmapImageRep(cgImage: result), name) }
    }

    private func renderControlCenter() {
        let host = NSHostingView(rootView: ControlCenterView().environmentObject(model))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        log("control center size: \(Int(host.bounds.width))x\(Int(host.bounds.height)) pt")
        write(rep, "control-center.png")
        window.close()
    }

    private func write(_ rep: NSBitmapImageRep, _ name: String) {
        try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name))
    }
}
#endif
