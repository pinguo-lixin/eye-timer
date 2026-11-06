import Foundation
import Combine
import AppKit

/// 计时引擎：20-20-20 法则的阶段状态机。
///
/// 设计要点：内部使用**绝对时间戳**（deadline）而非递减计数器。
/// 这样即使系统休眠、App 被挂起或定时器延迟触发，重新计算出的剩余时间依然准确。
final class TimerEngine: ObservableObject {
    static let shared = TimerEngine()

    enum State: Equatable {
        case idle
        case running
        case paused
        /// 休息阶段正在进行（此时显示全屏引导）
        case resting
    }

    // MARK: - 状态

    @Published private(set) var phase: TimerPhase = .focus
    @Published private(set) var state: State = .idle
    /// 已完成的专注周期数（连续计数，用于判断长休息）
    @Published private(set) var completedFocusCycles: Int = 0
    /// 今日累计专注秒数
    @Published private(set) var todayFocusSeconds: Int = 0

    /// 当前阶段总时长（秒）
    @Published private(set) var totalSeconds: Int = 0

    /// 剩余秒数。
    ///
    /// 刻意做成**计算属性**：每次读取都直接由 `deadline` 推导，
    /// 而不是依赖定时器去递减一个计数器。
    /// 这样即使主线程被阻塞（同步 IO、复杂视图重算、系统休眠），
    /// 读到的剩余时间依然是真实值；系统休眠唤醒后也不会漂移。
    var remainingSeconds: Int {
        switch state {
        case .idle:
            return totalSeconds
        case .paused:
            return pausedRemaining
        case .running, .resting:
            return currentRemaining()
        }
    }

    // MARK: - 事件回调

    /// 阶段切换时回调（参数为新阶段）
    var onPhaseChange: ((TimerPhase) -> Void)?
    /// 专注周期完成
    var onFocusCycleComplete: (() -> Void)?
    /// 休息阶段完成
    var onBreakComplete: (() -> Void)?

    // MARK: - 内部

    private let settings: AppSettings
    private let stats: StatsStore
    private var timer: Timer?
    private var lastPublishedRemaining: Int?
    /// 当前阶段的目标结束时刻
    private var deadline: Date?
    /// 暂停时剩余的秒数
    private var pausedRemaining: Int = 0
    /// 记录已完成的专注秒数（用于统计）
    private var accumulatedFocusSeconds: Int = 0

    init(settings: AppSettings = .shared, stats: StatsStore = .shared) {
        self.settings = settings
        self.stats = stats
        self.totalSeconds = settings.focusSeconds
    }

    // MARK: - 公开控制

    /// 开始或恢复计时（若当前处于休息阶段则直接跳过休息进入专注）
    func start() {
        if state == .paused {
            resume()
            return
        }
        if state == .running || state == .resting { return }

        phase = .focus
        beginPhase(.focus)
    }

    /// 从头开始一个专注周期（重置当前进度）
    func restart() {
        let wasResting = state == .resting
        stopTimer()
        accumulatedFocusSeconds = 0
        if wasResting {
            phase = .focus
            beginPhase(.focus)
        } else {
            phase = .focus
            beginPhase(.focus)
        }
    }

    func pause() {
        guard state == .running || state == .resting else { return }
        let remaining = currentRemaining()
        stopTimer()
        pausedRemaining = remaining
        state = .paused
        publishTick()
    }

    func resume() {
        guard state == .paused else { return }
        state = (phase == .focus) ? .running : .resting
        deadline = Date().addingTimeInterval(TimeInterval(pausedRemaining))
        startTimer()
        publishTick()
    }

    /// 跳过当前阶段，立即进入下一阶段
    func skip() {
        stopTimer()
        switch phase {
        case .focus:
            // 跳过的专注不计入完成数
            accumulatedFocusSeconds = 0
            enterNextPhase()
        case .shortBreak, .longBreak:
            accumulatedFocusSeconds = 0
            enterNextPhase()
        }
    }

