import AppKit
import CoreGraphics

/// 探针：验证「图标层之上的透明窗口」能否在 Finder 保持前台时收到 mouseDown。
///
/// 真实场景复现条件：
///   - 挂件在图标层之下 → 点击穿透给 Finder → Finder 画多选矩形；
///   - 若另建一个**完全透明**的窗口放在图标层之上（iconLevel+1），
///     且它不激活 App（nonactivatingPanel），就能在 Finder 前台时截住这次按下，
///     Finder 收不到 → 不会画矩形。
///
/// ⚠️ 探针进程本身保持 accessory（不抢前台），这样前台仍是 Finder，
///    与真实使用场景一致（上一版探针失败正是因为脚本自己成了前台 App）。
///
/// 用法：swift Tools/probe_input_capture.swift

final class ProbeView: NSView {
    let label: String
    init(label: String) {
        self.label = label
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        print("  ✅ 收到 mouseDown —— \(label)")
        fflush(stdout)
    }

    override func mouseDragged(with event: NSEvent) {
        print("  ↪️ 收到 mouseDragged")
        fflush(stdout)
    }

    override func mouseUp(with event: NSEvent) {
        print("  ✅ 收到 mouseUp")
        fflush(stdout)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) { return self }
        return super.hitTest(point)
    }
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame
print("屏幕 frame = \(screenFrame)")
print("图标层 = \(iconLevel)")
print("前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
print("AX 信任 = \(AXIsProcessTrusted())")
print("")

func cg(_ p: NSPoint) -> CGPoint {
    CGPoint(x: p.x, y: screenFrame.maxY - p.y)
}

func wait(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func click(at point: NSPoint) {
    let p = cg(point)
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(p)
    wait(0.3)
    if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: p, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
    }
    wait(0.3)
    if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                        mouseCursorPosition: p, mouseButton: .left) {
        up.post(tap: .cghidEventTap)
    }
    wait(0.6)
}

/// 桌面空白处，避开 Dock / EyeTimer 挂件
let origin = NSPoint(x: 900, y: 500)
let size = NSSize(width: 120, height: 120)
let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)

struct Case {
    let name: String
    let level: Int
    let nonactivating: Bool
}

let cases: [Case] = [
    Case(name: "图标层-1 · 普通窗口（当前挂件层级）", level: iconLevel - 1, nonactivating: false),
    Case(name: "图标层+1 · 透明 nonactivatingPanel", level: iconLevel + 1, nonactivating: true),
    Case(name: "图标层+1 · 透明普通窗口", level: iconLevel + 1, nonactivating: false),
]

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    for c in cases {
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
        let view = ProbeView(label: c.name)
        view.frame = NSRect(origin: .zero, size: size)
        win.contentView = view
        win.orderFrontRegardless()

        wait(0.7)
        print("  （前台 App 仍为 \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")）")
        click(at: center)

        win.orderOut(nil)
        win.contentView = nil
        wait(0.4)
        print("")
    }
    print("探测结束")
    exit(0)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
