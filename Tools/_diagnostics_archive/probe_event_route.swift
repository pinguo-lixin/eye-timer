import AppKit
import CoreGraphics

/// 深挖：事件已被路由到窗口（hitTest 被调用），
/// 但 mouseDown 却没有派发到视图 —— 卡在哪一步？
///
/// 可能原因：
///   1. 窗口不是 key window，且 App 未激活 → AppKit 走「首次点击只激活」的路径；
///   2. `NSWindow` 的 `canBecomeKey` / `nonactivatingPanel` 行为；
///   3. 事件被送给了窗口的 contentView 但被 responder 链丢弃。
///
/// 本探针用**真实事件**（CGEvent 注入）而不是 `sendEvent`，
/// 并逐一验证各种组合。
///
/// 用法：swift Tools/probe_event_route.swift

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
        print("    🔍 acceptsFirstMouse")
        fflush(stdout)
        return true
    }
    override func mouseDown(with event: NSEvent) {
        print("    ✅ mouseDown")
        fflush(stdout)
    }
    override func mouseUp(with event: NSEvent) {
        print("    ✅ mouseUp")
        fflush(stdout)
    }
    override func mouseMoved(with event: NSEvent) {
        print("    🖱️  mouseMoved")
        fflush(stdout)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        print("    🪟 viewDidMoveToWindow (window=\(window?.title ?? "nil"))")
        fflush(stdout)
    }
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame
let target = CGPoint(x: 3180, y: 200)     // 上次探针找到的裸桌面点

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func click() {
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(target)
    pump(0.4)
    if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                      mouseCursorPosition: target, mouseButton: .left) {
        d.post(tap: .cghidEventTap)
    }
    pump(0.25)
    if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                      mouseCursorPosition: target, mouseButton: .left) {
        u.post(tap: .cghidEventTap)
    }
    pump(0.6)
}

let size = NSSize(width: 130, height: 130)
let appKitPoint = NSPoint(x: target.x, y: screenFrame.maxY - target.y)
let origin = NSPoint(x: appKitPoint.x - size.width / 2, y: appKitPoint.y - size.height / 2)

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    print("裸桌面点 (CG) = \(target)\n")

    struct Case {
        let name: String
        let level: Int
        let nonactivating: Bool
        let floatingPanel: Bool
    }

    let cases: [Case] = [
        Case(name: "普通窗口 · 图标层+1", level: iconLevel + 1, nonactivating: false, floatingPanel: false),
        Case(name: "nonactivatingPanel · 图标层+1", level: iconLevel + 1, nonactivating: true, floatingPanel: true),
        Case(name: "普通窗口 · 图标层+1 · 激活 App", level: iconLevel + 1, nonactivating: false, floatingPanel: false),
    ]

    for (idx, c) in cases.enumerated() {
        print("▶️ \(c.name)  level=\(c.level)")
        let style: NSWindow.StyleMask = c.nonactivating ? [.borderless, .nonactivatingPanel] : [.borderless]
        let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                           styleMask: style,
                           backing: .buffered,
                           defer: false)
        win.level = NSWindow.Level(c.level)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if c.floatingPanel { win.setFrameOrigin(origin) }
        let v = ProbeView(label: c.name)
        v.frame = NSRect(origin: .zero, size: size)
        win.contentView = v
        win.orderFrontRegardless()
        pump(1.0)

        // 第三个用例：主动激活 App
        if idx == 2 {
            print("    → NSApp.activate")
            NSApp.activate(ignoringOtherApps: true)
            pump(1.0)
        }

        print("    前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        print("    win.isKeyWindow = \(win.isKeyWindow)  canBecomeKey = \(win.canBecomeKey)")

        click()

        win.orderOut(nil)
        win.contentView = nil
        pump(0.5)
        print("")
    }
    print("探测结束")
    exit(0)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
