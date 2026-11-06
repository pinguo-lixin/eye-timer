import Foundation
import CoreGraphics

/// 把鼠标移动到指定的屏幕坐标（用于测试悬停效果）。
///
/// 用法：swift mouse_to.swift <x> <y>
///
/// 坐标约定：**CoreGraphics / 屏幕图像坐标系**（原点在左上角，y 向下），
/// 与 `screencapture` 输出的 PNG 像素、`SCWindow.frame` 完全一致。
///
/// ⚠️ 不要和 AppKit 的左下角原点混用：
/// AppKit 的 `NSPanel.frame`（原点在左下）需要用
/// `y_appkit = 屏幕高 - (y_top + 高度)` 换算，
/// 否则鼠标会差一整个屏幕高度，点不到挂件。
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift mouse_to.swift <x> <y>   (屏幕坐标：原点在左上)")
    exit(1)
}

let x = Double(args[1])!
let y = Double(args[2])!
let point = CGPoint(x: x, y: y)

CGAssociateMouseAndMouseCursorPosition(1)
CGWarpMouseCursorPosition(point)

// 再合成一个 mouseMoved 事件，确保系统派发 mouseEntered / mouseExited
let src = CGEventSource(stateID: .hidSystemState)
if let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                      mouseCursorPosition: point, mouseButton: .left) {
    move.post(tap: .cghidEventTap)
}

print("鼠标已移动到屏幕坐标 (\(x), \(y))")
