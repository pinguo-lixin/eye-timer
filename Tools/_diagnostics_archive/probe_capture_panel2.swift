import AppKit
import CoreGraphics

/// 探针：验证「图标层之上的透明捕获窗」能否在**其它 App 窗口之上**抢到鼠标按下。
///
/// 上一版探针失败是因为要找「空旷桌面点」，但桌面上方被 VSCode 大窗口铺满，
/// 找不到空点 —— 这其实更接近真实场景（用户就在某个 App 前面时拖桌面挂件）。
/// 这一版直接在 VSCode 窗口区域上测试。
///
/// 用法：swift Tools/probe_capture_panel2.swift

final class CaptureView: NSView {
    let label: String
    init(label: String) {
        self.label = label
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        print("  ✅ mouseDown     (tag=\(label))")
        fflush(stdout)
    }
    override func mouseDragged(with event: NSEvent) {
        print("  ↪️  mouseDragged (tag=\(label))")
        fflush(stdout)
    }
    override func mouseUp(with event: NSEvent) {
        print("  ✅ mouseUp       (tag=\(label))")
        fflush(stdout)
    }

    /// 关键：始终接管命中测试
    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) { return self }
        return super.hitTest(point)
    }
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame

func cg(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: screenFrame.maxY - p.y) }

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 造一个透明捕获窗
func makeCaptureWindow(at point: NSPoint, size: NSSize, level: Int, label: String) -> NSWindow {
    let origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered,
                       defer: false)
    win.level = NSWindow.Level(level)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = false
    win.ignoresMouseEvents = false
    win.hidesOnDeactivate = false
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    let v = CaptureView(label: label)
    v.frame = NSRect(origin: .zero, size: size)
    win.contentView = v
    win.orderFrontRegardless()
    return win
}

func clickDrag(at point: NSPoint, delta: NSPoint) {
    let p = cg(point)
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(p)
    pump(0.3)
    if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                      mouseCursorPosition: p, mouseButton: .left) {
        d.post(tap: .cghidEventTap)
    }
    pump(0.15)
    for i in 1...8 {
        let t = Double(i) / 8.0
        let x = p.x + CGFloat(delta.x) * t
        let y = p.y + CGFloat(delta.y) * t
        if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                           mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        pump(0.03)
    }
    pump(0.25)
    let q = CGPoint(x: p.x + CGFloat(delta.x), y: p.y + CGFloat(delta.y))
    if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                       mouseCursorPosition: q, mouseButton: .left) {
        u.post(tap: .cghidEventTap)
    }
    pump(0.5)
}

// 测试点：VSCode 窗口内部（桌面被它铺满）
let testPoint = NSPoint(x: 1200, y: 700)
let size = NSSize(width: 140, height: 140)

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    print("图标层 = \(iconLevel)")
    print("前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
    print("测试点 (AppKit) = \(testPoint)  (CG) = \(cg(testPoint))\n")

    struct Case {
        let name: String
        let level: Int
    }
    let cases: [Case] = [
        Case(name: "图标层-1（当前挂件层级）", level: iconLevel - 1),
        Case(name: "图标层", level: iconLevel),
        Case(name: "图标层+1（捕获窗候选）", level: iconLevel + 1),
        Case(name: "floating 层", level: Int(CGWindowLevelForKey(.floatingWindow))),
    ]

    for c in cases {
        print("▶️ \(c.name)  level=\(c.level)")
        let win = makeCaptureWindow(at: testPoint, size: size, level: c.level, label: c.name)
        pump(0.8)
        print("  （点击前前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")）")
        clickDrag(at: testPoint, delta: NSPoint(x: 60, y: 60))
        print("  （点击后前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")）")
        win.orderOut(nil)
        win.contentView = nil
        pump(0.4)
        print("")
    }
    print("探测结束")
    exit(0)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
