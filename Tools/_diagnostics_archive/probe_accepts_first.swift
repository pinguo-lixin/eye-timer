import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 穷举探针：把「透明面板能否收到 mouseDown」的所有变量组合都试一遍。
///
/// ## 关键认知（前面的探针已经验证）
///
/// - `NSWindow` **没有**窗口级 `acceptsFirstMouse`（那是 NSView 的方法）——
///   之前写 `override func acceptsFirstMouse` 编译不过就是证据；
/// - `NSPanel` 默认 `canBecomeKey == false` —— 窗口不能成为 key 时，
///   mouseDown 可能不会被派发；
/// - 视图级 `acceptsFirstMouse(for:) → true` 是绕过「首次点击只激活 App」的正规做法。
///
/// ## 本探针的变量
///
/// | 变量 | 取值 |
/// |---|---|
/// | level | 图标层+1 / floating 层 |
/// | styleMask | .borderless / .borderless+.nonactivatingPanel |
/// | canBecomeKey | false / true |
/// | 视图 acceptsFirstMouse | false / true |
/// | makeKeyAndOrderFront | false / true |
///
/// 用法：swift Tools/probe_accepts_first.swift

/// 可配置的窗口：canBecomeKey 可开关
final class ProbePanel: NSPanel {
    var keyCapable = false
    override var canBecomeKey: Bool { keyCapable }
    override var canBecomeMain: Bool { false }
}

final class ProbeView: NSView {
    let label: String
    let viewAccepts: Bool
    init(label: String, viewAccepts: Bool) {
        self.label = label
        self.viewAccepts = viewAccepts
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        print("    📍 hitTest")
        fflush(stdout)
        return bounds.contains(point) ? self : super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        if viewAccepts { print("    🔍 视图 acceptsFirstMouse → true") }
        fflush(stdout)
        return viewAccepts
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
        print("干净点 (CG) = \(target)   前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")\n")

        let size = NSSize(width: 130, height: 130)
        let appKitPoint = NSPoint(x: target.x, y: screenFrame.maxY - target.y)
        let origin = NSPoint(x: appKitPoint.x - size.width / 2, y: appKitPoint.y - size.height / 2)

        struct Case {
            let name: String
            let level: Int
            let nonactivating: Bool
            let keyCapable: Bool
            let viewAccepts: Bool
            let makeKey: Bool
        }

        let cases: [Case] = [
            Case(name: "1 图标层+1 / 普通窗 / 无key / 视图放行",
                 level: iconLevel + 1, nonactivating: false, keyCapable: false, viewAccepts: true, makeKey: false),
            Case(name: "2 图标层+1 / nonactivating / 无key / 视图放行",
                 level: iconLevel + 1, nonactivating: true, keyCapable: false, viewAccepts: true, makeKey: false),
            Case(name: "3 图标层+1 / nonactivating / 可key / 视图放行",
                 level: iconLevel + 1, nonactivating: true, keyCapable: true, viewAccepts: true, makeKey: false),
            Case(name: "4 图标层+1 / nonactivating / 可key / 视图放行 / makeKey",
                 level: iconLevel + 1, nonactivating: true, keyCapable: true, viewAccepts: true, makeKey: true),
            Case(name: "5 floating / nonactivating / 可key / 视图放行",
                 level: floatLevel, nonactivating: true, keyCapable: true, viewAccepts: true, makeKey: false),
            Case(name: "6 floating / nonactivating / 可key / 视图放行 / makeKey",
                 level: floatLevel, nonactivating: true, keyCapable: true, viewAccepts: true, makeKey: true),
        ]

        for c in cases {
            print("▶️ \(c.name)")
            let style: NSWindow.StyleMask = c.nonactivating ? [.borderless, .nonactivatingPanel] : [.borderless]
            let win = ProbePanel(contentRect: NSRect(origin: origin, size: size),
                                 styleMask: style, backing: .buffered, defer: false)
            win.keyCapable = c.keyCapable
            win.level = NSWindow.Level(c.level)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.hidesOnDeactivate = false
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let v = ProbeView(label: c.name, viewAccepts: c.viewAccepts)
            v.frame = NSRect(origin: .zero, size: size)
            win.contentView = v
            if c.makeKey {
                win.makeKeyAndOrderFront(nil)
            } else {
                win.orderFrontRegardless()
            }
            pump(1.2)

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
            pump(0.6)
            print("")
        }
        print("探测结束")
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
