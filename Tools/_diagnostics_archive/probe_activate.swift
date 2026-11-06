import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 决定性探针：让**非前台 App** 的窗口收到 mouseDown 的可行路径。
///
/// ## 背景
///
/// AppKit 的规则是：点击只会派发给**前台 App** 的窗口。
/// 所以「透明输入窗」要生效，必须先让我们的 App 成为前台（或窗口成为 key）。
///
/// 这一版穷举几种「不抢焦点也能拿到点击」的策略：
///
/// | 用例 | 策略 |
/// |---|---|
/// | A | 普通窗 + makeKeyAndOrderFront + activate |
/// | B | 普通窗 + makeKeyAndOrderFront（不 activate） |
/// | C | nonactivatingPanel + makeKeyAndOrderFront |
/// | D | 鼠标移入时才 activate（模拟「悬停激活」） |
/// | E | 窗口 canBecomeKey + makeKeyAndOrderFront + activate + 不抢焦点策略 |
///
/// 用法：swift Tools/probe_activate.swift

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

        struct Case {
            let name: String
            let level: Int
            let nonactivating: Bool
            let makeKey: Bool
            let activate: Bool
            let activateOnHover: Bool
        }

        let cases: [Case] = [
            Case(name: "A 普通窗 + makeKey + activate", level: iconLevel + 1, nonactivating: false, makeKey: true, activate: true, activateOnHover: false),
            Case(name: "B 普通窗 + makeKey（不 activate）", level: iconLevel + 1, nonactivating: false, makeKey: true, activate: false, activateOnHover: false),
            Case(name: "C nonactivatingPanel + makeKey", level: iconLevel + 1, nonactivating: true, makeKey: true, activate: false, activateOnHover: false),
            Case(name: "D 悬停时 activate + 普通窗", level: iconLevel + 1, nonactivating: false, makeKey: true, activate: false, activateOnHover: true),
        ]

        for c in cases {
            print("▶️ \(c.name)")
            let style: NSWindow.StyleMask = c.nonactivating ? [.borderless, .nonactivatingPanel] : [.borderless]
            let win = KeyPanel(contentRect: NSRect(origin: origin, size: size),
                               styleMask: style, backing: .buffered, defer: false)
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
            pump(1.0)

            // 让别的 App（Finder）当前台，模拟真实场景
            let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
            finder?.activate(options: [.activateIgnoringOtherApps])
            pump(1.2)
            print("    前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

            // D 用例：鼠标移入时激活
            if c.activateOnHover {
                CGAssociateMouseAndMouseCursorPosition(1)
                CGWarpMouseCursorPosition(target)
                pump(0.5)
                NSApp.activate(ignoringOtherApps: true)
                pump(1.2)
                print("    悬停激活后前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
            }

            if c.activate {
                NSApp.activate(ignoringOtherApps: true)
                pump(1.2)
                print("    activate 后前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
            }

            if c.makeKey {
                win.makeKeyAndOrderFront(nil)
                pump(0.6)
                print("    isKeyWindow = \(win.isKeyWindow)")
            }

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

            win.orderOut(nil)
            win.contentView = nil
            pump(0.8)
            print("")
        }
        print("探测结束")
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
