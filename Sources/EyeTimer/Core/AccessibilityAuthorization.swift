import AppKit
import ApplicationServices

/// 辅助功能（Accessibility）授权状态。
///
/// ## 为什么需要它
///
/// 挂件位于**桌面图标层之下**（`kCGDesktopIconWindowLevel - 1`），
/// 这是「融进桌面」观感的前提 —— 桌面图标会盖在挂件上面。
///
/// 但代价是：**该层级的窗口完全不参与系统的鼠标命中测试**。
/// 点击必然穿透给 Finder 的桌面窗口 → Finder 进入框选模式 → 拖动时画出蓝色矩形。
///
/// 能真正消除矩形的办法只有一个：**在事件层吞掉这次按下**，让 Finder 从未收到。
/// 而「吞掉事件」需要 `CGEvent.tapCreate` 创建一个 **defaultTap** ——
/// 这要求 App 拥有「辅助功能」授权。
///
/// ## ⚠️ 一个容易踩的坑：启动方式决定授权是否有效
///
/// 实测（`Tools/probe_tap_auth.swift`）：
///
/// | 启动方式 | `AXIsProcessTrusted()` | defaultTap |
/// |---|---|---|
/// | 直接运行可执行文件（终端/脚本启动） | `true`（继承「责任进程」的授权） | ✅ 可创建 |
/// | `open` 双击启动（用户日常场景） | `false` | ❌ 返回 nil |
///
/// 也就是说：**用户双击启动时，事件 tap 必然不可用**。
/// 这正是「拖拽时桌面画矩形」在真实使用中依然出现的原因。
///
/// 所以本类除了查询状态，还要负责：
///  1. 主动弹出系统的授权引导（用户点一次「允许」即可）；
///  2. 在授权后**立即**重建事件 tap，让拖拽路径切回「干净模式」。
enum AccessibilityAuthorization {

    /// 当前是否已获得辅助功能授权。
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统的「辅助功能」授权提示。
    ///
    /// macOS 会弹出一个「XX 想要控制此电脑」的系统对话框，
    /// 用户点「打开系统设置」并勾选后即可生效。
    ///
    /// - Returns: 调用瞬间的授权状态（用户授权是异步的，通常仍是 false）
    @discardableResult
    static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 打开「系统设置 → 隐私与安全性 → 辅助功能」面板。
    ///
    /// 系统提示框只有「打开系统设置」一个按钮，但用户可能直接关掉，
    /// 因此这里也提供直接跳转的入口。
    static func openSystemSettings() {
        // 「隐私与安全性 → 辅助功能」的深链
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// 授权状态的文字描述（用于设置界面提示）。
    static var statusDescription: String {
        isTrusted
            ? "已授权 —— 拖拽使用事件 tap 直通，不会影响桌面。"
            : "未授权 —— 拖拽使用兼容模式，自动取消桌面框选。"
    }
}
