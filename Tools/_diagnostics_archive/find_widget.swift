import Foundation
import ScreenCaptureKit

/// 打印 EyeTimer 挂件窗口的 frame 与层级。
///
/// 用法：swift Tools/find_widget.swift
let sem = DispatchSemaphore(value: 0)
Task {
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    for w in content.windows {
        let bid = w.owningApplication?.bundleIdentifier ?? ""
        if bid.contains("eyetimer") {
            print("frame=(x: \(w.frame.origin.x), y: \(w.frame.origin.y), w: \(w.frame.width), h: \(w.frame.height)) level=\(w.windowLayer) onScreen=\(w.isOnScreen)")
        }
    }
    sem.signal()
}
sem.wait()
