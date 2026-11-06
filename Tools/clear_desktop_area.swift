import AppKit
import CoreGraphics

/// 临时把遮挡目标区域的普通 App 窗口**隐藏**，腾出一块干净的桌面。
///
/// ## 为什么需要
///
/// 视觉验证要求被测区域是**裸桌面**。但环境里随时有 VS Code / Edge /
/// WorkBuddy 等窗口铺满屏幕，把桌面盖得严严实实。
///
/// 之前试过：
///   - 切 Space → 那些窗口设了「加入所有空间」，跟不过去
///   - 关闭 App → 会破坏用户的现场
///   - AX 最小化 → 本机终端没有辅助功能授权，读不到窗口
///
/// 用 **`CGWindowListCopyWindowInfo` 拿窗口号 + `NSRunningApplication` 隐藏**
/// —— 两者都不需要辅助功能授权。
///
/// 用法：
///   swift Tools/clear_desktop_area.swift hide <x> <y> <r>   隐藏覆盖该区域的窗口
///   swift Tools/clear_desktop_area.swift restore            还原

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "hide"
let statePath = "/tmp/et_hidden_windows.json"

struct Record: Codable {
    var pid: pid_t
    var name: String
}

/// 目标区域（Quartz 坐标）内的普通 App 窗口
func blockingWindows(in region: CGRect) -> [(pid: pid_t, name: String, layer: Int, rect: CGRect)] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var out: [(pid_t, String, Int, CGRect)] = []
    for w in list {
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard layer >= 0 else { continue }          // 只管普通 App 窗口
        guard let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
        let rect = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                          width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
        guard rect.intersects(region) else { continue }
        let pid = (w[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        out.append((pid, owner, layer, rect))
    }
    return out
}

switch mode {
case "hide":
    guard CommandLine.arguments.count >= 5 else {
        print("用法: clear_desktop_area hide <x> <y> <r>")
        exit(1)
    }
    let cx = Double(CommandLine.arguments[2])!
    let cy = Double(CommandLine.arguments[3])!
    let r = Double(CommandLine.arguments[4])!
    let region = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

    let blocks = blockingWindows(in: region)
    print("覆盖目标区域的窗口 \(blocks.count) 个")

    // 按 App 归组，逐个隐藏
    var hidden: [Record] = []
    var byPID: [pid_t: String] = [:]
    for (pid, name, _, _) in blocks { byPID[pid] = name }

    for (pid, name) in byPID {
        // 不隐藏自己（测试工具本身）
        if name.contains("Terminal") || name.contains("iTerm") { continue }
        guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
        app.hide()
        hidden.append(Record(pid: pid, name: name))
        print("   已隐藏: \(name) (\(pid))")
    }
    let data = try! JSONEncoder().encode(hidden)
    try! data.write(to: URL(fileURLWithPath: statePath))
    print("共隐藏 \(hidden.count) 个 App")

case "restore":
    guard let data = FileManager.default.contents(atPath: statePath),
          let records = try? JSONDecoder().decode([Record].self, from: data) else {
        print("没有需要还原的 App")
        exit(0)
    }
    for rec in records {
        guard let app = NSRunningApplication(processIdentifier: rec.pid) else { continue }
        app.unhide()
        print("   已还原: \(rec.name)")
    }
    try? FileManager.default.removeItem(atPath: statePath)
    print("共还原 \(records.count) 个 App")

default:
    print("用法: clear_desktop_area <hide x y r | restore>")
    exit(1)
}
