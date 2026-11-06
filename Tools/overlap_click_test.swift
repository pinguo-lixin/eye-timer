import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 重叠区点击测试：挂件被别的 App 窗口盖住时，点击是否被误伤。
///
/// ## 为什么要测
///
/// 修复「桌面画矩形」的办法是：在检测到按下的瞬间**补发一个 mouseUp**，
/// 让 Finder 认为这次点击已经结束。
///
/// 但挂件位于**桌面图标层之下**（比所有普通 App 窗口都低），
/// 所以当别的 App 窗口盖住挂件时：
///   - 点击其实应该被那个 App 收到；
///   - 而我们补发的 mouseUp 会**把那个 App 的这次点击打断**。
///
/// 这是一个真实的回归风险，必须验证。
///
/// 用法：swift Tools/overlap_click_test.swift

let src = CGEventSource(stateID: .hidSystemState)

func pump(_ s: Double) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 找出覆盖某点的「最高层」窗口（排除自己的 App）
func topmostWindow(at point: CGPoint) -> (owner: String, layer: Int, name: String)? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    var best: (String, Int, String)?
    for w in list {
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        if owner.contains("EyeTimer") { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let r = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                       width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
        guard r.contains(point) else { continue }
        let name = (w[kCGWindowName as String] as? String) ?? ""
        if best == nil || layer > best!.1 {
            best = (owner, layer, name)
        }
    }
    return best.map { ($0.0, $0.1, $0.2) }
}

/// 在某点做一次「按下 → 抬起」，返回抬起时该点最上层的窗口
func clickAt(_ p: CGPoint) {
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(p)
    pump(0.4)
    if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                      mouseCursorPosition: p, mouseButton: .left) {
        d.post(tap: .cghidEventTap)
    }
    pump(0.12)
    if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                      mouseCursorPosition: p, mouseButton: .left) {
        u.post(tap: .cghidEventTap)
    }
    pump(0.5)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task {
        // 找 EyeTimer 挂件
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var widget: CGRect?
        for w in content.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") && w.isOnScreen {
                if widget == nil || w.frame.width * w.frame.height > widget!.width * widget!.height {
                    widget = w.frame
                }
            }
        }
        guard let widget else { print("❌ 未找到挂件"); exit(1) }
        print("挂件 frame: \(widget)")

        let center = CGPoint(x: widget.midX, y: widget.midY)
        let top = topmostWindow(at: center)
        print("挂件中心最上层窗口: \(top.map { "\($0.owner) layer=\($0.layer) \($0.name)" } ?? "无")")

        if let t = top, t.layer >= 0 {
            print("⚠️  挂件被普通 App 窗口覆盖（\(t.owner)），点击应该交给那个 App")
            print("    → 修复逻辑若补发 mouseUp，会打断该 App 的这次点击")
        } else {
            print("✅ 挂件中心是裸桌面，点击应该由 Finder 处理")
        }

        // 记录点击后的窗口状态
        let before = topmostWindow(at: center)
        clickAt(center)
        let after = topmostWindow(at: center)
        print("点击前后最上层窗口: \(before?.owner ?? "无") → \(after?.owner ?? "无")")
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
