import AppKit

/// 每次打开时重建，保证启用状态与勾选项反映当前计时和外观设置。
final class WidgetContextMenu: NSObject {
    private let engine: TimerEngine
    private let settings: AppSettings
    var onOpacitySelected: (() -> Void)?
    var onFineAdjustment: (() -> Void)?
    static let opacityPresets: [(Double, String)] = [
        (0.2, "20% · 轻隐"), (0.4, "40% · 融入"), (0.6, "60% · 柔和"),
        (0.8, "80% · 清晰"), (1, "100% · 不透明")
    ]

    init(engine: TimerEngine, settings: AppSettings) {
        self.engine = engine
        self.settings = settings
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let start = item(engine.state == .paused ? "继续" : "开始", action: #selector(startTimer))
        start.isEnabled = engine.state == .idle || engine.state == .paused
        menu.addItem(start)
        let pause = item("暂停", action: #selector(pauseTimer))
        pause.isEnabled = engine.state == .running || engine.state == .resting
        menu.addItem(pause)
        menu.addItem(.separator())

        let styles = NSMenu()
        for style in WidgetStyle.allCases {
            let choice = item(style.title, action: #selector(selectStyle(_:)))
            choice.representedObject = style.rawValue
            choice.state = settings.widgetStyle == style ? .on : .off
            styles.addItem(choice)
        }
        let styleItem = NSMenuItem(title: "挂件样式", action: nil, keyEquivalent: "")
        styleItem.submenu = styles
        menu.addItem(styleItem)

        let themes = NSMenu()
        for theme in WidgetTheme.allCases {
            let choice = item(theme.title, action: #selector(selectTheme(_:)))
            choice.representedObject = theme.rawValue
            choice.state = settings.widgetTheme == theme ? .on : .off
            themes.addItem(choice)
        }
        let themeItem = NSMenuItem(title: "配色主题", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        menu.addItem(themeItem)

        let opacity = NSMenu()
        opacity.autoenablesItems = false
        for (value, title) in Self.opacityPresets {
            let choice = item(title, action: #selector(selectOpacity(_:)))
            choice.representedObject = value
            choice.state = abs(settings.widgetOpacity - value) < 0.0001 ? .on : .off
            opacity.addItem(choice)
        }
        if !Self.opacityPresets.contains(where: { abs(settings.widgetOpacity - $0.0) < 0.0001 }) {
            let custom = NSMenuItem(title: String(format: "当前：%.0f%%（自定义）", settings.widgetOpacity * 100),
                                    action: nil, keyEquivalent: "")
            custom.state = .on
            custom.isEnabled = false
            opacity.addItem(custom)
        }
        opacity.addItem(.separator())
        opacity.addItem(item("精细调节…", action: #selector(openFineAdjustment)))
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacity
        menu.addItem(opacityItem)
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func selectOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double,
              Self.opacityPresets.contains(where: { $0.0 == value }) else { return }
        // 先暂停悬停提亮，再写入设置，避免短暂闪回不透明。
        onOpacitySelected?()
        settings.widgetOpacity = value
    }

    @objc private func openFineAdjustment() {
        // 等菜单退出跟踪再显示设置窗口。
        DispatchQueue.main.async { [weak self] in self?.onFineAdjustment?() }
    }

    @objc private func startTimer() {
        guard engine.state == .idle || engine.state == .paused else { return }
        engine.start()
    }

    @objc private func pauseTimer() { engine.pause() }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = WidgetStyle(rawValue: raw) else { return }
        settings.widgetStyle = style
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = WidgetTheme(rawValue: raw) else { return }
        settings.widgetTheme = theme
    }
}
