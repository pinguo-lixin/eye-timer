import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 决定性探针：在**真正可见的桌面区域**上，测试各层级透明窗口能否收到 mouseDown。
///
/// ⚠️ 之前几版探针的致命错误：测试点落在 Edge / VSCode / 微信窗口上，
///    那些窗口在挂件之上，点击自然被它们吃掉 —— 结论完全无效。
///    这一版先用 ScreenCaptureKit 排除所有普通 App 窗口，
///    找到**只有壁纸覆盖**的空点，再做对照。
///
/// 同时验证：事件 tap 能否在该点吞掉事件。
///
/// 用法：swift Tools/probe_desktop_point.swift

final class ProbeView: NSView {
    let label: String
    init(label: String) {
        self.label = label
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        print("  📍 hitTest 被调用 (\(label))")
        fflush(stdout)
        return bounds.contains(point) ? self : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        print("  ✅ mouseDown 收到 (\(label))")
        fflush(stdout)
    }
    override func mouseDragged(with event: NSEvent) {
        print("  ↪️  mouseDragged 收到 (\(label))")
        fflush(stdout)
    }
    override func mouseUp(with event: NSEvent) {
        print("  ✅ mouseUp 收到 (\(label))")
        fflush(stdout)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        print("  🔍 acceptsFirstMouse 被询问 (\(label))")
        fflush(stdout)
        return true
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

/// 找出**只有壁纸覆盖**的空点（无任何普通 App 窗口）
func findBareDesktop(blockers: [SCWindow]) -> CGPoint? {
    // 注意：SCWindow.frame 用的是 CG 坐标（左上原点）
    let step: CGFloat = 20
    var best: CGPoint?
    for fy in stride(from: 40.0, through: 1400.0, by: step) {
        for fx in stride(from: 40.0, through: 3400.0, by: step) {
            let p = CGPoint(x: fx, y: fy)
            let covered = blockers.contains { $0.frame.contains(p) }
            if !covered {
                // 再确认周围一圈也是空的（避免点在窗口边缘）
                var ringClear = true
                for dx in [-60.0, 60.0] {
                    for dy in [-60.0, 60.0] {
                        let q = CGPoint(x: p.x + dx, y: p.y + dy)
                        if blockers.contains(where: { $0.frame.contains(q) }) { ringClear = false }
                    }
                }
                if ringClear { return p }
            }
        }
    }
    return best
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("图标层 = \(iconLevel)")
        print("主屏 frame = \(screenFrame)")

        // 只把 level > 图标层 的在屏窗口当遮挡物
        let blockers = content.windows.filter { $0.windowLayer > iconLevel && $0.isOnScreen }
        print("遮挡窗口数 = \(blockers.count)")

        guard let target = findBareDesktop(blockers: blockers) else {
            print("❌ 找不到完全空旷的桌面点（屏幕被 App 窗口铺满）")
            exit(1)
        }
        print("✅ 裸桌面点 (CG) = \(target)")

        // 顺便看看 EyeTimer 挂件在哪
        for w in content.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") {
                print("   EyeTimer 窗口 level=\(w.windowLayer) frame=\(w.frame)")
            }
        }

        let size = NSSize(width: 130, height: 130)
        let appKitPoint = NSPoint(x: target.x, y: screenFrame.maxY - target.y)
        let origin = NSPoint(x: appKitPoint.x - size.width / 2, y: appKitPoint.y - size.height / 2)

        struct Case { let name: String; let level: Int }
        let cases: [Case] = [
            Case(name: "图标层-1（当前挂件层级）", level: iconLevel - 1),
            Case(name: "图标层", level: iconLevel),
            Case(name: "图标层+1（输入捕获面板候选）", level: iconLevel + 1),
        ]

        for c in cases {
            print("\n▶️ \(c.name)  level=\(c.level)")
            let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered,
                               defer: false)
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

            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(target)
            pump(0.4)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: target, mouseButton: .left) {
                d.post(tap: .cghidEventTap)
            }
            pump(0.2)
            if let g = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                              mouseCursorPosition: CGPoint(x: target.x + 40, y: target.y + 40),
                              mouseButton: .left) {
                g.post(tap: .cghidEventTap)
            }
            pump(0.2)
            if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                              mouseCursorPosition: CGPoint(x: target.x + 40, y: target.y + 40),
                              mouseButton: .left) {
                u.post(tap: .cghidEventTap)
            }
            pump(0.6)

            win.orderOut(nil)
            win.contentView = nil
            pump(0.4)
        }
        print("\n探测结束")
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
