import Foundation
import CoreGraphics
import ImageIO
import AppKit
import ScreenCaptureKit

/// 用 ScreenCaptureKit 校验挂件层级并截图。
///
/// 注意：`CGWindowListCopyWindowInfo` 对超低层级窗口会错误地报告 level=0，
/// 真实层级必须用 `SCShareableContent` 查。
///
/// 用法：swift Tools/sc_verify.swift [截图输出路径]
@available(macOS 13.0, *)
final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    let stream: SCStream
    var output: CGImage?
    var done = false

    init(stream: SCStream) {
        self.stream = stream
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext()
        if let cg = ctx.createCGImage(image, from: image.extent) {
            output = cg
            done = true
        }
    }
}

func fail(_ msg: String) -> Never {
    print("❌ \(msg)")
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("=== 可见窗口层级（ScreenCaptureKit 权威值）===")

        var eyeTimerWindow: SCWindow?
        for w in content.windows {
            let appName = w.owningApplication?.applicationName ?? "?"
            let bundleId = w.owningApplication?.bundleIdentifier ?? "?"
            let isEyeTimer = bundleId.contains("eyetimer") || appName.contains("EyeTimer")
            if isEyeTimer { eyeTimerWindow = w }
            let flag = isEyeTimer ? "  <<< EyeTimer" : ""
            print(String(format: "  %-26s %-24s level=%-13d onScreen=%@%@",
                         (appName as NSString).utf8String!,
                         (bundleId as NSString).utf8String!,
                         w.windowLayer,
                         w.isOnScreen ? "YES" : "no",
                         flag))
        }

        guard let target = eyeTimerWindow else {
            print("❌ 未找到 EyeTimer 窗口")
            exit(1)
        }

        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        print("\n=== 层级校验 ===")
        print("壁纸层        = \(desktopLevel)")
        print("桌面图标层    = \(iconLevel)")
        print("EyeTimer 挂件 = \(target.windowLayer)")

        if target.windowLayer <= desktopLevel {
            fail("挂件层级低于壁纸层，会被壁纸完全遮住")
        }
        if target.windowLayer >= iconLevel {
            fail("挂件层级高于桌面图标层，会遮挡桌面图标")
        }
        if target.windowLayer < iconLevel - 1 {
            fail("挂件层级低于 '图标层-1'，会被 Finder 桌面背景窗口挡住，导致无法点击拖拽")
        }
        print("✅ 挂件正确夹在桌面背景与桌面图标之间（可点击、不挡图标）")

        // 截图：找到挂件所在的那块显示器
        let windowFrame = target.frame
        guard let display = content.displays.first(where: { display in
            display.frame.contains(CGPoint(x: windowFrame.midX, y: windowFrame.midY))
        }) ?? content.displays.first else {
            fail("找不到挂件所在显示器")
        }
        print("\n挂件所在显示器 id=\(display.displayID) frame=\(display.frame)")

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.showsCursor = false
        config.captureResolution = .best

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let capture = Capture(stream: stream)
        try stream.addStreamOutput(capture, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try stream.removeStreamOutput(capture, type: .screen)
        try await stream.stopCapture()

        guard let image = capture.output else {
            fail("截图失败")
        }

        if CommandLine.arguments.count > 1 {
            let path = CommandLine.arguments[1]
            let url = URL(fileURLWithPath: path)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                fail("无法创建图片输出")
            }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("✅ 已保存全屏截图: \(path)")
        } else {
            print("✅ 截图完成（未指定输出路径）")
        }

        semaphore.signal()
    } catch {
        print("❌ 出错: \(error)")
        exit(1)
    }
}

semaphore.wait()
