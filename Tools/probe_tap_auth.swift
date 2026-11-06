import AppKit
import CoreGraphics
import ApplicationServices

/// ⭐ 授权与启动方式的关系（**诊断「拖拽时桌面画矩形」的关键**）。
///
/// ## 实测结论
///
/// 同一份二进制，只因启动方式不同，辅助功能授权的有效性就不同：
///
/// | 启动方式 | `AXIsProcessTrusted()` | `defaultTap` 事件 tap |
/// |---|---|---|
/// | 直接运行可执行文件（终端 / 脚本） | `true` | ✅ 可创建 |
/// | `open` 双击启动（**用户日常场景**） | `false` | ❌ 返回 nil |
///
/// 也就是说：**用户双击启动 EyeTimer 时，事件 tap 必然不可用**，
/// 只能走「全局监视器 + 事件抵消」的兜底路径。
///
/// 这正是「拖拽时桌面画矩形」在真实使用中依然出现的原因 ——
/// 之前那次 A/B 验证是在终端里直接跑起来的，tap 能用，掩盖了这个问题。
///
/// ## 用法
///
/// ```bash
/// # 编译成独立 .app 后分别用两种方式启动
/// ./probe_tap_auth.app/Contents/MacOS/probe_tap_auth      # 终端直接运行
/// open ./probe_tap_auth.app                              # 双击启动
/// ```
///
/// 两种方式的输出不同，即为复现。

let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
    | (1 << CGEventType.leftMouseUp.rawValue)
    | (1 << CGEventType.leftMouseDragged.rawValue)

print("=== 事件 tap 授权诊断 ===")
print("bundleIdentifier  = \(Bundle.main.bundleIdentifier ?? "(无 —— 脚本运行)")")
print("bundlePath        = \(Bundle.main.bundlePath)")
print("AXIsProcessTrusted = \(AXIsProcessTrusted())")
print("")

func tryTap(_ label: String, _ kind: CGEventTapLocation) {
    let cb: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
    guard let tap = CGEvent.tapCreate(
        tap: kind,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: cb,
        userInfo: nil
    ) else {
        print("  ❌ \(label) → tapCreate 返回 nil")
        return
    }
    print("  ✅ \(label) → tapCreate 成功")
    CGEvent.tapEnable(tap: tap, enable: true)
    CFMachPortInvalidate(tap)
}

func tryListenOnly(_ label: String, _ kind: CGEventTapLocation) {
    let cb: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
    guard let tap = CGEvent.tapCreate(
        tap: kind,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: cb,
        userInfo: nil
    ) else {
        print("  ❌ \(label) → tapCreate 返回 nil")
        return
    }
    print("  ✅ \(label) → tapCreate 成功")
    CGEvent.tapEnable(tap: tap, enable: true)
    CFMachPortInvalidate(tap)
}

print("=== defaultTap（可吞事件 → 彻底消除矩形）===")
tryTap("cgSessionEventTap", .cgSessionEventTap)
tryTap("cghidEventTap", .cghidEventTap)

print("")
print("=== listenOnly（只能观察，实测无授权时收不到事件）===")
tryListenOnly("cgSessionEventTap", .cgSessionEventTap)
tryListenOnly("cghidEventTap", .cghidEventTap)

print("")
if AXIsProcessTrusted() {
    print("→ 已授权：EyeTimer 会走事件 tap 路径，桌面完全不受影响。")
} else {
    print("→ 未授权：EyeTimer 会走兜底路径（补发 mouseUp + 持续抵消）。")
    print("  若要让拖拽完全无感，可在「设置 → 桌面挂件」里申请辅助功能权限。")
}
