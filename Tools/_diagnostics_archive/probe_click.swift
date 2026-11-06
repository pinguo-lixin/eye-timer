import AppKit
import CoreGraphics

/// 探针：搞清楚「桌面层窗口到底能不能收到鼠标按下」以及「能否拦截事件」。
///
/// 背景：挂件放在图标层之下（iconLevel-1）时，点击会穿透给 Finder，
/// Finder 于是画出多选矩形（marquee）。
///
/// 本探针验证两件事：
///   A. 位于图标层之上、覆盖挂件大小的**透明窗口**能否收到 mouseDown
///      → 若能，则可用「输入捕获窗」方案解决，且视觉上图标依然盖在挂件上面。
///   B. `CGEvent.tapCreate` 能否创建成功（事件 tap 可吞掉事件，
///      让 Finder 根本收不到这次按下）—— 需要辅助功能/输入监控授权。
///
/// ⚠️ 关键：必须以真正的 GUI app 方式启动（`app.run()`），
/// 否则 AppKit 不会完成 launch，窗口收不到任何事件。
///
/// 用法：swift Tools/probe_click.swift

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) { return self }
        return super.hitTest(point)
    }
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let src = CGEventSource(stateID: .hidSystemState)

var tapCount = 0
var tapCreated = false

func runProbe() {
    let app = NSApplication.shared
    print("主显示器 AppKit frame = \(NSScreen.screens[0].frame)")
    print("图标层 = \(iconLevel)")
    print("辅助功能信任 = \(AXIsProcessTrusted())")
    print("")

    let screenFrame = NSScreen.screens[0].frame

    /// AppKit 点 → CoreGraphics 全局点（CG 原点在主显示器左上角，y 向下）
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
        wait(0.25)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: p, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        wait(0.25)
        if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                            mouseCursorPosition: p, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
        wait(0.5)
    }

    struct Case {
        let name: String
        let level: Int
        let transparent: Bool
    }

    let cases: [Case] = [
        Case(name: "图标层-1 · 透明内容（当前挂件层级）", level: iconLevel - 1, transparent: true),
        Case(name: "图标层   · 透明内容", level: iconLevel, transparent: true),
        Case(name: "图标层+1 · 透明内容（输入捕获窗候选）", level: iconLevel + 1, transparent: true),
        Case(name: "图标层+1 · 不透明内容", level: iconLevel + 1, transparent: false),
    ]

    // 桌面空白处，避开 Dock 与 EyeTimer 挂件
    let origin = NSPoint(x: 900, y: 500)
    let size = NSSize(width: 120, height: 120)
    let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)

    for c in cases {
        print("▶️ \(c.name)  level=\(c.level)")
        let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered,
                           defer: false)
        win.level = NSWindow.Level(c.level)
        win.isOpaque = !c.transparent
        win.backgroundColor = c.transparent ? .clear : NSColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = ProbeView(label: c.name)
        view.frame = NSRect(origin: .zero, size: size)
        win.contentView = view
        win.orderFrontRegardless()

        wait(0.6)
        click(at: center)

        win.orderOut(nil)
        win.contentView = nil
        wait(0.3)
        print("")
    }

    // ---- B. 事件 tap 能否创建 ----
    print("▶️ 事件 tap（可吞掉事件）")
    let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
    let cb: CGEventTapCallBack = { _, type, event, refcon in
        tapCount += 1
        print("  ✅ 事件 tap 收到 leftMouseDown #\(tapCount)")
        fflush(stdout)
        return Unmanaged.passUnretained(event)
    }
    if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                  place: .headInsertEventTap,
                                  options: .defaultTap,
                                  eventsOfInterest: mask,
                                  callback: cb,
                                  userInfo: nil) {
        tapCreated = true
        let srcObj = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), srcObj, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("  ✅ 事件 tap 创建成功")
    } else {
        print("  ❌ 事件 tap 创建失败（需要辅助功能 / 输入监控授权）")
    }
    fflush(stdout)

    // 点一下桌面，看 tap 是否触发
    let p = cg(NSPoint(x: 1400, y: 500))
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(p)
    wait(0.2)
    if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: p, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
    }
    wait(0.2)
    if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                        mouseCursorPosition: p, mouseButton: .left) {
        up.post(tap: .cghidEventTap)
    }
    wait(0.6)
    print("  事件 tap 累计收到 \(tapCount) 次按下 (created=\(tapCreated))")
    print("")
    print("探测结束")
    exit(0)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    runProbe()
}
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
