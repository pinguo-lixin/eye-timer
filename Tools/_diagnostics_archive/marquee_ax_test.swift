import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

/// 确定性检测：在**真实拖拽过程中**检查 Finder 桌面是否出现框选矩形。
///
/// ## 判据
///
/// Finder 桌面的辅助功能树结构是：
/// ```
/// AXWindow (AXScrollArea)
///   └─ AXGroup        ← 桌面图标容器
/// ```
///
/// 框选矩形进行中时，Finder 会在这个 AXGroup 下**临时插入一个选区元素**
/// （role 仍是 AXGroup / AXUnknown，带 AXPosition + AXSize）。
/// 框选一结束它就消失。
///
/// 所以：拖拽中途反复采样 AX 树，看有没有多出来的元素，
/// 比像素比对可靠得多（不受光标、其他 App 窗口干扰）。
///
/// 用法：swift Tools/marquee_ax_test.swift

let src = CGEventSource(stateID: .hidSystemState)

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 读出 Finder 桌面 AXGroup 下当前的子元素签名
func desktopChildSignature() -> (count: Int, signatures: [String]) {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        return (-1, [])
    }
    let app = AXUIElementCreateApplication(finder.processIdentifier)

    var windowsValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
          let windows = windowsValue as? [AXUIElement],
          let window = windows.first else { return (-1, []) }

    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AXUIElement] else { return (-1, []) }

    var sigs: [String] = []
    for group in children {
        var groupChildrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(group, kAXChildrenAttribute as CFString, &groupChildrenValue) == .success,
              let groupChildren = groupChildrenValue as? [AXUIElement] else { continue }
        for item in groupChildren {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXRoleAttribute as CFString, &roleValue)
            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subroleValue)
            var positionValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
            var sizeValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
            let pos = (positionValue as? [Any]) ?? []
            let size = (sizeValue as? [Any]) ?? []
            sigs.append("\(roleValue as? String ?? "?")/\(subroleValue as? String ?? "?")"
                        + " pos=\(pos.map { "\($0)" }.joined(separator: ","))"
                        + " size=\(size.map { "\($0)" }.joined(separator: ","))")
        }
    }
    return (sigs.count, sigs)
}

/// 找到桌面空白区域（没有任何普通 App 窗口覆盖），在其上做拖拽
func findBareDesktop(blockers: [SCWindow]) -> CGPoint? {
    let step: CGFloat = 25
    for fy in stride(from: 200.0, through: 1300.0, by: step) {
        for fx in stride(from: 100.0, through: 3300.0, by: step) {
            let p = CGPoint(x: fx, y: fy)
            if blockers.contains(where: { $0.frame.contains(p) }) { continue }
            var clear = true
            for dx in [-120.0, 0, 120.0] {
                for dy in [-120.0, 0, 120.0] {
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
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        // 遮挡源：普通 App 窗口（level >= 0）+ 系统 UI（比图标层高但不是 Finder 桌面）
        var blockers = content.windows.filter { w in
            guard w.isOnScreen else { return false }
            if w.windowLayer >= 0 { return true }
            if w.windowLayer > iconLevel {
                let bid = w.owningApplication?.bundleIdentifier ?? ""
                if bid == "com.apple.finder" { return false }
                return true
            }
            return false
        }
        // 排除 EyeTimer 自己的窗口
        blockers = blockers.filter { !($0.owningApplication?.bundleIdentifier ?? "").contains("eyetimer") }

        // 直接在 EyeTimer 挂件上拖拽 —— 这才是真实场景
        var widget: SCWindow?
        for w in content.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") && w.isOnScreen {
                if widget == nil || w.frame.width * w.frame.height > widget!.frame.width * widget!.frame.height {
                    widget = w
                }
            }
        }
        guard let widget else {
            print("❌ 未找到 EyeTimer 挂件窗口（应用在运行吗？）"); exit(1)
        }
        let target = CGPoint(x: widget.frame.midX, y: widget.frame.midY)
        print("挂件窗口 frame=\(widget.frame) level=\(widget.windowLayer)")
        print("拖拽起点 (CG) = \(target)")

        // 拖拽路径：向左上（挂件默认在右下角），终点留在裸桌面区域内
        var end = CGPoint(x: target.x - 320, y: target.y - 220)
        if end.x < 150 || end.y < 200 {
            end = CGPoint(x: target.x + 320, y: target.y + 220)
        }
        print("拖拽终点 (CG) = \(end)")

        // ---- 基线采样 ----
        let (baseCount, baseSigs) = desktopChildSignature()
        print("\n基线：桌面子元素数 = \(baseCount)")
        for s in baseSigs.prefix(8) { print("  \(s)") }

        // ---- 拖拽，中途采样 ----
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(target)
        pump(0.4)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: target, mouseButton: .left) {
            d.post(tap: .cghidEventTap)
        }
        pump(0.15)

        var maxCount = 0
        var newSigs: Set<String> = []
        for i in 1...16 {
            let t = Double(i) / 16.0
            let x = target.x + (end.x - target.x) * t
            let y = target.y + (end.y - target.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.04)
            let (count, sigs) = desktopChildSignature()
            maxCount = max(maxCount, count)
            for s in sigs where !baseSigs.contains(s) { newSigs.insert(s) }
        }
        pump(0.4)

        // 释放
        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: end, mouseButton: .left) {
            u.post(tap: .cghidEventTap)
        }
        pump(0.8)

        // 释放后再采样
        let (afterCount, afterSigs) = desktopChildSignature()

        print("\n=== 拖拽期间采样结果 ===")
        print("基线子元素数: \(baseCount)")
        print("拖拽中最大子元素数: \(maxCount)")
        print("释放后子元素数: \(afterCount)")
        print("拖拽中新出现的元素 (\(newSigs.count)):")
        for s in newSigs.prefix(10) { print("  \(s)") }

        if maxCount > baseCount && !newSigs.isEmpty {
            print("\n❌ 拖拽期间桌面出现了额外的选区元素 → 框选矩形存在")
            exit(2)
        } else {
            print("\n✅ 拖拽期间桌面没有出现选区元素 → 无框选矩形")
            exit(0)
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
