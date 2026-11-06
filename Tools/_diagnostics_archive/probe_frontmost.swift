import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 决定性实验：透明面板能否在「别的 App 处于前台」时收到 mouseDown？
///
/// ## 关键变量
///
/// 之前的探针都用 `.accessory` 策略（永不激活），结论可能是「非前台 App 收不到点击」。
/// 这一版用 `.regular` 策略，让探针**能**成为前台 App，对比两种情况：
///   A. 探针是前台 App   → 点击理应到达
///   B. 别的 App 是前台   → 关键场景
///
/// 两种情况下窗口层级都是「图标层+1」与「floating 层」。
///
/// ## 判定
///
/// 若 B 情况下也能收到 mouseDown，说明「透明输入窗」方案完全可行，不需要 AX 权限；
/// 若收不到，就只能走事件 tap（AX）路线。
///
/// 用法：swift Tools/probe_frontmost.swift

final class ProbeView: NSView {
    let label: String
    init(label: String) {
        self.label = label
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        print("    📍 hitTest")
        fflush(stdout)
        return bounds.contains(point) ? self : super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        print("    🔍 视图 acceptsFirstMouse → true")
        fflush(stdout)
        return true
    }
    override func mouseDown(with event: NSEvent) {
        print("    ✅ mouseDown 收到 ← 成功！")
        fflush(stdout)
    }
    override func mouseDragged(with event: NSEvent) {
        print("    ↪️  mouseDragged 收到")
        fflush(stdout)
    }
    override func mouseUp(with event: NSEvent) {
        print("    ✅ mouseUp 收到")
        fflush(stdout)
    }
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let floatLevel = Int(CGWindowLevelForKey(.floatingWindow))
let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func clickBlockers(_ windows: [SCWindow]) -> [SCWindow] {
    windows.filter { w in
        guard w.isOnScreen else { return false }
        if w.windowLayer >= 0 { return true }
        if w.windowLayer > iconLevel {
            let nm = w.owningApplication?.bundleIdentifier ?? ""
            if nm == "com.apple.finder" { return false }
            return true
        }
        return false
    }
}

func findCleanPoint(blockers: [SCWindow]) -> CGPoint? {
    let step: CGFloat = 20
    for fy in stride(from: 200.0, through: 1300.0, by: step) {
        for fx in stride(from: 100.0, through: 3300.0, by: step) {
            let p = CGPoint(x: fx, y: fy)
            if blockers.contains(where: { $0.frame.contains(p) }) { continue }
            var clear = true
            for dx in [-80.0, 0, 80.0] {
                for dy in [-80.0, 0, 80.0] {
                    let q = CGPoint(x: p.x + dx, y: p.y + dy)
                    if blockers.contains(where: { $0.frame.contains(q) }) { clear = false }
                }
            }
            if clear { return p }
        }
    }
    return nil
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let blockers = clickBlockers(content.windows)
        guard let target = findCleanPoint(blockers: blockers) else {
            print("❌ 找不到干净点"); exit(1)
        }
        print("干净点 (CG) = \(target)\n")

        let size = NSSize(width: 130, height: 130)
        let appKitPoint = NSPoint(x: target.x, y: screenFrame.maxY - target.y)
        let origin = NSPoint(x: appKitPoint.x - size.width / 2, y: appKitPoint.y - size.height / 2)

        struct Case { let name: String; let level: Int }

        let cases: [Case] = [
            Case(name: "图标层+1", level: iconLevel + 1),
            Case(name: "floating 层", level: floatLevel),
        ]

        // === 场景 A：探针是前台 App ===
        print("════════ 场景 A：探针自己处于前台 ════════")
        NSApp.activate(ignoringOtherApps: true)
        pump(1.5)
        print("前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        for c in cases {
            print("\n▶️ A / \(c.name)")
            let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
            win.level = NSWindow.Level(c.level)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.hidesOnDeactivate = false
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let v = ProbeView(label: c.name)
            v.frame = NSRect(origin: .zero, size: size)
            win.contentView = v
            win.orderFrontRegardless()
            pump(1.2)

            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(target)
            pump(0.5)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: target, mouseButton: .left) {
                d.post(tap: .cghidEventTap)
            }
            pump(0.3)
            if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                              mouseCursorPosition: target, mouseButton: .left) {
                u.post(tap: .cghidEventTap)
            }
            pump(0.8)
            win.orderOut(nil)
            win.contentView = nil
            pump(0.5)
        }

        // === 场景 B：别的 App 是前台（探针退到后台）===
        print("\n\n════════ 场景 B：别的 App 处于前台 ════════")
        // 激活 Finder，让它成为前台
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        finder?.activate(options: [.activateIgnoringOtherApps])
        pump(2.0)
        print("前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        for c in cases {
            print("\n▶️ B / \(c.name)")
            let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
            win.level = NSWindow.Level(c.level)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.hidesOnDeactivate = false
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let v = ProbeView(label: c.name)
            v.frame = NSRect(origin: .zero, size: size)
            win.contentView = v
            win.orderFrontRegardless()
            pump(1.2)

            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(target)
            pump(0.5)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: target, mouseButton: .left) {
                d.post(tap: .cghidEventTap)
            }
            pump(0.3)
            if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                              mouseCursorPosition: target, mouseButton: .left) {
                u.post(tap: .cghidEventTap)
            }
            pump(0.8)
            print("    点击后前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
            win.orderOut(nil)
            win.contentView = nil
            pump(0.5)
        }
        print("\n探测结束")
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
