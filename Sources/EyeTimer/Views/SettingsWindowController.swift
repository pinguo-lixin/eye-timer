import AppKit
import SwiftUI
import Charts

/// 设置窗口控制器（单例窗口）。
final class SettingsWindowController: NSObject, ObservableObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    @Published var selectedSection: SettingsView.Section = .rules
    @Published var opacityRequest = 0

    func showOpacityControls() {
        selectedSection = .widget
        opacityRequest += 1
        show()
    }

    private override init() {
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "护眼提醒 · EyeTimer"
        win.center()
        win.setFrameAutosaveName("EyeTimerSettingsWindow")
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 640, height: 480)
        // 置顶显示，避免被其他窗口盖住
        win.level = .floating

        let host = NSHostingView(rootView: SettingsView()
            .environmentObject(AppSettings.shared))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 560)
        win.contentView = host

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 设置窗口主视图：左侧分段选择，右侧内容。
struct SettingsView: View {
    enum Section: String, CaseIterable, Hashable {
        case rules    = "护眼法则"
        case widget   = "桌面挂件"
        case remind   = "提醒方式"
        case stats    = "使用统计"
        case about    = "关于"

        var icon: String {
            switch self {
            case .rules:  return "eye"
            case .widget: return "desktopcomputer"
            case .remind: return "bell.badge"
            case .stats:  return "chart.bar.fill"
            case .about:  return "info.circle"
            }
        }
    }

    @ObservedObject private var navigation = SettingsWindowController.shared

    var body: some View {
        HStack(spacing: 0) {
            // 侧边栏
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("护眼提醒")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ForEach(Section.allCases, id: \.rawValue) { s in
                    Button {
                        navigation.opacityRequest = 0
                        navigation.selectedSection = s
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: s.icon)
                                .font(.system(size: 11))
                                .frame(width: 16)
                            Text(s.rawValue)
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(navigation.selectedSection == s ? Color.accentColor.opacity(0.14) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Divider().padding(.horizontal, 12).padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("20-20-20 法则")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("每 20 分钟，看 20 英尺外\n至少 20 秒")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: 176)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 内容区
            Group {
                switch navigation.selectedSection {
                case .rules:  RulesView()
                case .widget: WidgetSettingsView()
                case .remind: ReminderSettingsView()
                case .stats:  StatsView()
                case .about:  AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

// MARK: - 护眼法则

struct RulesView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("护眼法则")
                    .font(.system(size: 17, weight: .semibold))

                Text("调整计时节奏。每个专注周期结束后提醒你远眺放松眼睛。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        durationRow(title: "专注用眼时长",
                                   subtitle: "连续用眼多久后开始提醒",
                                   seconds: $settings.focusSeconds,
                                   displayRange: 1...120,
                                   unit: .minute)

                        Divider()

                        durationRow(title: "短休息时长",
                                   subtitle: "远眺放松眼睛的时间",
                                   seconds: $settings.shortBreakSeconds,
                                   displayRange: 10...120,
                                   unit: .second)

                        Divider()

                        durationRow(title: "长休息时长",
                                   subtitle: "完成多个周期后的深度休息",
                                   seconds: $settings.longBreakSeconds,
                                   displayRange: 1...30,
                                   unit: .minute)
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("长休息间隔")
                                .font(.system(size: 12.5))
                            Spacer()
                            Text("每 \(settings.longBreakInterval) 个专注周期")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.longBreakInterval) },
                                set: { settings.longBreakInterval = Int($0) }
                            ),
                            in: 2...8,
                            step: 1
                        )
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("休息结束后自动回到专注计时", isOn: $settings.autoReturnToFocus)
                            .font(.system(size: 12.5))
                        Toggle("专注计时结束后自动进入休息", isOn: $settings.autoStartNextPhase)
                            .font(.system(size: 12.5))
                    }
                    .padding(6)
                }

                HStack {
                    Button {
                        TimerEngine.shared.restart()
                    } label: {
                        Label("重新开始计时", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 时长滑杆。
    ///
    /// 设置内部统一以**秒**存储，这里按显示单位（分钟/秒）做换算，
    /// 避免出现「1200 分钟」这种单位错乱的显示。
    private func durationRow(title: String,
                             subtitle: String,
                             seconds: Binding<Int>,
                             displayRange: ClosedRange<Int>,
                             unit: DurationUnit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .medium))
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(unit.display(seconds.wrappedValue)) \(unit.rawValue)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(unit.display(seconds.wrappedValue)) },
                    set: { seconds.wrappedValue = unit.storage(Int($0.rounded())) }
                ),
                in: Double(displayRange.lowerBound)...Double(displayRange.upperBound),
                step: 1
            )
        }
    }
}

/// 时长显示单位。
enum DurationUnit: String {
    case minute = "分钟"
    case second = "秒"

    /// 秒 → 显示值
    func display(_ seconds: Int) -> Int {
        switch self {
        case .minute: return max(1, Int((Double(seconds) / 60.0).rounded()))
        case .second: return seconds
        }
    }

