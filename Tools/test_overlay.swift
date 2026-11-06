import AppKit

/// 测试辅助：在指定区域开一个普通层级(level 0)的窗口，用来验证
/// 「挂件被别的 App 窗口覆盖时不应抢走点击」。
///
/// 用法：swift Tools/test_overlay.swift <x> <y> <w> <h>

let args = CommandLine.arguments
let x = Double(args.count > 1 ? args[1] : "0")!
let y = Double(args.count > 2 ? args[2] : "0")!
let w = Double(args.count > 3 ? args[3] : "400")!
let h = Double(args.count > 4 ? args[4] : "400")!

final class Delegate: NSObject, NSApplicationDelegate {
    var win: NSWindow?
    func applicationDidFinishLaunching(_ n: Notification) {
        let win = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "EyeTimer 覆盖测试窗"
        win.backgroundColor = NSColor.systemPink
        win.level = .normal
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.win = win
    }
}
let d = Delegate()
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.delegate = d
NSApplication.shared.run()
