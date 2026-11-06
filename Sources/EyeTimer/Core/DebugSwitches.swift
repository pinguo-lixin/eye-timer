import Foundation

/// 诊断开关。
///
/// ## 用途
///
/// 这些开关**只为自动化验证服务**，正常使用时全部关闭（默认值），
/// 不会影响用户的任何体验。
///
/// | 环境变量 | 作用 |
/// |---|---|
/// | `EYETIMER_FORCE_FALLBACK=1` | 强制走「无辅助功能授权」的兜底输入路径（即使 tap 能挂上） |
/// | `EYETIMER_DISABLE_MARQUEE_FIX=1` | 关掉「补发 mouseUp 取消桌面框选」——用来**复现**修复前那个蓝色矩形 |
///
/// 两者配合可以稳定复现修复前的行为，做 A/B 对照验证：
///
/// ```bash
/// # 对照组：应当复现蓝色矩形
/// EYETIMER_FORCE_FALLBACK=1 EYETIMER_DISABLE_MARQUEE_FIX=1 EyeTimer
///
/// # 实验组：应当没有矩形
/// EYETIMER_FORCE_FALLBACK=1 EyeTimer
/// ```
enum DebugSwitches {

    /// 强制使用兜底输入路径（跳过事件 tap）
    static var forceFallbackPath: Bool {
        env("EYETIMER_FORCE_FALLBACK") == "1"
    }

    /// 关掉「补发 mouseUp」——用于复现修复前的桌面框选矩形
    static var disableMarqueeFix: Bool {
        env("EYETIMER_DISABLE_MARQUEE_FIX") == "1"
    }

    private static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}
