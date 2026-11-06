import Foundation
import AppKit
import ServiceManagement

/// 开机自启管理（macOS 13+ 使用 SMAppService）。
enum LaunchAtLogin {
    private static let serviceID = "com.eyetimer.app"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 设置开机自启。返回是否成功。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return true }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[EyeTimer] 开机自启设置失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 应用是否以「后台启动项」注册（用于判断能否注册）
    static var canRegister: Bool {
        SMAppService.mainApp.status != .notFound
    }
}
