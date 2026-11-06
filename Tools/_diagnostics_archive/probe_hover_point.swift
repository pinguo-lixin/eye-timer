import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 探针：找出「上方只有桌面（Finder）覆盖」的空旷点，
/// 并在该点上验证不同层级的透明窗口能否收到 mouseDown。
///
/// 这是决定性实验 —— 之前几版探针的测试点都落在 Edge / VSCode 窗口上，
/// 所以任何层级都收不到事件，结论无效。
///
/// 结论预期：
///   - 图标层-1：收不到（被 Finder 的全屏桌面窗口挡住）→ 现状，会画矩形
///   - 图标层+1：**应该能收到** → 可作为「输入捕获窗」方案
///
/// 用法：swift Tools/probe_hover_point.swift

final class ProbeView: NSView {
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

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("图标层 = \(iconLevel)")
        print("主屏 AppKit frame = \(screenFrame)")

        // 阻塞物：level > 图标层 且在屏的窗口
        let blockers = content.windows.filter { $0.windowLayer > iconLevel && $0.isOnScreen }
        print("\n=== 阻塞窗口 ===")
        for w in blockers {
            let nm = w.owningApplication?.applicationName ?? "?"
            print("  \(nm) level=\(w.windowLayer) frame=\(w.frame)")
        }

        // 找空旷点：没有被任何阻塞窗口覆盖，且在主屏内
        var found: CGPoint?
        let step: CGFloat = 25
        outer: for fy in stride(from: 40.0, through: 1400.0, by: step) {
            for fx in stride(from: 40.0, through: 3400.0, by: step) {
                let p = CGPoint(x: fx, y: fy)
                let covered = blockers.contains { $0.frame.contains(p) }
                if !covered { found = p; break outer }
            }
        }

        guard let target = found else {
            print("\n❌ 整个屏幕都被其他 App 窗口覆盖，找不到空旷点")
            exit(1)
        }
        print("\n✅ 空旷点（CG 坐标）= \(target)  → AppKit = \(NSPoint(x: target.x, y: screenFrame.maxY - target.y))")

        let appKitPoint = NSPoint(x: target.x, y: screenFrame.maxY - target.y)
        let size = NSSize(width: 130, height: 130)
        let origin = NSPoint(x: appKitPoint.x - size.width / 2, y: appKitPoint.y - size.height / 2)

        struct Case { let name: String; let level: Int }
        let cases: [Case] = [
            Case(name: "图标层-1（当前挂件层级）", level: iconLevel - 1),
            Case(name: "图标层", level: iconLevel),
            Case(name: "图标层+1（输入捕获窗候选）", level: iconLevel + 1),
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
            pump(0.8)

            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(target)
            pump(0.3)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: target, mouseButton: .left) {
                d.post(tap: .cghidEventTap)
            }
            pump(0.15)
            if let g = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                              mouseCursorPosition: CGPoint(x: target.x + 40, y: target.y + 40),
                              mouseButton: .left) {
                g.post(tap: .cghidEventTap)
            }
            pump(0.15)
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
