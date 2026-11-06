import AppKit
import ApplicationServices

/// 确定性检测：Finder 的桌面框选矩形在辅助功能树里是一个**独立元素**
/// （AXGroup / AXUnknown，role 常为 `AXGroup`，subrole 为 `AXUnknown`），
/// 我们可以直接问系统「桌面上现在有没有这个东西」。
///
/// 这比像素比对可靠得多：
///   - 像素比对会被光标、其他 App 窗口干扰；
///   - AX 树直接反映 Finder 内部「正在框选」的状态。
///
/// 同时用 AX 读出 Finder 桌面窗口的**选中项数量** ——
/// 框选进行中时，选中项会是 0，但桌面窗口会有一个额外的选区元素。
///
/// 用法：swift Tools/check_desktop_selection.swift

/// 遍历 Finder 桌面窗口的 AX 子树，找「选区」元素
func findSelectionElements() -> [AXUIElement] {
    let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    guard let finder else { return [] }

    let app = AXUIElementCreateApplication(finder.processIdentifier)

    var windows: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
    guard err == .success, let windowList = windows as? [AXUIElement] else { return [] }

    var results: [AXUIElement] = []

    for window in windowList {
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String) ?? ""
        guard title == "Desktop" else { continue }   // 只看 Finder 桌面窗口

        // 收集整棵子树的 role
        var stack: [AXUIElement] = [window]
        var visited = 0
        while let current = stack.popLast() {
            visited += 1
            if visited > 4000 { break }

            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
            let role = (roleValue as? String) ?? ""

            // 选区在 AX 树里表现为 AXGroup / AXUnknown
            if role == "AXGroup" || role == "AXUnknown" {
                var subroleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subroleValue)
                let subrole = (subroleValue as? String) ?? ""
                if subrole == "AXUnknown" || role == "AXUnknown" {
                    results.append(current)
                }
            }

            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &children) == .success,
               let childList = children as? [AXUIElement] {
                stack.append(contentsOf: childList)
            }
        }
    }
    return results
}

/// 读出桌面窗口里的选中项数量
func desktopSelectionCount() -> Int {
    let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    guard let finder else { return -1 }
    let app = AXUIElementCreateApplication(finder.processIdentifier)

    var windows: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
          let windowList = windows as? [AXUIElement] else { return -1 }

    for window in windowList {
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        guard (titleValue as? String) == "Desktop" else { continue }

        var selected: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSelectedChildrenAttribute as CFString, &selected)
        return (selected as? [AXUIElement])?.count ?? 0
    }
    return -1
}

/// 打印选区元素的属性（用于人工确认）
func describe(_ element: AXUIElement) -> String {
    var roleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
    var subroleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
    var positionValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
    var sizeValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

    let pos = (positionValue as? [Any]) ?? []
    let size = (sizeValue as? [Any]) ?? []
    return "role=\(roleValue as? String ?? "?") subrole=\(subroleValue as? String ?? "?") "
        + "pos=(\(pos.map { "\($0)" }.joined(separator: ","))) "
        + "size=(\(size.map { "\($0)" }.joined(separator: ",")))"
}

print("=== 当前 Finder 桌面状态 ===")
let sel = desktopSelectionCount()
print("桌面选中项数量 = \(sel)")
let elements = findSelectionElements()
print("检测到的选区元素数量 = \(elements.count)")
for e in elements.prefix(10) {
    print("  \(describe(e))")
}

if elements.isEmpty {
    print("\n✅ 桌面上没有框选矩形")
    exit(0)
} else {
    print("\n❌ 桌面上存在框选矩形")
    exit(2)
}
