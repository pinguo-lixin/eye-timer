import AppKit
import SwiftUI

// Exercise real hosting-view lifetimes without changing the installed app's state.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let overlay = BreakOverlayController.shared
var checks = 0
var failures: [String] = []

final class HostLifetime {
    private weak var host: NSView?
    init(window: NSWindow?) { host = window?.contentView }
    var isReleased: Bool { host == nil }
}

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { failures.append(message); print("FAIL: \(message)") }
}

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        autoreleasepool {
            _ = RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02)))
        }
    }
}

func show(duration: Int, phase: TimerPhase = .shortBreak) -> NSWindow {
    autoreleasepool {
        overlay.show(duration: duration, phase: phase, gazeDistance: 6)
        let window = app.windows.first {
            $0.isVisible && $0.level.rawValue == Int(CGWindowLevelForKey(.screenSaverWindow))
        }!
        window.setFrameOrigin(NSPoint(x: -10000, y: 0))
        return window
    }
}

func hide(notify: Bool = true) {
    // AppKit drains an autorelease pool after each real UI event.
    autoreleasepool { overlay.hide(notify: notify) }
}

var dismissals = 0
var callbackSawHiddenWindow = false
overlay.onDismiss = {
    dismissals += 1
    callbackSawHiddenWindow = !overlay.isShowing
}

weak var firstWindow = show(duration: 60)
let firstHost = HostLifetime(window: firstWindow)
pump(0.5) // Allow onAppear to start the breathing animations.
check(overlay.isShowing && firstWindow?.isVisible == true, "休息引导可显示")
check(!firstHost.isReleased, "休息引导创建宿主视图")
hide(notify: false)
pump(0.5)
check(!overlay.isShowing && firstWindow?.isVisible != true, "关闭后休息窗口不可见")
check(firstHost.isReleased, "关闭后动画宿主视图可释放")
check(dismissals == 0, "静默关闭不触发回调")

weak var secondWindow = show(duration: 60, phase: .longBreak)
check(secondWindow !== firstWindow, "再次显示重建休息窗口")
check(secondWindow?.contentView != nil && overlay.isShowing, "再次显示重建动画视图")
check(overlay.phaseTitle == "长休息" && overlay.remaining == 60, "再次显示刷新阶段与倒计时")
weak var updatedWindow = show(duration: 1)
check(updatedWindow === secondWindow, "可见时更新休息引导不会创建重复窗口")
let secondHost = HostLifetime(window: secondWindow)
pump(1.6)
check(!overlay.isShowing && overlay.remaining == 0, "倒计时结束自动关闭")
check(secondHost.isReleased, "自动关闭后动画宿主视图可释放")
check(dismissals == 1 && callbackSawHiddenWindow, "自动结束清理窗口后仅回调一次")
hide()
check(dismissals == 1, "重复关闭不会重复回调")

let settings = AppSettings.shared
settings.focusSeconds = 60
settings.shortBreakSeconds = 60
let engine = TimerEngine(settings: settings)
engine.start()
engine.skip()
check(engine.state == .resting, "集成检查进入休息阶段")
weak var skippedWindow = show(duration: 60)
let skippedHost = HostLifetime(window: skippedWindow)
overlay.onDismiss = { engine.endBreak() }
hide()
pump(0.5)
check(engine.state == .running && engine.phase == .focus, "跳过休息后继续专注")
check(skippedHost.isReleased, "跳过休息释放动画视图")
engine.stopAll()

// Callbacks may immediately show another rest window.
weak var reentrantWindow = show(duration: 60)
let reentrantHost = HostLifetime(window: reentrantWindow)
overlay.onDismiss = { _ = show(duration: 60, phase: .longBreak) }
hide()
pump(0.5)
check(reentrantHost.isReleased, "回调重开前旧动画视图可释放")
check(overlay.isShowing && overlay.phaseTitle == "长休息", "关闭回调可安全重开引导")
overlay.onDismiss = nil
hide(notify: false)

if failures.isEmpty {
    print("休息引导生命周期验证通过：\(checks) 项检查")
    exit(0)
}
print("休息引导生命周期验证失败：\(failures.count)/\(checks)")
exit(1)
