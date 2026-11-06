import AppKit
import ApplicationServices

/// 打印 Finder 桌面窗口的辅助功能树结构，用于确定「框选矩形」在 AX 树里长什么样。
///
/// 用法：swift Tools/dump_ax_desktop.swift

let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
guard let finder else { print("❌ Finder 未运行"); exit(1) }
let app = AXUIElementCreateApplication(finder.processIdentifier)

var windowsValue: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
      let windows = windowsValue as? [AXUIElement] else {
    print("❌ 读不到窗口列表"); exit(1)
}

print("Finder 窗口数 = \(windows.count)\n")

for (i, window) in windows.enumerated() {
    var titleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
    var roleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
    var subroleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
    var positionValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
    var sizeValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

    let pos = (positionValue as? [Any]) ?? []
    let size = (sizeValue as? [Any]) ?? []
    print("窗口[\(i)] title=\"\(titleValue as? String ?? "")\" "
          + "role=\(roleValue as? String ?? "?") subrole=\(subroleValue as? String ?? "?") "
          + "pos=(\(pos.map { "\($0)" }.joined(separator: ","))) "
          + "size=(\(size.map { "\($0)" }.joined(separator: ",")))")
}

print("\n=== 桌面窗口的子元素（前 3 层）===")
for window in windows {
    var titleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
    let title = titleValue as? String ?? ""
    guard title.contains("Desktop") || title == "桌面" || title.isEmpty else { continue }

    print("\n▸ 窗口 title=\"\(title)\"")
    func dump(_ el: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleValue)
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleValue)
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleValue)
        let indent = String(repeating: "  ", count: depth)
        print("\(indent)- \(roleValue as? String ?? "?")/\(subroleValue as? String ?? "?") \"\(titleValue as? String ?? "")\"")

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return }
        for c in children.prefix(12) {
            dump(c, depth: depth + 1, maxDepth: maxDepth)
        }
    }
    dump(window, depth: 1, maxDepth: 2)
}
