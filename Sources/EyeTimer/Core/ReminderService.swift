import Foundation
import AppKit
import UserNotifications
import AVFoundation

/// 提醒服务：系统通知 + 提示音 + 语音播报。
final class ReminderService: NSObject {
    static let shared = ReminderService()

    private let settings: AppSettings
    private var audioPlayer: AVAudioPlayer?

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init()
    }

    // MARK: - 通知授权

    /// 请求通知权限（App 启动时调用一次）
    func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                NSLog("[EyeTimer] 通知权限未授予，将使用其他提醒方式")
            }
        }
    }

    // MARK: - 发送提醒

    /// 阶段切换时统一入口
    func notifyPhaseChange(to phase: TimerPhase, remainingSeconds: Int) {
        let opts = settings.reminders

        if opts.showNotification {
            sendNotification(for: phase)
        }
        if opts.playSound {
            playSound()
        }
        if opts.speak {
            speak(for: phase)
        }
    }

    private func sendNotification(for phase: TimerPhase) {
        let content = UNMutableNotificationContent()
        switch phase {
        case .focus:
            content.title = "休息一下眼睛 👀"
            content.body = "已经专注 \(AppSettings.shared.focusSeconds / 60) 分钟了。看向 6 米外的远处，保持 20 秒。"
        case .shortBreak:
            content.title = "休息结束"
            content.body = "眼睛已经休息了 20 秒，继续保持这个节奏。"
        case .longBreak:
            content.title = "来个大休息"
            content.body = "完成一个长周期了，站起来走动一下，眺望远处。"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "eyetimer.phase.\(phase.rawValue).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 提示音

    private func playSound() {
        let name = settings.sound.rawValue
        let candidates = [
            "/System/Library/Sounds/\(name).aiff",
            "/Library/Sounds/\(name).aiff"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
            // 降级：用系统 beep
            NSSound.beep()
            return
        }
        player.volume = 0.5
        player.play()
        audioPlayer = player
    }

    // MARK: - 语音播报

    private func speak(for phase: TimerPhase) {
        let text: String
        switch phase {
        case .focus:      text = "该休息一下眼睛了，看向远处二十秒"
        case .shortBreak: text = "休息结束，继续加油"
        case .longBreak:  text = "长休息时间到了，站起来活动一下"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "Tingting", text]
        try? process.run()
    }
}
