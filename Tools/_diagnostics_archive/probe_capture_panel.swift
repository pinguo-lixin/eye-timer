import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// 探针：验证「图标层之上的透明输入捕获窗」能否
///   1. 收到 mouseDown / mouseDragged / mouseUp；
///   2. 阻止 Finder 在桌面上画出多选矩形（marquee）。
///
/// 对照实验：
///   组 A（对照组）  ：不放捕获窗，直接在桌面空白处拖拽 → 期望出现 marquee
///   组 B（实验组）  ：放置透明捕获窗（iconLevel+1），同样拖拽 → 期望没有 marquee
///
/// 判定指标：不看颜色，而是看**拖拽路径矩形内相对拖拽前基线帧发生变化的像素数**。
/// marquee 出现时该区域会有大面积变化；没有 marquee 时区域几乎不变。
///
/// 用法：swift Tools/probe_capture_panel.swift

final class CaptureView: NSView {
    let label: String
    init(tag: String) {
        self.label = tag
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        print("  ✅ mouseDown  (tag=\(label))")
        fflush(stdout)
    }
    override func mouseDragged(with event: NSEvent) {
        print("  ↪️  mouseDragged (tag=\(label))")
        fflush(stdout)
    }
    override func mouseUp(with event: NSEvent) {
        print("  ✅ mouseUp    (tag=\(label))")
        fflush(stdout)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) { return self }
        return super.hitTest(point)
    }
}

@available(macOS 13.0, *)
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    let stream: SCStream
    var frames: [CGImage] = []
    init(stream: SCStream) {
        self.stream = stream
        super.init()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext()
        if let cg = ctx.createCGImage(image, from: image.extent) {
            frames.append(cg)
        }
    }
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame

func cg(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: screenFrame.maxY - p.y) }

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 找出上方没有普通 App 窗口覆盖的桌面点
func emptyDesktopPoint(blockers: [SCWindow]) -> NSPoint? {
    let step: Double = 43
    for iy in 0..<28 {
        for ix in 0..<70 {
            let fx = 150.0 + Double(ix) * step
            let fy = 150.0 + Double(iy) * step
            let p = NSPoint(x: fx, y: fy)
            guard screenFrame.contains(p) else { continue }
            let gp = cg(p)
            let covered = blockers.contains { $0.frame.contains(gp) }
            if !covered { return p }
        }
    }
    return nil
}

/// 计算「相对基线帧，指定区域内发生变化的像素数」
func changedPixels(_ a: CGImage, _ b: CGImage, rectInPoints: CGRect, scale: Double) -> Int {
    let px = Int(rectInPoints.minX * scale)
    let py = Int(rectInPoints.minY * scale)
    let pw = max(1, Int(rectInPoints.width * scale))
    let ph = max(1, Int(rectInPoints.height * scale))

    func bytes(_ img: CGImage) -> [UInt8]? {
        guard let cropped = img.cropping(to: CGRect(x: px, y: py, width: pw, height: ph)) else { return nil }
        var out = [UInt8](repeating: 0, count: pw * ph * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = out.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: pw, height: ph,
                                      bitsPerComponent: 8, bytesPerRow: pw * 4,
                                      space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: pw, height: ph))
            return true
        }
        return ok ? out : nil
    }
    guard let ba = bytes(a), let bb = bytes(b) else { return -1 }
    var count = 0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i])) + abs(Int(ba[i+1]) - Int(bb[i+1])) + abs(Int(ba[i+2]) - Int(bb[i+2]))
        if d > 24 { count += 1 }
    }
    return count
}

func makeCaptureWindow(at point: NSPoint, size: NSSize, level: Int, tag: String) -> NSWindow {
    let origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered,
                       defer: false)
    win.level = NSWindow.Level(level)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = false
    win.ignoresMouseEvents = false
    win.hidesOnDeactivate = false
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    let v = CaptureView(tag: tag)
    v.frame = NSRect(origin: .zero, size: size)
    win.contentView = v
    win.orderFrontRegardless()
    return win
}

