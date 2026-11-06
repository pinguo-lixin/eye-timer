import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 关键探针：窗口成为 **key window** 之后，点击能否派发到视图？
///
/// 上一版探针里 `nonactivatingPanel + makeKeyAndOrderFront` 让 `isKeyWindow == true`，
/// 但 mouseDown 仍未派发 —— 需要确认是不是「App 必须在前面」这一条还没满足。
///
/// 这一版：
///   1. 让 App 处于前台（activate）
///   2. 用 nonactivatingPanel 抢 key
///   3. 在 Finder 处于前台的情况下点击
///   4. 对比「App 前台」与「Finder 前台」两种情况
///
/// 另外测试 `NSApplication.activate` 之后立刻点击的时序问题
/// （activate 是异步的，需要等它生效）。
///
/// 用法：swift Tools/probe_key_window.swift

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

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

        func makeWindow() -> KeyPanel {
            let win = KeyPanel(contentRect: NSRect(origin: origin, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
            win.level = NSWindow.Level(iconLevel + 1)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.hidesOnDeactivate = false
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let v = ProbeView(label: "key-window")
            v.frame = NSRect(origin: .zero, size: size)
            win.contentView = v
            return win
        }

        func click() {
            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(target)
            pump(0.5)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: target, mouseButton: .left) {
                d.post(tap: .cghidEventTap)
            }
            pump(0.3)
            if let g = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                              mouseCursorPosition: CGPoint(x: target.x + 40, y: target.y + 40),
                              mouseButton: .left) {
                g.post(tap: .cghidEventTap)
            }
            pump(0.3)
            if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                              mouseCursorPosition: CGPoint(x: target.x + 40, y: target.y + 40),
                              mouseButton: .left) {
                u.post(tap: .cghidEventTap)
            }
            pump(0.8)
        }

        // ===== 场景 1：App 处于前台 =====
        print("════════ 场景 1：App 处于前台 ════════")
        NSApp.activate(ignoringOtherApps: true)
        pump(1.5)
        print("前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        let w1 = makeWindow()
        w1.makeKeyAndOrderFront(nil)
        pump(1.2)
        print("isKeyWindow = \(w1.isKeyWindow)")
        click()
        w1.orderOut(nil); w1.contentView = nil
        pump(0.8)

        // ===== 场景 2：Finder 前台，但面板已 grab key =====
        print("\n════════ 场景 2：Finder 前台 + 面板已是 key ════════")
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        finder?.activate(options: [.activateIgnoringOtherApps])
        pump(1.5)
        print("前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        let w2 = makeWindow()
        w2.makeKeyAndOrderFront(nil)
        pump(1.2)
        print("isKeyWindow = \(w2.isKeyWindow)   前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        click()
        print("点击后前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        w2.orderOut(nil); w2.contentView = nil
        pump(0.8)

        // ===== 场景 3：Finder 前台，激活 App 后立刻点（不等） =====
        print("\n════════ 场景 3：Finder 前台 → activate → 立刻点击 ════════")
        finder?.activate(options: [.activateIgnoringOtherApps])
        pump(1.5)
        let w3 = makeWindow()
        w3.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pump(0.15)          // 不等 activate 完全生效
        click()
        w3.orderOut(nil); w3.contentView = nil
        pump(0.8)

        print("\n探测结束")
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
