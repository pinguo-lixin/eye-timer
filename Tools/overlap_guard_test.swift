import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 重叠保护验证：
///
/// 1. 挂件被普通 App 窗口盖住 → 点击**不应该**被我们接管
///    （不能补发 mouseUp 打断那个 App，也不能把挂件拖走）
/// 2. 挂件在裸桌面上 → 点击**应该**被我们接管（拖拽生效）
///
/// 用法：swift Tools/overlap_guard_test.swift

let src = CGEventSource(stateID: .hidSystemState)

func pump(_ s: Double) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 覆盖该点的最高层普通 App 窗口（排除 EyeTimer）
func topmostAppWindow(at point: CGPoint) -> (owner: String, layer: Int)? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    var best: (String, Int)?
    for w in list {
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        if owner.contains("EyeTimer") { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard layer >= 0 else { continue }
        guard let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
        let r = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                       width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
        guard r.contains(point) else { continue }
        if best == nil || layer > best!.1 { best = (owner, layer) }
    }
    return best
}

/// 在某点拖拽一小段，返回拖拽前后的挂件位置
func drag(_ from: CGPoint, _ to: CGPoint, steps: Int = 8) {
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(from)
    pump(0.35)
    if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                      mouseCursorPosition: from, mouseButton: .left) {
        d.post(tap: .cghidEventTap)
    }
    pump(0.12)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                           mouseCursorPosition: p, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        pump(0.04)
    }
    pump(0.2)
    if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                      mouseCursorPosition: to, mouseButton: .left) {
        u.post(tap: .cghidEventTap)
    }
    pump(0.5)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        func widgetFrame() -> CGRect? {
            var best: CGRect?
            for w in content.windows {
                let bid = w.owningApplication?.bundleIdentifier ?? ""
                if bid.contains("eyetimer") && w.isOnScreen {
                    if best == nil || w.frame.width * w.frame.height > best!.width * best!.height {
                        best = w.frame
                    }
                }
            }
            return best
        }

        guard let before = widgetFrame() else { print("❌ 未找到挂件"); exit(1) }
        let center = CGPoint(x: before.midX, y: before.midY)
        print("挂件: \(before)")
        print("挂件中心最上层普通 App 窗口: \(topmostAppWindow(at: center)?.owner ?? "无（裸桌面）")")

        let covered = topmostAppWindow(at: center) != nil
        print(covered ? "▶ 场景：挂件被 App 窗口覆盖" : "▶ 场景：挂件在裸桌面上")

        // 拖 60×60
        let to = CGPoint(x: center.x - 60, y: center.y - 60)
        drag(center, to)

        // 重新取窗口列表（缓存的 content 可能过期）
        let content2 = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var after: CGRect?
        for w in content2.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") && w.isOnScreen {
                if after == nil || w.frame.width * w.frame.height > after!.width * after!.height {
                    after = w.frame
                }
            }
        }
        guard let after else { print("❌ 拖拽后找不到挂件"); exit(1) }

        let moved = abs(after.minX - before.minX) > 5 || abs(after.minY - before.minY) > 5
        print("拖拽前: \(before.minX),\(before.minY)  拖拽后: \(after.minX),\(after.minY)  移动了: \(moved)")

        if covered {
            if moved {
                print("❌ 挂件被别的 App 盖住时仍然被拖走了 —— 会抢走那个 App 的交互")
                exit(1)
            } else {
                print("✅ 挂件被覆盖时没有抢走点击/拖拽，保护生效")
                exit(0)
            }
        } else {
            if moved {
                print("✅ 裸桌面上拖拽正常生效")
                exit(0)
            } else {
                print("❌ 裸桌面上拖拽失效")
                exit(1)
            }
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
