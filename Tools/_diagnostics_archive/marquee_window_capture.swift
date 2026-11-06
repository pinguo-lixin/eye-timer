import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 直接截取 **Finder 桌面窗口**本身（ScreenCaptureKit 版）。
///
/// ## 为什么这样能绕过遮挡
///
/// 桌面的框选矩形是 **Finder 在它自己的桌面窗口里画的**。
/// 用「只针对该窗口」的 content filter 截图，矩形必然在里面 ——
/// 完全不受「其它 App 窗口盖在上面」的影响。
///
/// 用法：swift Tools/marquee_window_capture.swift <输出png> <sx> <sy> <ex> <ey>

let args = CommandLine.arguments
guard args.count >= 6 else {
    print("用法: marquee_window_capture <输出png> <sx> <sy> <ex> <ey>")
    exit(1)
}
let outPath = args[1]
let sx = Double(args[2])!, sy = Double(args[3])!
let ex = Double(args[4])!, ey = Double(args[5])!

let src = CGEventSource(stateID: .hidSystemState)

func pump(_ s: Double) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 截取 Finder 桌面窗口并裁剪出拖拽区域
func captureFinderDesktop(_ path: String) async -> Bool {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { w in
            (w.owningApplication?.bundleIdentifier ?? "") == "com.apple.finder" && w.frame.width > 2000
        }) else {
            print("   （找不到 Finder 桌面窗口）")
            return false
        }

        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        // 按像素 1:1 截取整窗，再自己裁剪
        config.sourceResolution = CGSize(width: target.frame.width, height: target.frame.height)
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        print("   窗口图像: \(image.width)x\(image.height)  (窗口 \(target.frame))")

        let crop = CGRect(x: min(sx, ex) - target.frame.minX - 120,
                           y: min(sy, ey) - target.frame.minY - 120,
                           width: abs(ex - sx) + 240,
                           height: abs(ey - sy) + 240)
        guard let cropped = image.cropping(to: crop) else {
            print("   （裁剪失败）")
            return false
        }
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        guard let dest else { return false }
        CGImageDestinationAddImage(dest, cropped, nil)
        guard CGImageDestinationFinalize(dest) else { return false }
        print("   已保存 \(path) (\(cropped.width)x\(cropped.height))")
        return true
    } catch {
        print("   （截图失败: \(error)）")
        return false
    }
}

// 拖拽前
print("=== 拖拽前 ===")
_ = await captureFinderDesktop("/tmp/win_base.png")

// 拖拽
CGAssociateMouseAndMouseCursorPosition(1)
CGWarpMouseCursorPosition(CGPoint(x: sx, y: sy))
pump(0.7)
if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                  mouseCursorPosition: CGPoint(x: sx, y: sy), mouseButton: .left) {
    d.post(tap: .cghidEventTap)
}
pump(0.3)
for i in 1...18 {
    let t = Double(i) / 18.0
    let p = CGPoint(x: sx + (ex - sx) * t, y: sy + (ey - sy) * t)
    if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                       mouseCursorPosition: p, mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
    pump(0.045)
}
pump(0.5)

print("=== 拖拽中 ===")
let ok = await captureFinderDesktop(outPath)

if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                   mouseCursorPosition: CGPoint(x: ex, y: ey), mouseButton: .left) {
    u.post(tap: .cghidEventTap)
}
pump(0.7)

exit(ok ? 0 : 2)
