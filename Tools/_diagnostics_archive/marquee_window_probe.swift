import AppKit
import CoreGraphics

/// 框选矩形探针：**用窗口列表差异**来检测。
///
/// ## 为什么不用像素比对
///
/// 像素比对要求被测区域是**裸桌面**；一旦有别的 App 窗口弹过来覆盖，
/// 截图里拍到的是别人的界面，结论直接作废（之前踩过好几次）。
///
/// ## 窗口列表法
///
/// macOS 的桌面框选矩形是 Finder 桌面窗口自己画的，
/// 但系统里可能会多出一个专门的「选择框」窗口。
/// 这个探针在拖拽前后各拍一次窗口列表，**差集**里多出来的窗口就是它。
///
/// 好处：完全不依赖屏幕上有没有被别的窗口覆盖。
///
/// 用法：swift Tools/marquee_window_probe.swift <标签> <起点x> <起点y> <终点x> <终点y>

let tag = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "probe"
guard CommandLine.arguments.count >= 6 else {
    print("用法: marquee_window_probe <标签> <sx> <sy> <ex> <ey>")
    exit(1)
}
let sx = Double(CommandLine.arguments[2])!
let sy = Double(CommandLine.arguments[3])!
let ex = Double(CommandLine.arguments[4])!
let ey = Double(CommandLine.arguments[5])!

let src = CGEventSource(stateID: .hidSystemState)

func pump(_ s: Double) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 窗口快照：(窗口号, 层, 名称, 位置, 尺寸)
func snapshot() -> [String: String] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return [:]
    }
    var out: [String: String] = [:]
    for w in list {
        guard let num = w[kCGWindowNumber as String] as? Int else { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let name = (w[kCGWindowName as String] as? String) ?? "(无名)"
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let rect = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                          width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
        out["\(num)"] = "\(owner)|\(name)|layer=\(layer)|\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
    }
    return out
}

let before = snapshot()
print("拖拽前窗口数: \(before.count)")

// 真实拖拽，中途停住
let start = CGPoint(x: sx, y: sy)
let end = CGPoint(x: ex, y: ey)
CGAssociateMouseAndMouseCursorPosition(1)
CGWarpMouseCursorPosition(start)
pump(0.7)
if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                  mouseCursorPosition: start, mouseButton: .left) {
    d.post(tap: .cghidEventTap)
}
pump(0.3)
for i in 1...18 {
    let t = Double(i) / 18.0
    let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                       mouseCursorPosition: p, mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
    pump(0.045)
}
pump(0.5)

let during = snapshot()
print("拖拽中窗口数: \(during.count)")

let added = during.filter { before[$0.key] == nil }
let removed = before.filter { during[$0.key] == nil }

if added.isEmpty {
    print("✅ 没有新增窗口")
} else {
    print("⚠️  新增 \(added.count) 个窗口:")
    for (num, desc) in added.sorted(by: { $0.key < $1.key }) {
        print("   #\(num)  \(desc)")
    }
}
if !removed.isEmpty {
    print("   (消失 \(removed.count) 个)")
}

// 收尾
if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                   mouseCursorPosition: end, mouseButton: .left) {
    u.post(tap: .cghidEventTap)
}
pump(0.6)
print("── \(tag) 完成 ──")
exit(0)
