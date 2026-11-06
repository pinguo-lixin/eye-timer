import AppKit
import ApplicationServices
import CoreGraphics

/// 拖拽**过程中**的 AX 树检测。
///
/// ## 为什么用 AX 树而不是像素比对
///
/// 像素比对要求被测区域是裸桌面，环境里随便一个 App 窗口弹过来就作废；
/// 而且「挂件移动」本身也会产生巨大亮度差，容易误判。
///
/// Finder 的桌面框选矩形在**辅助功能树**里是一个独立元素
/// （AXGroup / AXUnknown，subrole=AXUnknown）。
/// 直接问系统「桌面窗口的子树里现在有没有这个东西」，
/// 完全不受像素、遮挡、光标影响 —— 这是**确定性**的判据。
///
/// 用法：swift Tools/marquee_ax_during.swift <起点x> <起点y> <终点x> <终点y>

let src = CGEventSource(stateID: .hidSystemState)

func pump(_ s: Double) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 遍历 Finder 桌面窗口的 AX 子树，找「框选矩形」元素
func findMarqueeElements() -> [(pos: [Any], size: [Any], role: String, subrole: String)] {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        return []
    }
    let app = AXUIElementCreateApplication(finder.processIdentifier)

    var windows: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
          let windowList = windows as? [AXUIElement] else { return [] }

    var found: [(pos: [Any], size: [Any], role: String, subrole: String)] = []

    for window in windowList {
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        guard (titleValue as? String) == "Desktop" else { continue }

        var stack: [AXUIElement] = [window]
        var visited = 0
        while let current = stack.popLast() {
            visited += 1
            if visited > 4000 { break }

            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
            let role = (roleValue as? String) ?? ""

            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = (subroleValue as? String) ?? ""

            if subrole == "AXUnknown" || role == "AXUnknown" {
                var posValue: CFTypeRef?
                AXUIElementCopyAttributeValue(current, kAXPositionAttribute as CFString, &posValue)
                var sizeValue: CFTypeRef?
                AXUIElementCopyAttributeValue(current, kAXSizeAttribute as CFString, &sizeValue)
                found.append(((posValue as? [Any]) ?? [],
                              (sizeValue as? [Any]) ?? [],
                              role, subrole))
            }

            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &children) == .success,
               let childList = children as? [AXUIElement] {
                stack.append(contentsOf: childList)
            }
        }
    }
    return found
}

guard CommandLine.arguments.count >= 5 else {
    print("用法: marquee_ax_during <sx> <sy> <ex> <ey>")
    exit(1)
}
let sx = Double(CommandLine.arguments[1])!, sy = Double(CommandLine.arguments[2])!
let ex = Double(CommandLine.arguments[3])!, ey = Double(CommandLine.arguments[4])!

// 拖拽前
let before = findMarqueeElements()
print("拖拽前：框选元素 \(before.count) 个")

CGAssociateMouseAndMouseCursorPosition(1)
CGWarpMouseCursorPosition(CGPoint(x: sx, y: sy))
pump(0.7)

if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                  mouseCursorPosition: CGPoint(x: sx, y: sy), mouseButton: .left) {
    d.post(tap: .cghidEventTap)
}
pump(0.3)

for i in 1...18 {
    let t = Double(i) / 18.0
    let p = CGPoint(x: sx + (ex - sx) * t, y: sy + (ey - sy) * t)
    if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                       mouseCursorPosition: p, mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
    pump(0.045)
}

// 拖拽中采样
pump(0.4)
let during = findMarqueeElements()
print("拖拽中：框选元素 \(during.count) 个")
for e in during.prefix(5) {
    print("   role=\(e.role) subrole=\(e.subrole) pos=\(e.pos) size=\(e.size)")
}

if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                   mouseCursorPosition: CGPoint(x: ex, y: ey), mouseButton: .left) {
    u.post(tap: .cghidEventTap)
}
pump(0.7)

let after = findMarqueeElements()
print("拖拽后：框选元素 \(after.count) 个")

if during.count > before.count {
    print("⚠️  拖拽过程中桌面出现了框选矩形")
    exit(2)
} else {
    print("✅ 拖拽过程中桌面没有框选矩形")
    exit(0)
}
