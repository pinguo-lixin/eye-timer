import SwiftUI
import AppKit
import Combine

@main
struct EyeTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 设置窗口（由 AppDelegate 通过 SettingsWindowController 打开）
        Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
        }
    }
}

// MARK: - 菜单栏控制器

/// 菜单栏状态项控制器。
///
/// 用原生 `NSStatusItem` 而不是 SwiftUI 的 `MenuBarExtra`：
/// 在 `LSUIElement`（纯菜单栏）App 里，MenuBarExtra 的状态项有时不会被
/// WindowServer 正确注册，导致图标不出现。原生 NSStatusItem 更可控。
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private let engine = TimerEngine.shared
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var displayedPhase: TimerPhase?
    private var displayedTitle: String?

    // MARK: 创建

    func setup() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "护眼提醒")
            button.imagePosition = .imageLeading
            button.toolTip = "护眼提醒 EyeTimer"
            // 注意：设置了 statusItem.menu 之后由系统负责弹出菜单，
            // 不能再设置 target/action，否则两者会互相干扰导致状态项不显示。
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        // 与计时引擎共用刷新节奏；暂停 / 空闲时不再轮询。
        // @Published 在赋值前通知，切到下一轮主循环读取完整的新状态。
        engine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshButton() }
            .store(in: &cancellables)
        settings.$showMenuBarSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshButton() }
            .store(in: &cancellables)

        refreshButton()
        NSLog("[EyeTimer] 菜单栏状态项已创建")
    }

    private func refreshButton() {
        guard let button = statusItem?.button else { return }

        if displayedPhase != engine.phase {
            button.image = NSImage(systemSymbolName: engine.phase.symbolName, accessibilityDescription: nil)
            button.image?.isTemplate = true
            displayedPhase = engine.phase
        }

        let title = settings.showMenuBarSeconds ? " " + engine.remainingText : ""
        guard title != displayedTitle else { return }
        displayedTitle = title

        // NSStatusItem 的按钮在设置了 image 后不显示 title，
        // 因此需要用 attributedTitle 手动拼接「图标 + 文字」。
        if settings.showMenuBarSeconds {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
            button.imagePosition = .imageLeading
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        }
    }

    // MARK: 交互

    /// 菜单打开时重建内容，保证显示最新状态
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    /// 主动弹出菜单（供 `--demo-menu` 参数与自动化测试使用）
    func popUpMenu() {
        guard let menu = statusItem?.menu else { return }
        rebuild(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        // 状态区
        let header = NSMenuItem(title: "\(engine.phase.title) · \(engine.remainingText)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // 开始 / 继续
        let startTitle = engine.state == .paused ? "继续" : "开始"
        let start = NSMenuItem(title: startTitle, action: #selector(startAction), keyEquivalent: "")
        start.target = self
        start.isEnabled = engine.state != .running && engine.state != .resting
        menu.addItem(start)

        // 暂停
        let pause = NSMenuItem(title: "暂停", action: #selector(pauseAction), keyEquivalent: "")
        pause.target = self
        pause.isEnabled = engine.state == .running || engine.state == .resting
        menu.addItem(pause)

        // 跳过
        let skip = NSMenuItem(title: "跳过本轮", action: #selector(skipAction), keyEquivalent: "")
        skip.target = self
        menu.addItem(skip)

        // 重新开始
        let restart = NSMenuItem(title: "重新开始", action: #selector(restartAction), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        menu.addItem(.separator())

        // 桌面挂件层级
        let layerHeader = NSMenuItem(title: "桌面挂件", action: nil, keyEquivalent: "")
        layerHeader.isEnabled = false
        menu.addItem(layerHeader)

        for mode in WidgetLayerMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(layerAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (settings.layerMode == mode) ? .on : .off
            menu.addItem(item)
        }

        let appearanceMenu = NSMenuItem(title: "挂件样式", action: nil, keyEquivalent: "")
        let styles = NSMenu()
        for style in WidgetStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(styleAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = settings.widgetStyle == style ? .on : .off
            styles.addItem(item)
        }
        appearanceMenu.submenu = styles
        menu.addItem(appearanceMenu)

        let themeMenu = NSMenuItem(title: "配色主题", action: nil, keyEquivalent: "")
        let themes = NSMenu()
        for theme in WidgetTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(themeAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            item.state = settings.widgetTheme == theme ? .on : .off
            themes.addItem(item)
        }
        themeMenu.submenu = themes
        menu.addItem(themeMenu)

        let center = NSMenuItem(title: "居中显示挂件", action: #selector(centerAction), keyEquivalent: "")
        center.target = self
        center.isEnabled = settings.layerMode != .hidden
        menu.addItem(center)

        menu.addItem(.separator())

        // 设置
        let settingsItem = NSMenuItem(title: "设置与统计…", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 停止
        let stop = NSMenuItem(title: "停止计时", action: #selector(stopAction), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)

        let quit = NSMenuItem(title: "退出护眼提醒", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: 动作

    @objc private func startAction() { engine.start() }
    @objc private func pauseAction() { engine.pause() }
    @objc private func skipAction() { engine.skip() }
    @objc private func restartAction() { engine.restart() }
    @objc private func stopAction() { engine.stopAll() }

    @objc private func layerAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = WidgetLayerMode(rawValue: raw) else { return }
        settings.layerMode = mode
        if mode == .hidden {
            DesktopWidgetController.shared.hide()
        } else {
            DesktopWidgetController.shared.show()
            DesktopWidgetController.shared.applyLevel()
        }
    }

    @objc private func styleAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = WidgetStyle(rawValue: raw) else { return }
        settings.widgetStyle = style
    }

    @objc private func themeAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = WidgetTheme(rawValue: raw) else { return }
        settings.widgetTheme = theme
    }

    @objc private func centerAction() {
        DesktopWidgetController.shared.centerOnScreen()
    }

    @objc private func settingsAction() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = TimerEngine.shared
    private let settings = AppSettings.shared
    private let reminders = ReminderService.shared
    private let widget = DesktopWidgetController.shared
    private let overlay = BreakOverlayController.shared
    private let menuBar = MenuBarController.shared

    /// 在创建任何窗口/状态项之前把 App 设为 accessory（纯菜单栏）模式。
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[EyeTimer] 应用启动, pid=\(ProcessInfo.processInfo.processIdentifier)")

        // 命令行参数：
        //   --settings   启动即打开设置窗口
        //   --start      启动即开始计时
        //   --demo-break 启动即演示一次休息引导（预览效果用）
        //   --demo-menu  启动即弹出菜单栏菜单（预览效果用）
        //   --move X Y   启动即把挂件移动到指定屏幕坐标（左下原点）
        //   --center     启动即把挂件居中
        let args = ProcessInfo.processInfo.arguments
        let wantsSettings = args.contains("--settings")
        let wantsStart = args.contains("--start")
        let wantsDemoBreak = args.contains("--demo-break")
        let wantsDemoMenu = args.contains("--demo-menu")

        // 菜单栏状态项
        menuBar.setup()

        // 通知授权
        reminders.requestNotificationAuthorization()

        // 装配引擎回调
        engine.onPhaseChange = { [weak self] phase in
            self?.handlePhaseChange(to: phase)
        }

        // 引导层关闭后，若用户跳过了休息则回到专注
        overlay.onDismiss = { [weak self] in
            self?.handleOverlayDismissed()
        }

        // 显示桌面挂件
        if settings.layerMode != .hidden {
            widget.show()
        }

        // 开机自启状态同步
        settings.launchAtLogin = LaunchAtLogin.isEnabled

        // 按命令行参数执行动作
        if wantsStart {
            engine.start()
        }
        if wantsSettings {
            DispatchQueue.main.async {
                SettingsWindowController.shared.show()
            }
        }
        if wantsDemoBreak {
            DispatchQueue.main.async { [self] in
                self.overlay.show(
                    duration: 20,
                    phase: .shortBreak,
                    gazeDistance: self.settings.gazeDistanceMeters
                )
                NSLog("[EyeTimer] 已触发演示休息引导")
            }
        }
        if wantsDemoMenu {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                self.menuBar.popUpMenu()
            }
        }
        // 测试辅助：把挂件移到指定位置（屏幕坐标，左下原点）
        // 仅在显式开启诊断开关时生效，正常使用不会触发。
        if DebugSwitches.forceFallbackPath || DebugSwitches.disableMarqueeFix,
           args.count >= 3,
           let x = Double(args[args.count - 2]), let y = Double(args[args.count - 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DesktopWidgetController.shared.moveWidget(to: NSPoint(x: x, y: y))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        widget.destroy()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 阶段回调

    private func handlePhaseChange(to phase: TimerPhase) {
        // 只有进入休息阶段才提醒
        guard phase == .shortBreak || phase == .longBreak else { return }
        reminders.notifyPhaseChange(to: phase, remainingSeconds: settings.duration(for: phase))

        if settings.reminders.showOverlay {
            overlay.show(
                duration: settings.duration(for: phase),
                phase: phase,
                gazeDistance: settings.gazeDistanceMeters
            )
        }
    }

    private func handleOverlayDismissed() {
        // 用户跳过/关闭引导层后，立即结束休息回到专注
        engine.endBreak()
    }
}