    /// 显示值 → 秒
    func storage(_ value: Int) -> Int {
        switch self {
        case .minute: return value * 60
        case .second: return value
        }
    }
}

// MARK: - 桌面挂件

struct WidgetSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var widget = DesktopWidgetController.shared
    @ObservedObject private var navigation = SettingsWindowController.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("桌面挂件")
                        .font(.system(size: 17, weight: .semibold))

                    Text("选择样式与主题，让护眼提醒安静地融入桌面。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(WidgetLayerMode.allCases, id: \.rawValue) { mode in
                                Button {
                                    settings.layerMode = mode
                                    if mode == .hidden {
                                        widget.hide()
                                    } else {
                                        widget.show()
                                        widget.applyLevel()
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 9) {
                                        Image(systemName: settings.layerMode == mode ? "largecircle.fill.circle" : "circle")
                                            .font(.system(size: 13))
                                            .foregroundStyle(settings.layerMode == mode ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(mode.title)
                                                .font(.system(size: 12.5, weight: .medium))
                                                .foregroundStyle(.primary)
                                            Text(mode.detail)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 3)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("外观样式")
                                    .font(.system(size: 12.5, weight: .medium))
                                Spacer()
                                Picker("", selection: $settings.widgetStyle) {
                                    ForEach(WidgetStyle.allCases, id: \.rawValue) { s in
                                        Text(s.title).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 260)
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.17, blue: 0.24),
                                                                  Color(red: 0.07, green: 0.11, blue: 0.17)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                WidgetFace(style: settings.widgetStyle, theme: settings.widgetTheme,
                                           showsDetails: settings.showWidgetText)
                                    .scaleEffect(0.9)
                            }
                            .frame(height: 216)
                            .accessibilityLabel("样式预览，\(settings.widgetStyle.title)，\(settings.widgetTheme.title)")

                            HStack {
                                Text("配色主题")
                                    .font(.system(size: 12.5, weight: .medium))
                                Spacer()
                                Picker("配色主题", selection: $settings.widgetTheme) {
                                    ForEach(WidgetTheme.allCases, id: \.rawValue) { theme in
                                        Text(theme.title).tag(theme)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 260)
                            }

                            Divider()

                            if settings.widgetStyle == .halo {
                                Text("Halo 仅显示倒计时与阶段图标，保持简洁。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            } else {
                                Toggle("显示辅助文字", isOn: $settings.showWidgetText)
                                    .font(.system(size: 12.5))
                            }

                            Text("大小与透明度会应用到桌面挂件；上方预览保持清晰。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("大小")
                                    .font(.system(size: 12.5))
                                Spacer()
                                Text(String(format: "%.0f%%", settings.widgetScale * 100))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: $settings.widgetScale,
                                in: 0.6...1.8
                            )
                        }
                        .padding(6)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("融入程度")
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text("调低透明度，挂件会更「藏进」壁纸里")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.0f%%", settings.widgetOpacity * 100))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: $settings.widgetOpacity,
                                in: 0.10...1.0
                            )

                            HStack {
                                Text("透明")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("不透明")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            Toggle("鼠标指向时恢复不透明", isOn: $settings.widgetHoverHighlight)
                                .font(.system(size: 12.5))

                            HStack(spacing: 6) {
                                Image(systemName: "hand.point.up.left")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text("把鼠标移到挂件上看看效果")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        .padding(6)
                    }
                    .id("widget-opacity")

                    // MARK: 辅助功能授权
                    //
                    // 挂件位于「桌面图标层之下」，点击会穿透给 Finder，
                    // 于是 Finder 进入框选模式 → 拖动时桌面画出蓝色矩形。
                    //
                    // 有辅助功能授权时可由事件 tap 直接吞掉按下事件；
                    // 未授权时使用全局监视器和事件抵消，仍可避免桌面框选。
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: widget.isAccessibilityTrusted
                                      ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(widget.isAccessibilityTrusted
                                                     ? Color.green : Color.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(widget.isAccessibilityTrusted
                                         ? "已授权：拖拽不会影响桌面" : "未授权：使用兼容拖拽模式")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(widget.isAccessibilityTrusted
                                         ? "挂件使用事件 tap 直接接管鼠标事件，桌面完全不受影响。"
                                         : "挂件会在拖拽时自动取消 Finder 的桌面框选，无需授权也能正常移动。")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 8) {
                                if widget.isAccessibilityTrusted {
                                    Button {
                                        widget.refreshAccessibilityAuthorization()
                                    } label: {
                                        Label("重新检查", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button {
                                        widget.requestAccessibilityAuthorization()
                                    } label: {
                                        Label("申请辅助功能权限", systemImage: "lock.shield")
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button {
                                        widget.openAccessibilitySettings()
                                    } label: {
                                        Label("打开系统设置", systemImage: "gear")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Spacer()
                            }
                        }
                        .padding(6)
                    }

                    HStack {
                        Button {
                            widget.centerOnScreen()
                        } label: {
                            Label("居中显示挂件", systemImage: "target")
                        }
                        .buttonStyle(.bordered)

                        Text("提示：直接拖动桌面上的挂件即可移动位置")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()                }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if navigation.opacityRequest > 0 {
                    DispatchQueue.main.async { proxy.scrollTo("widget-opacity", anchor: .top) }
                }
            }
            .onReceive(navigation.$opacityRequest.dropFirst()) { request in
                if request > 0 {
                    DispatchQueue.main.async { proxy.scrollTo("widget-opacity", anchor: .top) }
                }
            }
        }
    }
}

// MARK: - 提醒方式

struct ReminderSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("提醒方式")
                    .font(.system(size: 17, weight: .semibold))

                Text("选择休息时如何通知你。可同时开启多种方式。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("全屏引导遮罩", isOn: $settings.reminders.showOverlay)
                            .font(.system(size: 12.5))
                        Text("在半透明遮罩上显示呼吸动画，引导看向远处并倒计时")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)

                        Divider()

                        Toggle("系统通知", isOn: $settings.reminders.showNotification)
                            .font(.system(size: 12.5))

                        Divider()

                        Toggle("播放提示音", isOn: $settings.reminders.playSound)
                            .font(.system(size: 12.5))
                        HStack {
                            Text("提示音")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 20)
                            Spacer()
                            Picker("", selection: $settings.sound) {
                                ForEach(SoundChoice.allCases, id: \.rawValue) { s in
                                    Text(s.title).tag(s)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                            .disabled(!settings.reminders.playSound)
                        }

                        Divider()

                        Toggle("语音播报", isOn: $settings.reminders.speak)
                            .font(.system(size: 12.5))
                    }
                    .padding(6)
                }

                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("远眺距离提示")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("20-20-20 法则建议看 6 米（约 20 英尺）以外")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(settings.gazeDistanceMeters) 米",
                               value: $settings.gazeDistanceMeters,
                               in: 3...20)
                        .fixedSize()
                    }
                    .padding(6)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 统计

