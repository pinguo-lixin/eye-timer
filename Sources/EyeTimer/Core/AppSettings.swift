import Foundation
import Combine

/// 用户配置，持久化到 UserDefaults。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// 所有配置项的默认值。
    ///
    /// 单独抽出来有两个用途：
    ///  1. 首次启动时的初始值；
    ///  2. 反序列化旧版本配置时缺失字段的兜底（保证升级不丢设置）。
    enum Defaults {
        static let focusSeconds = 20 * 60
        static let shortBreakSeconds = 20
        static let longBreakSeconds = 5 * 60
        static let longBreakInterval = 4
        static let autoStartNextPhase = false
        static let autoReturnToFocus = true
        static let gazeDistanceMeters = 6
        static let layerMode = WidgetLayerMode.desktop
        static let widgetStyle = WidgetStyle.halo
        static let widgetTheme = WidgetTheme.mist
        static let widgetX = 0.88
        static let widgetY = 0.12
        static let widgetScale = 1.0
        static let showWidgetText = true
        static let showMenuBarSeconds = true
        static let widgetClickThrough = false
        /// 挂件融入桌面的透明度：1 = 完全不透明，0.15 = 几乎融进壁纸
        static let widgetOpacity = 0.4
        /// 鼠标指向挂件时是否恢复不透明
        static let widgetHoverHighlight = true
        static let launchAtLogin = false
        static let launchMinimized = true
    }

    private let defaults = UserDefaults.standard
    private let key = "com.eyetimer.settings.v1"

    // MARK: - 时长（秒）

    /// 专注时长，默认 20 分钟（20-20-20 法则的「20」）
    @Published var focusSeconds: Int {
        didSet { persist() }
    }
    /// 短休息时长，默认 20 秒
    @Published var shortBreakSeconds: Int {
        didSet { persist() }
    }
    /// 长休息时长，默认 5 分钟
    @Published var longBreakSeconds: Int {
        didSet { persist() }
    }
    /// 每多少个专注周期后进入一次长休息
    @Published var longBreakInterval: Int {
        didSet { persist() }
    }

    // MARK: - 行为

    /// 是否自动开始下一阶段
    @Published var autoStartNextPhase: Bool {
        didSet { persist() }
    }
    /// 休息结束后是否自动回到专注
    @Published var autoReturnToFocus: Bool {
        didSet { persist() }
    }
    /// 提醒方式
    @Published var reminders: ReminderOptions {
        didSet { persist() }
    }
    /// 提示音
    @Published var sound: SoundChoice {
        didSet { persist() }
    }
    /// 引导视线的距离（米），用于提示文案
    @Published var gazeDistanceMeters: Int {
        didSet { persist() }
    }

    // MARK: - 挂件

    @Published var layerMode: WidgetLayerMode {
        didSet { persist() }
    }
    @Published var widgetStyle: WidgetStyle {
        didSet { persist() }
    }
    @Published var widgetTheme: WidgetTheme {
        didSet { persist() }
    }
    /// 挂件在屏幕上的归一化位置（0...1），跨显示器保持
    @Published var widgetX: Double {
        didSet { persist() }
    }
    @Published var widgetY: Double {
        didSet { persist() }
    }
    /// 挂件缩放
    @Published var widgetScale: Double {
        didSet { persist() }
    }
    /// 挂件是否显示文字
    @Published var showWidgetText: Bool {
        didSet { persist() }
    }
    /// 是否在菜单栏显示剩余时间
    @Published var showMenuBarSeconds: Bool {
        didSet { persist() }
    }
    /// 挂件是否点击穿透（不影响点击下面的桌面图标）
    @Published var widgetClickThrough: Bool {
        didSet { persist() }
    }
    /// 挂件融入桌面的透明度（0.15...1.0）。越低越透明，越容易「融进」壁纸。
    @Published var widgetOpacity: Double {
        didSet { persist() }
    }
    /// 鼠标指向挂件时是否恢复不透明
    @Published var widgetHoverHighlight: Bool {
        didSet { persist() }
    }

    // MARK: - 统计

    @Published var launchAtLogin: Bool {
        didSet { persist() }
    }
    @Published var launchMinimized: Bool {
        didSet { persist() }
    }

    private init() {
        // 读取已保存的配置；字段缺失时逐项回退到默认值（向后兼容）
        let snapshot = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            ?? Snapshot()

        focusSeconds = snapshot.focusSeconds
        shortBreakSeconds = snapshot.shortBreakSeconds
        longBreakSeconds = snapshot.longBreakSeconds
        longBreakInterval = snapshot.longBreakInterval
        autoStartNextPhase = snapshot.autoStartNextPhase
        autoReturnToFocus = snapshot.autoReturnToFocus
        reminders = snapshot.reminders
        sound = snapshot.sound
        gazeDistanceMeters = snapshot.gazeDistanceMeters
        layerMode = snapshot.layerMode
        widgetStyle = snapshot.widgetStyle
        widgetTheme = snapshot.widgetTheme
        widgetX = snapshot.widgetX
        widgetY = snapshot.widgetY
        widgetScale = snapshot.widgetScale
        showWidgetText = snapshot.showWidgetText
        showMenuBarSeconds = snapshot.showMenuBarSeconds
        widgetClickThrough = snapshot.widgetClickThrough
        widgetOpacity = snapshot.widgetOpacity
        widgetHoverHighlight = snapshot.widgetHoverHighlight
        launchAtLogin = snapshot.launchAtLogin
        launchMinimized = snapshot.launchMinimized
    }

    /// 持久化用的快照。
    ///
    /// 每个字段都有默认值，且 `init(from:)` 对缺失字段逐项兜底 ——
    /// 这样以后新增配置项时，老用户升级不会因为 JSON 缺字段而丢掉全部设置。
    struct Snapshot: Codable {
        var focusSeconds: Int = Defaults.focusSeconds
        var shortBreakSeconds: Int = Defaults.shortBreakSeconds
        var longBreakSeconds: Int = Defaults.longBreakSeconds
        var longBreakInterval: Int = Defaults.longBreakInterval
        var autoStartNextPhase: Bool = Defaults.autoStartNextPhase
        var autoReturnToFocus: Bool = Defaults.autoReturnToFocus
        var reminders: ReminderOptions = ReminderOptions()
        var sound: SoundChoice = .glass
        var gazeDistanceMeters: Int = Defaults.gazeDistanceMeters
        var layerMode: WidgetLayerMode = Defaults.layerMode
        var widgetStyle: WidgetStyle = Defaults.widgetStyle
        var widgetTheme: WidgetTheme = Defaults.widgetTheme
        var widgetX: Double = Defaults.widgetX
        var widgetY: Double = Defaults.widgetY
        var widgetScale: Double = Defaults.widgetScale
        var showWidgetText: Bool = Defaults.showWidgetText
        var showMenuBarSeconds: Bool = Defaults.showMenuBarSeconds
        var widgetClickThrough: Bool = Defaults.widgetClickThrough
        var widgetOpacity: Double = Defaults.widgetOpacity
        var widgetHoverHighlight: Bool = Defaults.widgetHoverHighlight
        var launchAtLogin: Bool = Defaults.launchAtLogin
        var launchMinimized: Bool = Defaults.launchMinimized

        init() {}

        init(focusSeconds: Int,
             shortBreakSeconds: Int,
             longBreakSeconds: Int,
             longBreakInterval: Int,
             autoStartNextPhase: Bool,
             autoReturnToFocus: Bool,
             reminders: ReminderOptions,
             sound: SoundChoice,
             gazeDistanceMeters: Int,
             layerMode: WidgetLayerMode,
             widgetStyle: WidgetStyle,
             widgetTheme: WidgetTheme,
             widgetX: Double,
             widgetY: Double,
             widgetScale: Double,
             showWidgetText: Bool,
             showMenuBarSeconds: Bool,
             widgetClickThrough: Bool,
             widgetOpacity: Double,
             widgetHoverHighlight: Bool,
             launchAtLogin: Bool,
             launchMinimized: Bool) {
            self.focusSeconds = focusSeconds
            self.shortBreakSeconds = shortBreakSeconds
            self.longBreakSeconds = longBreakSeconds
            self.longBreakInterval = longBreakInterval
            self.autoStartNextPhase = autoStartNextPhase
            self.autoReturnToFocus = autoReturnToFocus
            self.reminders = reminders
            self.sound = sound
            self.gazeDistanceMeters = gazeDistanceMeters
            self.layerMode = layerMode
            self.widgetStyle = widgetStyle
            self.widgetTheme = widgetTheme
            self.widgetX = widgetX
            self.widgetY = widgetY
            self.widgetScale = widgetScale
            self.showWidgetText = showWidgetText
            self.showMenuBarSeconds = showMenuBarSeconds
            self.widgetClickThrough = widgetClickThrough
            self.widgetOpacity = widgetOpacity
            self.widgetHoverHighlight = widgetHoverHighlight
            self.launchAtLogin = launchAtLogin
            self.launchMinimized = launchMinimized
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            focusSeconds = c.value(.focusSeconds, Defaults.focusSeconds)
            shortBreakSeconds = c.value(.shortBreakSeconds, Defaults.shortBreakSeconds)
            longBreakSeconds = c.value(.longBreakSeconds, Defaults.longBreakSeconds)
            longBreakInterval = c.value(.longBreakInterval, Defaults.longBreakInterval)
            autoStartNextPhase = c.value(.autoStartNextPhase, Defaults.autoStartNextPhase)
            autoReturnToFocus = c.value(.autoReturnToFocus, Defaults.autoReturnToFocus)
            reminders = c.value(.reminders, ReminderOptions())
            sound = c.value(.sound, SoundChoice.glass)
            gazeDistanceMeters = c.value(.gazeDistanceMeters, Defaults.gazeDistanceMeters)
            layerMode = c.value(.layerMode, Defaults.layerMode)
            widgetStyle = c.value(.widgetStyle, Defaults.widgetStyle)
            widgetTheme = c.value(.widgetTheme, Defaults.widgetTheme)
            widgetX = c.value(.widgetX, Defaults.widgetX)
            widgetY = c.value(.widgetY, Defaults.widgetY)
            widgetScale = c.value(.widgetScale, Defaults.widgetScale)
            showWidgetText = c.value(.showWidgetText, Defaults.showWidgetText)
            showMenuBarSeconds = c.value(.showMenuBarSeconds, Defaults.showMenuBarSeconds)
            widgetClickThrough = c.value(.widgetClickThrough, Defaults.widgetClickThrough)
            widgetOpacity = c.value(.widgetOpacity, Defaults.widgetOpacity)
            widgetHoverHighlight = c.value(.widgetHoverHighlight, Defaults.widgetHoverHighlight)
            launchAtLogin = c.value(.launchAtLogin, Defaults.launchAtLogin)
            launchMinimized = c.value(.launchMinimized, Defaults.launchMinimized)
        }
    }

    private func persist() {
        let snap = Snapshot(
            focusSeconds: focusSeconds,
            shortBreakSeconds: shortBreakSeconds,
            longBreakSeconds: longBreakSeconds,
            longBreakInterval: longBreakInterval,
            autoStartNextPhase: autoStartNextPhase,
            autoReturnToFocus: autoReturnToFocus,
            reminders: reminders,
            sound: sound,
            gazeDistanceMeters: gazeDistanceMeters,
            layerMode: layerMode,
            widgetStyle: widgetStyle,
            widgetTheme: widgetTheme,
            widgetX: widgetX,
            widgetY: widgetY,
            widgetScale: widgetScale,
            showWidgetText: showWidgetText,
            showMenuBarSeconds: showMenuBarSeconds,
            widgetClickThrough: widgetClickThrough,
            widgetOpacity: widgetOpacity,
            widgetHoverHighlight: widgetHoverHighlight,
            launchAtLogin: launchAtLogin,
            launchMinimized: launchMinimized
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: key)
        }
    }

    /// 当前阶段的默认时长
    func duration(for phase: TimerPhase) -> Int {
        switch phase {
        case .focus:      return focusSeconds
        case .shortBreak: return shortBreakSeconds
        case .longBreak:  return longBreakSeconds
        }
    }
}

// MARK: - 容错解码

extension KeyedDecodingContainer {
    /// 读取一个键；缺失 / 为 null / 解码失败时返回兜底值。
    ///
    /// 这样新增配置项后，老版本写下的 JSON 依然能完整读出来。
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        // `try?` 会把 decodeIfPresent 的双层 Optional 拍平，
        // 所以这里拿到的是 `T?`：键缺失 / 为 null / 解码失败都走兜底。
        guard let decoded = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return decoded
    }
}

// MARK: - 测试访问

/// 给端到端测试用的公开入口。
///
/// `Snapshot` 本身是 internal 的（只在模块内可见），
/// 测试用独立的 swiftc 编译时需要通过这个别名访问。
enum AppSettingsTestAccess {
    typealias Snapshot = AppSettings.Snapshot
}
