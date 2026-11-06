import AppKit
import SwiftUI
import AVFoundation
import UserNotifications

// Runs as a separate app with its own defaults/container. Never requests TCC permissions.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let isSandbox = Bundle.main.bundleIdentifier!.hasSuffix(".sandbox")
var checks: [[String: Any]] = []
var capabilities: [String: Any] = [:]

final class NotificationResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int?
    var value: Int? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

func check(_ name: String, _ passed: Bool, _ detail: String = "") {
    checks.append(["name": name, "passed": passed, "detail": detail])
}

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        _ = RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02)))
    }
}

@MainActor
func probe() throws {
    // Confirm the sandbox actually enforces a boundary, rather than trusting entitlements alone.
    let marker = Bundle.main.bundleURL.deletingLastPathComponent()
        .appendingPathComponent("boundary-\(UUID().uuidString).txt")
    var outsideWriteAllowed = false
    do {
        try Data("probe".utf8).write(to: marker)
        outsideWriteAllowed = true
        try FileManager.default.removeItem(at: marker)
    } catch { }
    check("filesystem_boundary", outsideWriteAllowed != isSandbox,
          "Outside-container write allowed: \(outsideWriteAllowed)")
    check("container_home", NSHomeDirectory().contains("/Library/Containers/") == isSandbox)

    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("EyeTimerProbe", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let localFile = support.appendingPathComponent("roundtrip.txt")
    try Data("container roundtrip".utf8).write(to: localFile)
    check("container_file_roundtrip", try String(contentsOf: localFile, encoding: .utf8) == "container roundtrip")

    let settings = AppSettings.shared
    settings.focusSeconds = 60
    settings.widgetStyle = .monolith
    settings.widgetTheme = .forest
    settings.widgetOpacity = 0.6
    settings.widgetScale = 1
    settings.layerMode = .desktop
    let persisted = UserDefaults.standard.data(forKey: "com.eyetimer.settings.v1")!
    let decoded = try JSONDecoder().decode(AppSettings.Snapshot.self, from: persisted)
    check("settings_persistence", decoded.widgetTheme == .forest && decoded.widgetOpacity == 0.6)
    let stats = StatsStore.shared
    let cycles = stats.today.focusCycles
    stats.recordFocusCycle(seconds: 1)
    check("statistics_persistence", stats.today.focusCycles == cycles + 1)

    let engine = TimerEngine(settings: settings, stats: stats)
    engine.start()
    pump(1.15)
    check("countdown", engine.remainingSeconds == 59)
    engine.pause()
    let paused = engine.remainingSeconds
    pump(1.05)
    check("pause", engine.remainingSeconds == paused)
    engine.resume()
    pump(1.15)
    check("resume", engine.remainingSeconds == paused - 1)
    engine.stopAll()

    for style in WidgetStyle.allCases {
        for theme in WidgetTheme.allCases {
            let renderer = ImageRenderer(content: WidgetFace(style: style, theme: theme))
            check("render_\(style.rawValue)_\(theme.rawValue)", renderer.cgImage != nil)
        }
    }

    let widget = DesktopWidgetController(settings: settings, engine: engine)
    widget.show()
    pump(1.25)
    let display = app.windows.first { $0.contentView is WidgetHostView }
    let input = app.windows.first { $0.contentView is WidgetInputView }
    check("widget_window_level", display?.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
    check("input_window_level", input?.level.rawValue == Int(CGWindowLevelForKey(.floatingWindow)))
    check("aligned_input_window", display != nil && display?.frame == input?.frame)
    if let display {
        let origin = display.frame.origin
        let point = NSPoint(x: display.frame.midX, y: display.frame.midY)
        widget.didPress(at: point)
        widget.didDrag(to: NSPoint(x: point.x - 24, y: point.y - 16))
        widget.didRelease(at: NSPoint(x: point.x - 24, y: point.y - 16))
        check("drag_controller_geometry", abs(display.frame.minX - origin.x + 24) < 1
              && abs(display.frame.minY - origin.y + 16) < 1,
              "Controller callbacks only; not a hardware-event or marquee test")
    }
    widget.destroy()

    let menu = WidgetContextMenu(engine: engine, settings: settings).makeMenu()
    check("context_menu", menu.items[0].isEnabled && !menu.items[1].isEnabled
          && menu.items[3].submenu?.items.count == 3 && menu.items[4].submenu?.items.count == 3)

    let overlay = BreakOverlayController.shared
    overlay.show(duration: 1, phase: .shortBreak, gazeDistance: 6)
    check("overlay_visible", overlay.isShowing)
    pump(1.3)
    check("overlay_auto_dismiss", !overlay.isShowing && overlay.remaining == 0)
    overlay.show(duration: 20, phase: .shortBreak, gazeDistance: 6)
    overlay.hide(notify: false)
    check("overlay_manual_dismiss", !overlay.isShowing)

    let soundURL = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
    let player = try? AVAudioPlayer(contentsOf: soundURL)
    check("system_sound_decode", player != nil && player!.duration > 0)

    // Record the real legacy speech command's behavior without playing audible speech.
    let speechFile = support.appendingPathComponent("speech.aiff")
    try? FileManager.default.removeItem(at: speechFile)
    let speech = Process()
    speech.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    speech.arguments = ["-v", "Tingting", "-o", speechFile.path, "护眼提醒测试"]
    speech.standardOutput = FileHandle.nullDevice
    speech.standardError = FileHandle.nullDevice
    do {
        try speech.run()
        let timeout = Date().addingTimeInterval(8)
        while speech.isRunning && Date() < timeout { pump(0.05) }
        if speech.isRunning {
            speech.terminate()
            capabilities["legacy_speech"] = "timeout"
        } else {
            let bytes = (try? Data(contentsOf: speechFile).count) ?? 0
            capabilities["legacy_speech"] = speech.terminationStatus == 0 && bytes > 0
                ? "generated_audio" : "failed (exit \(speech.terminationStatus), bytes \(bytes))"
        }
    } catch { capabilities["legacy_speech"] = "launch_failed: \(error.localizedDescription)" }

    capabilities["accessibility_trusted"] = AccessibilityAuthorization.isTrusted
    capabilities["post_event_access"] = CGPreflightPostEventAccess()
    let interceptor = MouseEventInterceptor()
    capabilities["event_tap_created"] = interceptor.start()
    interceptor.stop()
    let notificationStatus = NotificationResult()
    UNUserNotificationCenter.current().getNotificationSettings { state in
        // The probe pumps a nested run loop inside a main-queue block. Dispatching back to
        // that same serial queue would defer the result until after the probe has exited.
        notificationStatus.value = state.authorizationStatus.rawValue
    }
    let timeout = Date().addingTimeInterval(2)
    while notificationStatus.value == nil && Date() < timeout { pump(0.05) }
    check("notification_settings_query", notificationStatus.value != nil)
    capabilities["notification_authorization"] = notificationStatus.value ?? -1
    capabilities["login_item_status_query"] = LaunchAtLogin.canRegister
    capabilities["untested"] = ["Real mouse capture/marquee", "Notification delivery after user consent",
                                "Login registration/reboot", "Multiple displays/Spaces", "Audible output"]
}

DispatchQueue.main.async {
    do { try MainActor.assumeIsolated { try probe() } }
    catch { check("probe_execution", false, error.localizedDescription) }
    let failures = checks.filter { $0["passed"] as? Bool == false }.count
    let report: [String: Any] = ["sandbox": isSandbox, "checks": checks,
                               "failures": failures, "capabilities": capabilities,
                               "os": ProcessInfo.processInfo.operatingSystemVersionString]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(failures == 0 ? 0 : 1)
}
app.run()