func simulateDrag(from: NSPoint, to: NSPoint, steps: Int = 20) {
    let a = cg(from), b = cg(to)
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(a)
    pump(0.25)
    if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                      mouseCursorPosition: a, mouseButton: .left) {
        d.post(tap: .cghidEventTap)
    }
    pump(0.12)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let x = a.x + (b.x - a.x) * t
        let y = a.y + (b.y - a.y) * t
        if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                           mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        pump(0.025)
    }
    pump(0.4)
    if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                       mouseCursorPosition: b, mouseButton: .left) {
        u.post(tap: .cghidEventTap)
    }
    pump(0.4)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("屏幕 frame = \(screenFrame)")
        print("图标层 = \(iconLevel)")
        print("AX 信任 = \(AXIsProcessTrusted())")

        // 只把普通 App 窗口（level > 图标层）视为遮挡物
        let blockers = content.windows.filter { $0.windowLayer > iconLevel && $0.isOnScreen }
        guard let pt = emptyDesktopPoint(blockers: blockers) else {
            print("❌ 找不到空旷桌面点"); exit(1)
        }
        print("空旷桌面点 (AppKit) = \(pt)")
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        print("拖拽前前台 App = \(front)\n")

        let display = content.displays.first(where: {
            $0.frame.contains(CGPoint(x: screenFrame.midX, y: screenFrame.midY))
        }) ?? content.displays.first!
        let scale = Double(display.width) / Double(screenFrame.width)
        print("显示器 scale = \(scale)  frame = \(display.frame)\n")

        // 录制
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

        // 拖拽路径（屏幕点，左下原点）
        let from = pt
        let to = NSPoint(x: pt.x + 380, y: pt.y - 260)
        // 路径包围盒（AppKit 坐标）→ 转成 CG 像素坐标（左上原点）
        let pathRect = CGRect(x: min(from.x, to.x) - 30, y: min(from.y, to.y) - 30,
                              width: abs(to.x - from.x) + 60, height: abs(to.y - from.y) + 60)
        let cgRect = CGRect(x: pathRect.minX,
                            y: screenFrame.maxY - pathRect.maxY,
                            width: pathRect.width,
                            height: pathRect.height)

        // --- 组 A：对照组，无捕获窗 ---
        pump(1.0)
        let aBaseline = rec.frames.count
        pump(0.5)
        let aStart = rec.frames.count
        simulateDrag(from: from, to: to)
        let aEnd = rec.frames.count
        pump(0.6)

        // --- 组 B：实验组，透明捕获窗 ---
        let capWin = makeCaptureWindow(at: from, size: NSSize(width: 140, height: 140),
                                        level: iconLevel + 1, tag: "capture")
        pump(1.0)
        let bBaseline = rec.frames.count
        pump(0.5)
        let bStart = rec.frames.count
        simulateDrag(from: from, to: to)
        let bEnd = rec.frames.count
        pump(0.6)

        try stream.removeStreamOutput(rec, type: .screen)
        try await stream.stopCapture()
        capWin.orderOut(nil)

        func maxChanged(baseIndex: Int, range: Range<Int>) -> Int {
            guard baseIndex < rec.frames.count else { return -1 }
            let base = rec.frames[baseIndex]
            var best = 0
            for i in range {
                let c = changedPixels(base, rec.frames[i], rectInPoints: cgRect, scale: scale)
                if c > best { best = c }
            }
            return best
        }

        let aMax = maxChanged(baseIndex: aBaseline, range: aStart..<aEnd)
        let bMax = maxChanged(baseIndex: bBaseline, range: bStart..<bEnd)

        print("")
        print("=== 拖拽路径区域「相对基线发生变化的像素数」峰值 ===")
        print("对照组（无捕获窗，Finder 可见）: \(aMax)")
        print("实验组（有透明捕获窗）        : \(bMax)")
        print("")

        if aMax > 500 && bMax < aMax / 3 {
            print("✅ 透明捕获窗成功阻止了 Finder 的多选矩形")
        } else if aMax > 500 {
            print("⚠️ 捕获窗未能消除矩形（对照组 \(aMax) vs 实验组 \(bMax)）")
        } else {
            print("❓ 对照组未出现矩形（aMax=\(aMax)），可能坐标不对")
        }
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
