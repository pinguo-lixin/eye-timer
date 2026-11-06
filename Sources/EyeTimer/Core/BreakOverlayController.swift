import AppKit
import SwiftUI

/// 休息引导全屏遮罩控制器。
///
/// 使用 `NSPanel` + `.nonactivatingPanel` + `screenSaverWindow` 层级：
///  - 覆盖全屏，柔和遮住底层内容，把视线拉回远处
///  - 不激活应用、不抢走当前 App 的键盘焦点（不打断你正在写的代码）
///  - 右上角留「跳过」出口，避免强制打断
final class BreakOverlayController: NSObject, ObservableObject {

    static let shared = BreakOverlayController()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    /// 引导层的倒计时定时器
    private var countdownTimer: Timer?
    /// 引导层结束时刻
    private var deadline: Date = Date()

    /// 当前是否正在显示
    @Published private(set) var isShowing = false
    /// 剩余秒数（引导层内的倒计时）
    @Published private(set) var remaining: Int = 0
    /// 本次引导的总时长（秒），用于进度条比例
    @Published private(set) var totalDuration: Int = 20
    /// 注视距离（米）
    @Published var gazeDistance: Int = 6
    /// 阶段标题
    @Published private(set) var phaseTitle: String = "远眺放松"

    /// 引导层被用户主动关闭时回调
    var onDismiss: (() -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - 显示 / 隐藏

    func show(duration: Int, phase: TimerPhase, gazeDistance: Int) {
        self.gazeDistance = gazeDistance
        self.phaseTitle = phase == .longBreak ? "长休息" : "远眺放松"
        self.remaining = duration
        self.totalDuration = duration
        self.deadline = Date().addingTimeInterval(TimeInterval(duration))

        dismissWorkItem?.cancel()
        countdownTimer?.invalidate()

        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        panel.orderFrontRegardless()
        isShowing = true

        // 每 250ms 刷新一次倒计时数字
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let left = max(0, Int(ceil(self.deadline.timeIntervalSinceNow)))
            if left != self.remaining {
                self.remaining = left
            }
            if left <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.hide(notify: true)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }

    func hide(notify: Bool = true) {
        let wasShowing = isShowing
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        // A hidden hosting view keeps its repeatForever animations running.
        // Tear it down before callbacks can show the next rest window.
        let dismissedPanel = panel
        panel = nil
        dismissedPanel?.orderOut(nil)
        dismissedPanel?.contentView = nil
        dismissedPanel?.close()
        isShowing = false
        if notify && wasShowing {
            onDismiss?()
        }
    }

    // MARK: - 面板构造

    private func makePanel() -> NSPanel {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0

        let host = NSHostingView(rootView: BreakOverlayView()
            .environmentObject(self))
        host.frame = frame
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        // 淡入动画
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 1.0
        }

        return panel
    }
}
