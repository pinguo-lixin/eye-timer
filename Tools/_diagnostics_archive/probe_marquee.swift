import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// 对照实验：验证「用事件 tap 吞掉 mouseDown」能否消除 Finder 的桌面多选矩形。
///
/// 做法：
///   1. 用 ScreenCaptureKit 连续录制桌面区域；
///   2. 第 1 次拖拽：不吞事件（对照组）→ 期望看到 marquee；
///   3. 第 2 次拖拽：用 event tap 吞掉 down/drag/up（实验组）→ 期望看不到 marquee；
///   4. 逐帧分析「蓝色调」（B-R）峰值，判断 marquee 是否出现。
///
/// marquee 是半透明蓝色填充，会显著抬高区域内 B-R。
///
/// 用法：swift Tools/probe_marquee.swift

@available(macOS 13.0, *)
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    let stream: SCStream
    var frames: [CGImage] = []
    var done = false

    init(stream: SCStream) {
        self.stream = stream
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return }
        frames.append(cg)
        if frames.count >= 180 { done = true }
    }
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame
print("屏幕 frame = \(screenFrame)  图标层 = \(iconLevel)")
print("AX 信任 = \(AXIsProcessTrusted())")

/// CG 全局点
func cg(_ p: NSPoint) -> CGPoint {
    CGPoint(x: p.x, y: screenFrame.maxY - p.y)
}

func wait(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 蓝色调（B-R）均值与峰值：marquee 出现时会明显升高
func blueStats(_ img: CGImage) -> (mean: Double, max: Double) {
    let w = img.width, h = img.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let drew: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drew else { return (0, 0) }
    var sum = 0.0, peak = 0.0, n = 0.0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let b = Double(pixels[i + 2]) - Double(pixels[i])
        sum += b; n += 1
        peak = max(peak, b)
    }
    return (sum / n, peak)
}

var swallowClicks = false
var tapOK = false

let tapMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
    | (1 << CGEventType.leftMouseDragged.rawValue)
    | (1 << CGEventType.leftMouseUp.rawValue)

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if swallowClicks {
        return nil   // 吞掉事件
    }
    return Unmanaged.passUnretained(event)
}

if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                              place: .headInsertEventTap,
                              options: .defaultTap,
                              eventsOfInterest: tapMask,
                              callback: tapCallback,
                              userInfo: nil) {
    tapOK = true
    let rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("事件 tap: ✅ 创建成功")
} else {
    print("事件 tap: ❌ 创建失败")
}

/// 模拟一次拖拽（不吞 / 吞 由 swallowClicks 控制）
func simulateDrag(from: NSPoint, to: NSPoint, steps: Int = 24) {
    let a = cg(from), b = cg(to)
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(a)
    wait(0.2)
    if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                      mouseCursorPosition: a, mouseButton: .left) {
        d.post(tap: .cghidEventTap)
    }
    wait(0.15)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let x = a.x + (b.x - a.x) * t
        let y = a.y + (b.y - a.y) * t
        if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                           mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        wait(0.02)
    }
    wait(0.35)   // 拖拽中停一下，让录制抓到 marquee
    if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                       mouseCursorPosition: b, mouseButton: .left) {
        u.post(tap: .cghidEventTap)
    }
    wait(0.3)
}

// 桌面空白处（避开 Dock、EyeTimer 挂件）
let start = NSPoint(x: 700, y: 700)
let end = NSPoint(x: 1300, y: 400)

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: {
            $0.frame.contains(CGPoint(x: screenFrame.midX, y: screenFrame.midY))
        }) ?? content.displays.first else {
            print("找不到显示器"); exit(1)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.showsCursor = false
        config.captureResolution = .best

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let rec = Recorder(stream: stream)
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        print("录制中…")

        // --- 对照组：不吞 ---
        swallowClicks = false
        wait(1.2)
        let groupAStart = rec.frames.count
        simulateDrag(from: start, to: end)
        let groupAEnd = rec.frames.count
        wait(0.8)

        // --- 实验组：吞掉 ---
        swallowClicks = true
        wait(1.0)
        let groupBStart = rec.frames.count
        simulateDrag(from: start, to: end)
        let groupBEnd = rec.frames.count
        wait(0.8)

        try stream.removeStreamOutput(rec, type: .screen)
        try await stream.stopCapture()

        func peak(_ range: Range<Int>) -> (mean: Double, max: Double, n: Int) {
            guard !range.isEmpty else { return (0, 0, 0) }
            var best = (mean: 0.0, max: 0.0, n: 0)
            for i in range {
                let s = blueStats(rec.frames[i])
                if s.max > best.max { best = (s.mean, s.max, range.count) }
            }
            return best
        }

        let a = peak(groupAStart..<groupAEnd)
        let b = peak(groupBStart..<groupBEnd)
        print("")
        print("=== 拖拽区域蓝色调 (B-R) 峰值 ===")
        print(String(format: "对照组（不吞事件）: 峰值 B-R = %.2f", a.max))
        print(String(format: "实验组（吞掉事件）: 峰值 B-R = %.2f", b.max))
        print("")

        if a.max > b.max + 8 {
            print("✅ 吞掉事件后蓝色调峰值显著下降 → marquee 已被消除")
        } else if a.max > 3 {
            print("⚠️ 差异不明显，需要进一步检查")
        } else {
            print("❓ 对照组也没出现 marquee（可能坐标选到了空白区域）")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
