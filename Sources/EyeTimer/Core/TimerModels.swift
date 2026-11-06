import Foundation
import AppKit

/// 一个计时周期中的三个阶段。
enum TimerPhase: String, Codable, CaseIterable, Hashable {
    case focus       // 专注用眼
    case shortBreak  // 短暂休息（20-20-20 的 20 秒）
    case longBreak   // 长休息（每 N 个专注周期后）

    var title: String {
        switch self {
        case .focus:      return "专注用眼"
        case .shortBreak: return "远眺放松"
        case .longBreak:  return "长休息"
        }
    }

    var shortTitle: String {
        switch self {
        case .focus:      return "专注"
        case .shortBreak: return "休息"
        case .longBreak:  return "长休"
        }
    }

    /// 菜单栏与挂件上用的符号
    var symbolName: String {
        switch self {
        case .focus:      return "eye"
        case .shortBreak: return "sparkles"
        case .longBreak:  return "moon.stars"
        }
    }

    var tintName: String {
        switch self {
        case .focus:      return "focus"
        case .shortBreak: return "break"
        case .longBreak:  return "longBreak"
        }
    }
}

/// 挂件的显示层级模式。
enum WidgetLayerMode: String, Codable, CaseIterable, Hashable {
    /// 融入壁纸：夹在壁纸层与桌面图标层之间，切到其他 App 时自动被遮住，像桌上真实摆件
    case desktop
    /// 始终置顶：浮在所有窗口之上
    case floating
    /// 完全隐藏，只保留菜单栏
    case hidden

    var title: String {
        switch self {
        case .desktop:  return "融入桌面"
        case .floating: return "始终置顶"
        case .hidden:   return "隐藏挂件"
        }
    }

    var detail: String {
        switch self {
        case .desktop:
            return "贴在壁纸与桌面图标之间，打开别的 App 时会自然被遮住，像桌面摆件一样不打扰。"
        case .floating:
            return "悬浮在所有窗口之上，随时可见。"
        case .hidden:
            return "不显示桌面挂件，只在菜单栏保留倒计时。"
        }
    }
}

/// 保留旧版存储值，升级后按原来的形态迁移到新设计。
enum WidgetStyle: String, Codable, CaseIterable, Hashable {
    case halo = "ring"
    case monolith = "pill"
    case paper = "text"

    var title: String {
        switch self {
        case .halo: return "Halo"
        case .monolith: return "Monolith"
        case .paper: return "Paper"
        }
    }

    /// 包含阴影留白；窗口、点击范围与缩放始终共用这一尺寸。
    var intrinsicSize: NSSize {
        switch self {
        case .halo: return NSSize(width: 168, height: 168)
        case .monolith: return NSSize(width: 304, height: 116)
        case .paper: return NSSize(width: 240, height: 222)
        }
    }
}

enum WidgetTheme: String, Codable, CaseIterable, Hashable {
    case mist
    case sand
    case forest

    var title: String {
        switch self {
        case .mist: return "雾蓝"
        case .sand: return "暖砂"
        case .forest: return "森林"
        }
    }
}

/// 提醒方式（可多选）。
struct ReminderOptions: Codable, Equatable {
    var showOverlay: Bool = true    // 全屏引导遮罩
    var showNotification: Bool = true // 系统通知
    var playSound: Bool = true      // 提示音
    var speak: Bool = false         // 语音播报
}

enum SoundChoice: String, Codable, CaseIterable, Hashable {
    case glass
    case ping
    case sosumi
    case tink
    case purr
    case funk

    var title: String {
        switch self {
        case .glass:  return "Glass"
        case .ping:   return "Ping"
        case .sosumi: return "Sosumi"
        case .tink:   return "Tink"
        case .purr:   return "Purr"
        case .funk:   return "Funk"
        }
    }
}
