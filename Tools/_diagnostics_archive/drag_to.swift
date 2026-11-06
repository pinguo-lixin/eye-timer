import Foundation
import CoreGraphics

/// 模拟一次鼠标拖拽：按下 → 分步移动 → 松开。
///
/// 用法：swift drag_to.swift <fromX> <fromY> <toX> <toY> [steps] [stepDelayMs]
///
/// 坐标为屏幕坐标（原点在左上，与 screencapture 输出一致）。
///
/// 用途：验证挂件拖拽是否「跟手」——
/// 拖完后挂件原点应该 ≈ (起点 + (终点 - 起点))，
/// 而不是抖动、滞后或朝反方向跑。
let args = CommandLine.arguments
guard args.count >= 5 else {
    print("用法: swift drag_to.swift <fromX> <fromY> <toX> <toY> [steps] [delayMs]")
    exit(1)
}

let fromX = Double(args[1])!
let fromY = Double(args[2])!
let toX = Double(args[3])!
let toY = Double(args[4])!
let steps = args.count > 5 ? Int(args[5])! : 24
let delayMs = args.count > 6 ? Int(args[6])! : 12

let src = CGEventSource(stateID: .hidSystemState)

CGAssociateMouseAndMouseCursorPosition(1)
CGWarpMouseCursorPosition(CGPoint(x: fromX, y: fromY))

func post(_ type: CGEventType, _ x: Double, _ y: Double, _ button: CGMouseButton) {
    if let e = CGEvent(mouseEventSource: src, mouseType: type,
                       mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: button) {
        e.post(tap: .cghidEventTap)
    }
}

// 按下
post(.leftMouseDown, fromX, fromY, .left)
Thread.sleep(forTimeInterval: 0.08)

// 分步移动（模拟真实拖拽轨迹）
for i in 1...steps {
    let t = Double(i) / Double(steps)
    let x = fromX + (toX - fromX) * t
    let y = fromY + (toY - fromY) * t
    post(.leftMouseDragged, x, y, .left)
    Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
}

// 松开
post(.leftMouseUp, toX, toY, .left)

print("已模拟拖拽: (\(fromX), \(fromY)) -> (\(toX), \(toY))，共 \(steps) 步")