struct StatsView: View {
    @ObservedObject private var stats = StatsStore.shared
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("使用统计")
                    .font(.system(size: 17, weight: .semibold))

                HStack(spacing: 12) {
                    statCard(title: "今日专注周期",
                             value: "\(stats.today.focusCycles)",
                             unit: "次",
                             icon: "eye",
                             tint: .blue)
                    statCard(title: "今日休息次数",
                             value: "\(stats.today.breakCycles)",
                             unit: "次",
                             icon: "sparkles",
                             tint: .green)
                    statCard(title: "今日用眼时长",
                             value: formatMinutes(stats.today.focusSeconds),
                             unit: "分钟",
                             icon: "clock",
                             tint: .purple)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("近 7 天专注周期")
                            .font(.system(size: 12.5, weight: .medium))

                        Chart(stats.recentDays(7)) { day in
                            BarMark(
                                x: .value("日期", shortLabel(day.dateKey)),
                                y: .value("周期", day.focusCycles)
                            )
                            .foregroundStyle(
                                day.dateKey == stats.today.dateKey
                                ? Color.accentColor
                                : Color.accentColor.opacity(0.35)
                            )
                            .cornerRadius(3)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                                AxisValueLabel()
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 150)
                    }
                    .padding(6)
                }

                HStack(spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                    Text(tips(stats))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 2)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statCard(title: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func shortLabel(_ key: String) -> String {
        // "2026-11-05" -> "11/05"
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }

    private func formatMinutes(_ seconds: Int) -> String {
        String(seconds / 60)
    }

    private func tips(_ stats: StatsStore) -> String {
        let avg = stats.recentDays(7).map { $0.focusCycles }.reduce(0, +) / 7
        if avg >= 6 {
            return "节奏很棒！平均每天完成 \(avg) 个专注周期，眼睛会很舒服。"
        } else if avg >= 3 {
            return "不错，平均每天 \(avg) 个周期。试着把专注时长调到 20 分钟，规律更好。"
        } else {
            return "平均每天 \(avg) 个周期，还挺佛系。建议开启「专注结束后自动进入休息」。"
        }
    }
}

// MARK: - 关于

struct AboutView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("关于")
                    .font(.system(size: 17, weight: .semibold))

                HStack(spacing: 12) {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .green],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("护眼提醒 EyeTimer")
                            .font(.system(size: 14, weight: .semibold))
                        Text("版本 1.0.0 · 原生 macOS 应用")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("开机时自动启动", isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { newValue in
                                settings.launchAtLogin = newValue
                                LaunchAtLogin.setEnabled(newValue)
                            }
                        ))
                        .font(.system(size: 12.5))

                        Toggle("启动时最小化到菜单栏", isOn: $settings.launchMinimized)
                            .font(.system(size: 12.5))
                    }
                    .padding(6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("关于 20-20-20 法则")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("每用眼 20 分钟，抬头看向 20 英尺（约 6 米）以外的地方，持续 20 秒。这能帮助眼外肌放松，缓解视疲劳和干眼。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("快捷键：⌘, 打开设置 · 菜单栏图标点击开始/暂停")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
