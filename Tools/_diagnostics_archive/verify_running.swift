import Foundation
import CoreGraphics
import AppKit

// 检查 EyeTimer 的窗口层级与位置
print("=== EyeTimer 窗口（全部层级）===")
if let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
    for w in info {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        guard owner.contains("EyeTimer") else { continue }
        let name = w[kCGWindowName as String] as? String ?? ""
        let level = w["kCGWindowLevel"] as? Int ?? -1
        let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
        let rect = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                          width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
        let onscreen = w["kCGWindowIsOnscreen"] as? Bool ?? false
        print("name=\(name.isEmpty ? "<none>" : name) level=\(level) onscreen=\(onscreen)")
        print("   bounds=(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))")
    }
}

print("\n=== 层级参考 ===")
print("kCGDesktopWindowLevel      =", CGWindowLevelForKey(.desktopWindow))
print("kCGDesktopIconWindowLevel  =", CGWindowLevelForKey(.desktopIconWindow))
print("挂件目标层级 (desktop+10)  =", Int(CGWindowLevelForKey(.desktopWindow)) + 10)
print("kCGFloatingWindowLevel     =", CGWindowLevelForKey(.floatingWindow))
print("kCGScreenSaverWindowLevel  =", CGWindowLevelForKey(.screenSaverWindow))

print("\n=== 进程状态 ===")
let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.eyetimer.app")
for app in running {
    print("pid=\(app.processIdentifier) active=\(app.isActive) terminated=\(app.isTerminated)")
}
if running.isEmpty { print("(未找到运行实例 - 可能 bundle id 不匹配)") }