    /// 延后休息（把休息推迟 N 秒，仍保持休息状态但不再强制遮挡屏幕）
    func snoozeBreak(seconds: Int = 60) {
        guard phase == .shortBreak || phase == .longBreak else { return }
        stopTimer()
        deadline = Date().addingTimeInterval(TimeInterval(seconds))
        pausedRemaining = seconds
        state = .resting
        startTimer()
        publishTick()
    }

    /// 结束休息，回到专注（并自动开始）
    func endBreak() {
        guard phase == .shortBreak || phase == .longBreak else { return }
        stopTimer()
        accumulatedFocusSeconds = 0
        enterNextPhase()
    }

    /// 彻底停止并回到空闲状态
    func stopAll() {
        stopTimer()
        state = .idle
        phase = .focus
        deadline = nil
        pausedRemaining = 0
        accumulatedFocusSeconds = 0
        // 停止后重置连续周期计数 —— 否则下次启动会直接撞上长休息
        completedFocusCycles = 0
        totalSeconds = settings.focusSeconds
        publishTick()
    }

    // MARK: - 阶段推进

    private func enterNextPhase() {
        switch phase {
        case .focus:
            let next: TimerPhase = (completedFocusCycles > 0 && completedFocusCycles % settings.longBreakInterval == 0)
                ? .longBreak
                : .shortBreak
            beginPhase(next)
        case .shortBreak, .longBreak:
            beginPhase(.focus)
        }
    }

    private func beginPhase(_ newPhase: TimerPhase) {
        let wasPhase = phase
        phase = newPhase
        let duration = settings.duration(for: newPhase)
        totalSeconds = duration
        deadline = Date().addingTimeInterval(TimeInterval(duration))
        state = (newPhase == .focus) ? .running : .resting
        startTimer()
        publishTick()
        if wasPhase != newPhase {
            onPhaseChange?(newPhase)
        }
    }

    // MARK: - 定时器

    private func startTimer() {
        stopTimer()
        guard let deadline else { return }
        // 对齐倒计时的下一次秒数变化；继续使用绝对 deadline，延迟触发不会累积误差。
        let firstTick = deadline.addingTimeInterval(-Double(max(0, currentRemaining() - 1)))
        let t = Timer(fire: firstTick, interval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running || state == .resting else { return }
        let remaining = currentRemaining()
        if remaining <= 0 {
            completeCurrentPhase()
        } else if remaining != lastPublishedRemaining {
            publishTick()
        }
    }

    /// 基于绝对时间戳计算剩余秒数 —— 休眠唤醒后依然准确
    private func currentRemaining() -> Int {
        guard let deadline else { return 0 }
        let delta = deadline.timeIntervalSinceNow
        return max(0, Int(ceil(delta)))
    }

    private func completeCurrentPhase() {
        stopTimer()
        switch phase {
        case .focus:
            let effective = totalSeconds
            accumulatedFocusSeconds = effective
            completedFocusCycles += 1
            todayFocusSeconds += effective
            stats.recordFocusCycle(seconds: effective)
            onFocusCycleComplete?()
            enterNextPhase()
        case .shortBreak, .longBreak:
            stats.recordBreakCycle()
            onBreakComplete?()
            accumulatedFocusSeconds = 0
            // 休息结束后自动回到专注
            beginPhase(.focus)
        }
    }

    /// 对外发布的派生属性（供 SwiftUI 观察）
    private func publishTick() {
        // remainingSeconds 是计算属性，只在显示值或控制状态变化时通知视图。
        lastPublishedRemaining = remainingSeconds
        objectWillChange.send()
    }

    // MARK: - 派生数据

    /// 进度 0...1（已完成比例）
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(totalSeconds - remainingSeconds) / Double(totalSeconds)))
    }

    /// 剩余时间的显示文本
    var remainingText: String {
        let remaining = remainingSeconds
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 距离下一个休息还有多久的简短描述
    var statusLine: String {
        switch state {
        case .idle:
            return "未开始"
        case .paused:
            return "已暂停 · \(remainingText)"
        case .running:
            return "\(phase.title) · \(remainingText)"
        case .resting:
            return "\(phase.title) · \(remainingText)"
        }
    }
}
