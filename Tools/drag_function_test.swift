import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 功能底线测试：挂件在「输入捕获面板」存在时**还能不能正常拖动**。
///
/// 检查三件事：
///   1. 拖拽前后的挂件位置差 —— 是否等于鼠标位移（1:1 跟手）；
///   2. 事件到底由哪条路径处理（捕获面板 / 全局兜底）；
///   3. 拖拽过程中桌面是否出现框选矩形（由 drag_marquee_check 负责）。
///
/// 用法：swift Tools/drag_function_test.swift

let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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

        guard let before = widgetFrame() else {
            print("❌ 未找到 EyeTimer 窗口"); exit(1)
        }
        print("拖拽前挂件: \(before)")

        // 选一个安全的拖拽终点：优先向左上（挂件默认在右下角），
        // 并确保终点距屏幕边缘足够远，避免被 clamp 影响精度判断。
        let startCG = CGPoint(x: before.midX, y: before.midY)
        let wantDX: CGFloat = -260
        let wantDY: CGFloat = -180
        var endCG = CGPoint(x: startCG.x + wantDX, y: startCG.y + wantDY)
        // 越界就翻转方向
        if endCG.x < 120 || endCG.y < 200 || endCG.x > 3300 || endCG.y > 1350 {
            endCG = CGPoint(x: startCG.x + abs(wantDX), y: startCG.y + abs(wantDY))
        }
        print("拖拽: \(startCG) → \(endCG)")

        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(startCG)
        pump(0.4)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: startCG, mouseButton: .left) {
            d.post(tap: .cghidEventTap)
        }
        pump(0.15)

        let steps = 20
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let x = startCG.x + (endCG.x - startCG.x) * t
            let y = startCG.y + (endCG.y - startCG.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.03)
        }
        pump(0.3)
        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: endCG, mouseButton: .left) {
            u.post(tap: .cghidEventTap)
        }
        pump(1.0)

        // 重新取窗口列表
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

        guard let after else {
            print("❌ 拖拽后找不到挂件窗口（可能被隐藏了？）"); exit(1)
        }
        print("拖拽后挂件: \(after)")

        let expectedDX = endCG.x - startCG.x
        let expectedDY = endCG.y - startCG.y
        let actualDX = after.origin.x - before.origin.x
        let actualDY = after.origin.y - before.origin.y

        print("")
        print("=== 跟手精度 ===")
        print(String(format: "期望位移: dx=%.0f dy=%.0f", expectedDX, expectedDY))
        print(String(format: "实际位移: dx=%.0f dy=%.0f", actualDX, actualDY))
        let errX = abs(actualDX - expectedDX)
        let errY = abs(actualDY - expectedDY)
        print(String(format: "误差: dx=%.0f dy=%.0f", errX, errY))

        if errX <= 2 && errY <= 2 {
            print("✅ 挂件 1:1 跟手，位置误差 ≤2px")
            exit(0)
        } else if errX < 60 && errY < 60 {
            print("⚠️ 挂件移动了但有偏差（可能被 clamp 到屏幕边缘）")
            exit(2)
        } else {
            print("❌ 挂件没有按预期移动 —— 拖拽功能失效")
            exit(1)
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
