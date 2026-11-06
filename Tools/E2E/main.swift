import Foundation
import Combine

/// 端到端逻辑测试：直接复用应用的核心引擎代码，验证 20-20-20 状态机。
///
/// 用极短时长跑完整个周期：
///   专注 → 自动进入短休息 → 休息结束 → 回到专注
/// 同时验证：长休息间隔、跳过、暂停/继续、统计累计、时间戳准确性。

// MARK: - 迷你测试框架

var failures: [String] = []
var checks = 0

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if condition {
        print("  ✅ \(message)")
    } else {
        print("  ❌ \(message)")
        failures.append(message)
    }
}

func section(_ title: String) {
    print("\n=== \(title) ===")
}

/// 等待指定秒数，同时泵送主 RunLoop —— 真实 App 跑在主 RunLoop 上，
/// Timer 依赖 RunLoop 才会触发。
func wait(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

// MARK: - 准备

// TimerEngine 依赖真实的 AppSettings 类型。
// 这里直接用 AppSettings.shared，并临时改写它的时长，
// 测试结束后恢复默认值，避免污染用户的真实配置。
let settings = AppSettings.shared
let stats = StatsStore.shared

// 备份原始配置
let savedFocus = settings.focusSeconds
let savedShort = settings.shortBreakSeconds
let savedLong = settings.longBreakSeconds
let savedInterval = settings.longBreakInterval

// 测试用的短时长
settings.focusSeconds = 2
settings.shortBreakSeconds = 2
settings.longBreakSeconds = 3
settings.longBreakInterval = 2

let engine = TimerEngine(settings: settings, stats: stats)

var phaseLog: [TimerPhase] = []
var focusCompletions = 0
var breakCompletions = 0
engine.onPhaseChange = { phase in phaseLog.append(phase) }
engine.onFocusCycleComplete = { focusCompletions += 1 }
engine.onBreakComplete = { breakCompletions += 1 }

// MARK: - 阶段机测试

section("阶段推进：专注 → 短休息 → 专注")

check(engine.state == .idle, "初始状态为 idle")
check(engine.phase == .focus, "初始阶段为 focus")

engine.start()
check(engine.state == .running, "start() 后状态为 running")
check(engine.totalSeconds == 2, "专注总时长 = 2 秒")
check(engine.remainingSeconds == 2, "专注剩余 = 2 秒")

// 专注在 t=2.0 结束；等到 t=2.5 时处于 shortBreak
wait(2.5)
check(focusCompletions == 1, "专注完成回调触发 1 次")
check(engine.phase == .shortBreak, "专注结束后进入 shortBreak（未达长休息间隔）")
check(engine.state == .resting, "休息阶段状态为 resting")
check(phaseLog.contains(.shortBreak), "阶段回调记录了 shortBreak")

// 短休息在 t=4.0 结束；等到 t=4.5 时应已回到 focus（且新专注未结束）
wait(2.0)
check(breakCompletions == 1, "休息完成回调触发 1 次")
check(engine.phase == .focus, "休息结束后回到 focus")
check(engine.state == .running, "休息结束后自动开始新的专注")

// MARK: -

section("长休息间隔：第 2 个专注周期后应进入 longBreak")

engine.stopAll()
settings.longBreakInterval = 2
phaseLog.removeAll()

engine.start()
wait(2.5)   // t=2.5：第 1 个专注已结束，处于 shortBreak
check(engine.phase == .shortBreak, "第 1 个专注后是 shortBreak")

wait(2.0)   // t=4.5：短休息已结束，回到 focus
check(engine.phase == .focus, "短休息后回到 focus")

wait(2.0)   // t=6.5：第 2 个专注已结束，应进入 longBreak
check(engine.phase == .longBreak, "第 2 个专注后是 longBreak（达到间隔）")
check(engine.totalSeconds == 3, "长休息时长 = 3 秒")

// MARK: -

section("暂停 / 继续")

engine.stopAll()
settings.focusSeconds = 60      // 给足时间，避免测试期间周期完成
engine.start()
wait(1.0)
let beforePause = engine.remainingSeconds
engine.pause()
check(engine.state == .paused, "pause() 后状态为 paused")
check(engine.remainingSeconds == beforePause, "暂停时剩余秒数被冻结")

wait(1.5)
check(engine.remainingSeconds == beforePause, "暂停期间倒计时不推进")

engine.resume()
check(engine.state == .running, "resume() 后状态为 running")
wait(1.6)
check(engine.remainingSeconds < beforePause, "继续后倒计时恢复推进")

// MARK: -

section("跳过当前阶段")

engine.stopAll()
settings.focusSeconds = 60
let cyclesBefore = engine.completedFocusCycles
engine.start()
wait(0.6)
engine.skip()
check(engine.phase == .shortBreak, "skip() 从专注跳到休息")
check(engine.completedFocusCycles == cyclesBefore, "跳过的专注不计入完成数")

engine.skip()
check(engine.phase == .focus, "skip() 从休息跳回专注")

// MARK: -

section("系统休眠后的时间准确性（绝对时间戳）")

engine.stopAll()
settings.focusSeconds = 30
engine.start()
let r1 = engine.remainingSeconds
wait(1.2)
let r2 = engine.remainingSeconds
check(r1 - r2 == 1 || r1 - r2 == 2, "剩余时间随真实时间单调递减 (\(r1) → \(r2))")
check(r2 <= 30, "剩余时间不超过总时长")

// 模拟「主线程被阻塞 5 秒」—— 计算属性仍应返回真实剩余值
let blocked = engine.remainingSeconds
let deadline = Date().addingTimeInterval(5)
while Date() < deadline { /* 故意阻塞主线程 */ }
let afterBlock = engine.remainingSeconds
check(afterBlock < blocked, "主线程阻塞后剩余时间仍然正确推进 (\(blocked) → \(afterBlock))")
check(afterBlock <= 0 || afterBlock < blocked - 3, "阻塞期间确实流逝了时间")

// MARK: -

section("统计累计")

let before = stats.today.focusCycles
engine.stopAll()
settings.focusSeconds = 2
engine.start()
wait(2.5)
check(stats.today.focusCycles == before + 1, "完成一次专注后今日计数 +1")
check(stats.today.focusSeconds > 0, "今日专注秒数已累计")

// MARK: -

section("剩余时间格式化")

engine.stopAll()
settings.focusSeconds = 125
engine.start()
check(engine.remainingText == "02:05" || engine.remainingText == "02:04",
      "125 秒格式化为 \(engine.remainingText)")

engine.stopAll()

// MARK: -

section("挂件融入程度（透明度）设置")

let savedOpacity = settings.widgetOpacity
let savedHover = settings.widgetHoverHighlight

settings.widgetOpacity = 0.4
check(abs(settings.widgetOpacity - 0.4) < 0.0001, "透明度可设置为 0.4")
settings.widgetOpacity = 1.0
check(abs(settings.widgetOpacity - 1.0) < 0.0001, "透明度可设置为 1.0（完全不透明）")
settings.widgetOpacity = 0.10
check(abs(settings.widgetOpacity - 0.10) < 0.0001, "透明度可设置到 0.10（几乎完全融入）")

settings.widgetHoverHighlight = true
check(settings.widgetHoverHighlight, "悬停恢复不透明开关可开启")
settings.widgetHoverHighlight = false
check(!settings.widgetHoverHighlight, "悬停恢复不透明开关可关闭")

settings.widgetOpacity = savedOpacity
settings.widgetHoverHighlight = savedHover

// MARK: -

section("配置持久化与向后兼容")

// 写入一份「旧版本」配置：不含透明度 / 悬停字段
let legacyJSON = """
{"focusSeconds":1500,"shortBreakSeconds":20,"longBreakSeconds":300,\
"longBreakInterval":4,"autoStartNextPhase":false,"autoReturnToFocus":true,\
"reminders":{"showOverlay":true,"showNotification":true,"playSound":true,"speak":false},\
"sound":"glass","gazeDistanceMeters":6,"layerMode":"desktop","widgetStyle":"ring",\
"widgetX":0.5,"widgetY":0.5,"widgetScale":1.0,"showWidgetText":true,\
"showMenuBarSeconds":true,"widgetClickThrough":false,\
"launchAtLogin":false,"launchMinimized":true}
"""

let legacyData = legacyJSON.data(using: .utf8)!
let legacySnapshot = try JSONDecoder().decode(AppSettingsTestAccess.Snapshot.self, from: legacyData)
check(legacySnapshot.widgetOpacity == 0.4,
      "旧配置缺失透明度字段时回退到默认 0.4（实测 \(legacySnapshot.widgetOpacity)）")
check(legacySnapshot.widgetHoverHighlight == true,
      "旧配置缺失悬停字段时回退到默认 true（实测 \(legacySnapshot.widgetHoverHighlight)）")
check(legacySnapshot.focusSeconds == 1500, "旧配置的既有字段被正确读出")
check(legacySnapshot.widgetX == 0.5, "旧配置的挂件位置被正确读出")

section("主题持久化与样式迁移")
check(legacySnapshot.widgetTheme == .mist, "旧配置缺少主题时回退雾蓝")
let legacyStyles: [(String, WidgetStyle)] = [("ring", .halo), ("pill", .monolith), ("text", .paper)]
for (raw, expected) in legacyStyles {
    let data = "{\"widgetStyle\":\"\(raw)\"}".data(using: .utf8)!
    let snapshot = try JSONDecoder().decode(AppSettingsTestAccess.Snapshot.self, from: data)
    check(snapshot.widgetStyle == expected, "旧样式 \(raw) 迁移到 \(expected.title)")
}
for theme in WidgetTheme.allCases {
    var snapshot = legacySnapshot
    snapshot.widgetTheme = theme
    snapshot.widgetStyle = .paper
    let data = try JSONEncoder().encode(snapshot)
    let restored = try JSONDecoder().decode(AppSettingsTestAccess.Snapshot.self, from: data)
    check(restored.widgetTheme == theme && restored.widgetStyle == .paper,
          "\(theme.title) 与 Paper 设置编码往返保留")
}
let invalidTheme = "{\"widgetTheme\":\"unknown-future-theme\",\"focusSeconds\":1500}".data(using: .utf8)!
let recovered = try JSONDecoder().decode(AppSettingsTestAccess.Snapshot.self, from: invalidTheme)
check(recovered.widgetTheme == .mist && recovered.focusSeconds == 1500,
      "未知主题回退且不丢失其它设置")

section("刷新频率：运行时每秒更新，暂停与空闲停止更新")
engine.stopAll()
settings.focusSeconds = 60
engine.start()
var refreshes = 0
let observation = engine.objectWillChange.sink { refreshes += 1 }
wait(2.25)
check(refreshes == 2, "2.25 秒仅发布 2 次倒计时更新（原实现为 9 次）")
check(engine.remainingSeconds == 58, "降低刷新频率后秒数仍正确")
engine.pause()
refreshes = 0
wait(1.2)
check(refreshes == 0, "暂停期间没有周期性界面更新")
engine.resume()
refreshes = 0
wait(1.2)
check(refreshes == 1 && engine.remainingSeconds == 57, "恢复后重新对齐秒数更新")
engine.stopAll()
refreshes = 0
wait(1.2)
check(refreshes == 0, "空闲期间没有周期性界面更新")
observation.cancel()

// 恢复用户配置
settings.focusSeconds = savedFocus
settings.shortBreakSeconds = savedShort
settings.longBreakSeconds = savedLong
settings.longBreakInterval = savedInterval

// MARK: - 结果

print("\n" + String(repeating: "=", count: 52))
if failures.isEmpty {
    print("全部通过：\(checks) 项检查 ✅")
    exit(0)
} else {
    print("失败 \(failures.count)/\(checks) 项：")
    for f in failures { print("  - \(f)") }
    exit(1)
}
