import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 探针：在真实桌面空白处验证「图标层之上的透明窗口」能否收到 mouseDown。
///
/// 上一版探针的坑：点击坐标落在了别的 App 窗口上（前台 App 变成了 Edge），
/// 所以没有任何一层能收到事件 —— 结论无效。
/// 这一版先用 ScreenCaptureKit 找到**真正空旷的桌面点**（上方没有任何 App 窗口），
/// 再逐层做对照实验。
///
/// 用法：swift Tools/probe_capture.swift

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
        print("  ↪️  收到 mouseDragged")
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

func cg(_ p: NSPoint) -> CGPoint {
    CGPoint(x: p.x, y: screenFrame.maxY - p.y)
}

func wait(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 找出上方没有 App 窗口覆盖的桌面点（AppKit 坐标）
func findEmptyDesktopPoint(content: SCShareableContent) -> NSPoint? {
    // 只考虑 level > 图标层的窗口（普通 App 窗口）会遮挡桌面
    let blockers = content.windows.filter { $0.windowLayer > iconLevel && $0.isOnScreen }

    var candidate = NSPoint(x: 400, y: 900)
    let step: Double = 37
    outer: for iy in 0..<30 {
        for ix in 0..<60 {
            let fx = 200.0 + Double(ix) * step
            let fy = 200.0 + Double(iy) * step
            let p = NSPoint(x: fx, y: fy)
            guard screenFrame.contains(p) else { continue }
            let gp = cg(p)
            let hit = blockers.contains { $0.frame.contains(gp) }
            if !hit {
                candidate = p
                break outer
            }
        }
    }

    // 再确认该点上方确实没有 App 窗口
    let gp = cg(candidate)
    let hit = blockers.filter { $0.frame.contains(gp) }
    if !hit.isEmpty { return nil }
    return candidate
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("屏幕 frame = \(screenFrame)")
        print("图标层 = \(iconLevel)")
        print("前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        print("AX 信任 = \(AXIsProcessTrusted())")

        guard let pt = findEmptyDesktopPoint(content: content) else {
            print("❌ 找不到空旷桌面点"); sem.signal(); exit(1)
        }
        print("空旷桌面点 (AppKit) = \(pt)  (CG) = \(cg(pt))")

        let size = NSSize(width: 140, height: 140)
        let origin = NSPoint(x: pt.x - size.width / 2, y: pt.y - size.height / 2)

        struct Case {
            let name: String
            let level: Int
            let clearBackground: Bool
            let nonactivating: Bool
        }

        let cases: [Case] = [
            Case(name: "图标层-1 · 透明 · 普通窗口（当前挂件层级）",
                 level: iconLevel - 1, clearBackground: true, nonactivating: false),
            Case(name: "图标层   · 透明 · 普通窗口",
                 level: iconLevel, clearBackground: true, nonactivating: false),
            Case(name: "图标层+1 · 透明 · 普通窗口",
                 level: iconLevel + 1, clearBackground: true, nonactivating: false),
            Case(name: "图标层+1 · 透明 · nonactivatingPanel",
                 level: iconLevel + 1, clearBackground: true, nonactivating: true),
            Case(name: "图标层+1 · 白色不透明 · 普通窗口",
                 level: iconLevel + 1, clearBackground: false, nonactivating: false),
        ]

        for c in cases {
            print("")
            print("▶️ \(c.name)  level=\(c.level)")
            let style: NSWindow.StyleMask = c.nonactivating ? [.borderless, .nonactivatingPanel] : [.borderless]
            let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                               styleMask: style,
                               backing: .buffered,
                               defer: false)
            win.level = NSWindow.Level(c.level)
            win.isOpaque = !c.clearBackground
            win.backgroundColor = c.clearBackground ? .clear : .white
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.hidesOnDeactivate = false
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let view = ProbeView(label: c.name)
            view.frame = NSRect(origin: .zero, size: size)
            win.contentView = view
            win.orderFrontRegardless()

            wait(0.7)

            let p = cg(pt)
            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(p)
            wait(0.3)
            if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                                  mouseCursorPosition: p, mouseButton: .left) {
                down.post(tap: .cghidEventTap)
            }
            wait(0.2)
            if let drag = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                                  mouseCursorPosition: CGPoint(x: p.x + 30, y: p.y + 30),
                                  mouseButton: .left) {
                drag.post(tap: .cghidEventTap)
            }
            wait(0.2)
            if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                                mouseCursorPosition: CGPoint(x: p.x + 30, y: p.y + 30),
                                mouseButton: .left) {
                up.post(tap: .cghidEventTap)
            }
            wait(0.6)
            print("  （拖完后前台 App = \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")）")

            win.orderOut(nil)
            win.contentView = nil
            wait(0.4)
        }
        print("")
        print("探测结束")
        sem.signal()
    }
    sem.wait()
    exit(0)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
