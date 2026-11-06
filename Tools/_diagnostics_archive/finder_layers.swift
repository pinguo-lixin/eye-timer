import Foundation
import ScreenCaptureKit
import AppKit

/// 枚举所有 Finder / Dock 相关窗口的层级，
/// 用来确定挂件应该放在哪一层才能既「在图标之下」又能收到点击。
let sem = DispatchSemaphore(value: 0)

Task {
    // including desktop elements
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

    print("=== 所有低层级窗口（level <= 图标层）===")
    let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
    let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))

    for w in content.windows.sorted(by: { $0.windowLayer < $1.windowLayer }) {
        guard w.windowLayer <= iconLevel else { continue }
        let nm = w.owningApplication?.applicationName ?? "?"
        let bid = w.owningApplication?.bundleIdentifier ?? "?"
        print("  \(nm) [\(bid)] level=\(w.windowLayer) frame=\(w.frame)")
    }

    print("\n=== 常量 ===")
    print("壁纸层 desktopWindow      = \(desktopLevel)")
    print("图标层 desktopIconWindow  = \(iconLevel)")

    print("\n=== EyeTimer ===")
    for w in content.windows {
        let bid = w.owningApplication?.bundleIdentifier ?? ""
        if bid.contains("eyetimer") {
            print("  level=\(w.windowLayer) frame=\(w.frame)")
        }
    }

    sem.signal()
}
sem.wait()
