import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 决定性探针（分类版）：验证不同层级的透明窗口能否在**别的 App 前台**时收到 mouseDown。
///
/// ## 窗口分类
///
/// macOS 上盖在桌面的窗口分三类：
///   - **背景类**（Wallpaper -2147483625 / Dock -2147483624 / Finder 桌面 -2147483603）
///     —— 这些是桌面本身，我们要压过的是 Finder 桌面窗口；
///   - **系统 UI 类**（菜单栏条 -2147483602、通知中心 -2147483601）
///     —— 需要避开测试点；
///   - **普通 App 类**（level >= 0，如 Edge / VSCode / 微信）
///     —— 会吃掉点击，测试点必须避开。
///
/// 前一版探针把背景类也算成遮挡源，导致「找不到干净点」而没跑完。
///
/// ## 结论预期
///
/// - 图标层-1 → 事件不路由（hitTest 不被调用）
/// - floating 层 → 若收到 mouseDown，说明「透明输入窗 + floating 层级」可行，
///   不需要 AX 权限。
///
/// 用法：swift Tools/probe_definitive.swift

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
    override func mouseDragged(with event: NSEvent) {
        print("    ↪️  mouseDragged")
        fflush(stdout)
    }
    override func mouseUp(with event: NSEvent) {
        print("    ✅ mouseUp")
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

/// 会吃掉点击的窗口：普通 App（level >= 0）与系统 UI（level 在图标层之上、但不是 Finder 桌面本身）
func clickBlockers(_ windows: [SCWindow]) -> [SCWindow] {
    windows.filter { w in
        guard w.isOnScreen else { return false }
        // 普通 App 窗口
        if w.windowLayer >= 0 { return true }
        // 系统 UI：比图标层高，但不是 Finder 桌面窗口本身
        if w.windowLayer > iconLevel {
            let nm = w.owningApplication?.bundleIdentifier ?? ""
            if nm == "com.apple.finder" { return false }   // Finder 桌面窗口（我们要压过的目标）
            return true
        }
        return false
    }
}

/// 找一个不被任何 clickBlocker 覆盖的点（±80px 内也要干净）
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
        print("图标层 = \(iconLevel)   floating 层 = \(floatLevel)")
        print("AX 信任 = \(AXIsProcessTrusted())")

        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let onScreen = content.windows.filter { $0.isOnScreen }
        let blockers = clickBlockers(onScreen)
        print("在屏窗口 \(onScreen.count) 个，其中会吃掉点击的 \(blockers.count) 个")

        print("\n=== 点击遮挡源 ===")
        for w in blockers {
            let nm = w.owningApplication?.applicationName ?? "?"
            print("  \(nm) level=\(w.windowLayer) frame=\(w.frame)")
        }

        guard let target = findCleanPoint(blockers: blockers) else {
            print("\n❌ 找不到干净点"); exit(1)
        }
        print("\n✅ 干净点 (CG) = \(target)")
        print("   前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        let size = NSSize(width: 130, height: 130)
        let appKitPoint = NSPoint(x: target.x, y: screenFrame.maxY - target.y)
        let origin = NSPoint(x: appKitPoint.x - size.width / 2, y: appKitPoint.y - size.height / 2)

        struct Case { let name: String; let level: Int; let nonactivating: Bool }
        let cases: [Case] = [
            Case(name: "图标层-1（挂件当前层级）", level: iconLevel - 1, nonactivating: false),
            Case(name: "图标层+1", level: iconLevel + 1, nonactivating: true),
            Case(name: "floating 层", level: floatLevel, nonactivating: true),
            Case(name: "floating 层 + 普通窗口", level: floatLevel, nonactivating: false),
        ]

        for c in cases {
            print("\n▶️ \(c.name)  level=\(c.level)  nonactivating=\(c.nonactivating)")

            let content2 = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let dirty = clickBlockers(content2.windows).filter { $0.frame.contains(target) }
                .map { "\($0.owningApplication?.applicationName ?? "?")@\($0.windowLayer)" }
            if !dirty.isEmpty {
                print("    ⚠️ 该点已被 \(dirty) 覆盖，跳过")
                continue
            }

            let style: NSWindow.StyleMask = c.nonactivating ? [.borderless, .nonactivatingPanel] : [.borderless]
            let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
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
            print("    点击后前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

            win.orderOut(nil)
            win.contentView = nil
            pump(0.6)
        }
        print("\n探测结束")
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
