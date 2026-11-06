import Foundation
import CoreGraphics

/// 在屏幕坐标处点击一次。
///
/// 用法：swift click_at.swift <x> <y>
/// 坐标为屏幕坐标（原点在左上，与 screencapture 输出一致）。
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift click_at.swift <x> <y>")
    exit(1)
}
let x = Double(args[1])!
let y = Double(args[2])!

let src = CGEventSource(stateID: .hidSystemState)
let p = CGPoint(x: x, y: y)

CGAssociateMouseAndMouseCursorPosition(1)
CGWarpMouseCursorPosition(p)
Thread.sleep(forTimeInterval: 0.05)

if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                     mouseCursorPosition: p, mouseButton: .left) {
    down.post(tap: .cghidEventTap)
}
Thread.sleep(forTimeInterval: 0.06)
if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                   mouseCursorPosition: p, mouseButton: .left) {
    up.post(tap: .cghidEventTap)
}

print("已点击 (\(x), \(y))")
