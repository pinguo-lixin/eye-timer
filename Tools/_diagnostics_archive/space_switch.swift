import AppKit
import CoreGraphics

/// 切换到另一个「桌面空间」（Space）。
///
/// ## 为什么需要
///
/// 视觉验证要求被测区域是**裸桌面**。但环境里经常有别的 App 窗口
/// （VS Code / Edge / WorkBuddy…）铺满屏幕，把桌面完全盖住。
///
/// macOS 的每个 App 窗口只属于**某个 Space**，所以切到另一个 Space
/// 就能得到一块干干净净的桌面 —— 比去关别人的窗口安全得多，也不破坏现场。
///
/// 用法：swift Tools/space_switch.swift <方向: -1 或 1>

let dir = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 1 : 1
let src = CGEventSource(stateID: .hidSystemState)

func pump(_ s: Double) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

let ctrl = CGEvent(keyboardEventSource: src, virtualKey: 0x3B, keyDown: true)   // Control
let arrow = CGEvent(keyboardEventSource: src, virtualKey: dir < 0 ? 0x7B : 0x7C, keyDown: true) // ←/→
arrow?.flags = .maskControl

ctrl?.post(tap: .cghidEventTap)
arrow?.post(tap: .cghidEventTap)
pump(1.2)

print("已请求切换 Space（方向 \(dir)）")
exit(0)
