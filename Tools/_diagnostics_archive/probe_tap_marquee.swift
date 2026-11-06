import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// 决定性实验：验证「用 CGEvent tap 吞掉落在指定矩形内的鼠标事件」
/// 能否阻止 Finder 在桌面上画出多选矩形（marquee）。
///
/// 背景：
///   - 挂件窗口在**桌面图标层之下**（-2147483604），Finder 的桌面窗口在图标层（-2147483603）
///     且铺满全屏 → 点击挂件时穿透给 Finder → Finder 开始框选 → 画出矩形。
///   - 负层级窗口收不到鼠标事件（已实测确认），
///     所以解决办法是**在事件层面拦截**：用 session 级 event tap 把
///     落在挂件矩形内的事件吞掉，Finder 根本收不到，自然不会画矩形。
///
/// 实验设计（A/B 对照）：
///   组 A：不吞事件，在桌面空白处拖拽 → 期望出现 marquee
///   组 B：吞掉矩形内的 down/dragged/up，同样拖拽 → 期望没有 marquee
///
/// 判定：marquee 出现时，拖拽路径包围盒内相对基线帧会有大面积像素变化；
///       没有 marquee 时（且隐藏光标）该区域应几乎不变。
///
/// 用法：swift Tools/probe_tap_marquee.swift

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

// MARK: - 全局状态

let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame          // 主显示器 AppKit 坐标（左下原点）
let primaryHeight = screenFrame.height

/// Quartz 全局坐标（原点：主屏左上，y 向下） → AppKit 全局坐标（左下原点）
func toAppKit(_ quartz: CGPoint) -> NSPoint {
    NSPoint(x: quartz.x, y: primaryHeight - quartz.y)
}

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 测试用的「挂件矩形」（AppKit 坐标）
var swallowRect = NSRect.zero
var swallowEnabled = false
var swallowedCount = 0
var tapInstalled = false

let tapMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
    | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

let tapCallback: CGEventTapCallBack = { _, _, event, _ in
    guard swallowEnabled else { return Unmanaged.passUnretained(event) }
    let appkit = toAppKit(event.location)
    if swallowRect.contains(appkit) {
        swallowedCount += 1
        return nil                       // 吞掉事件：Finder 收不到
    }
    return Unmanaged.passUnretained(event)
}

func installTap() {
    guard !tapInstalled else { return }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest: tapMask,
                                     callback: tapCallback,
                                     userInfo: nil) else {
        print("❌ 事件 tap 创建失败（需要辅助功能授权）")
        return
    }
    tapInstalled = true
    let rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("✅ 事件 tap 已安装")
}

/// 统计「相对基线帧，区域内变化像素数」
func changedPixels(_ base: CGImage, _ frame: CGImage, rectPx: CGRect) -> Int {
    guard let a = base.cropping(to: rectPx), let b = frame.cropping(to: rectPx) else { return -1 }
    let w = a.width, h = a.height
    func bytes(_ img: CGImage) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = out.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? out : nil
    }
    guard let ba = bytes(a), let bb = bytes(b) else { return -1 }
    var count = 0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        if d > 24 { count += 1 }
    }
    return count
}

// MARK: - 测试区域（桌面左侧空白条，避开 VSCode 大窗口与通知中心）

/// CG 坐标（左上原点）下的拖拽起点与终点
let dragStartCG = CGPoint(x: 120, y: 1220)
let dragEndCG = CGPoint(x: 260, y: 820)

/// 关注区域（CG 坐标）：marquee 会画在这里
let regionCG = CGRect(x: 40, y: 700, width: 280, height: 620)

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        print("主屏 AppKit frame = \(screenFrame)")
        print("图标层 = \(iconLevel)")
        print("AX 信任 = \(AXIsProcessTrusted())")

        // 确认测试点确实没有被普通 App 窗口遮挡
        let blockers = content.windows.filter { $0.windowLayer > iconLevel && $0.isOnScreen }
        for p in [dragStartCG, dragEndCG] {
            let covered = blockers.filter { $0.frame.contains(p) }
            print("测试点 \(p) 被遮挡: \(covered.map { "\($0.owningApplication?.applicationName ?? "?")" })")
        }

        installTap()

        let display = content.displays.first!
        // 半分辨率采集，减少开销
        let outW = Int(Double(display.width) / 2)
        let outH = Int(Double(display.height) / 2)
        let scale = 0.5

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = outW
        config.height = outH
        config.showsCursor = false
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let rec = Recorder(stream: stream)
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        print("录制中…（输出 \(outW)x\(outH)）")

        let regionPx = CGRect(x: regionCG.minX * scale, y: regionCG.minY * scale,
                              width: regionCG.width * scale, height: regionCG.height * scale)

        func simulateDrag() {
            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(dragStartCG)
            pump(0.3)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: dragStartCG, mouseButton: .left) {
                d.post(tap: .cghidEventTap)
            }
            pump(0.12)
            for i in 1...20 {
                let t = Double(i) / 20.0
                let x = dragStartCG.x + (dragEndCG.x - dragStartCG.x) * t
                let y = dragStartCG.y + (dragEndCG.y - dragStartCG.y) * t
                if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                                   mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                    e.post(tap: .cghidEventTap)
                }
                pump(0.03)
            }
            pump(0.5)
            if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                               mouseCursorPosition: dragEndCG, mouseButton: .left) {
                u.post(tap: .cghidEventTap)
            }
            pump(0.5)
        }

        // --- 组 A：对照组，不吞 ---
        swallowEnabled = false
        pump(1.2)
        let aBase = rec.frames.count
        pump(0.4)
        let aStart = rec.frames.count
        simulateDrag()
        let aEnd = rec.frames.count
        pump(0.6)

        // --- 组 B：实验组，吞掉矩形内事件 ---
        // 吞掉区域覆盖整条拖拽路径
        swallowRect = NSRect(x: 60, y: toAppKit(dragEndCG).y - 40,
                             width: 260, height: 500)
        swallowEnabled = true
        swallowedCount = 0
        pump(1.2)
        let bBase = rec.frames.count
        pump(0.4)
        let bStart = rec.frames.count
        simulateDrag()
        let bEnd = rec.frames.count
        pump(0.6)
        swallowEnabled = false

        try stream.removeStreamOutput(rec, type: .screen)
        try await stream.stopCapture()

        func peak(baseIndex: Int, range: Range<Int>) -> Int {
            guard baseIndex < rec.frames.count else { return -1 }
            let base = rec.frames[baseIndex]
            var best = 0
            for i in range {
                let c = changedPixels(base, rec.frames[i], rectPx: regionPx)
                if c > best { best = c }
            }
            return best
        }

        let aMax = peak(baseIndex: aBase, range: aStart..<aEnd)
        let bMax = peak(baseIndex: bBase, range: bStart..<bEnd)

        print("")
        print("=== 拖拽路径区域「相对基线变化的像素数」峰值 ===")
        print("对照组 A（不吞事件）: \(aMax)")
        print("实验组 B（吞掉事件）: \(bMax)   已吞事件数=\(swallowedCount)")
        print("")

        if aMax > 800 {
            if bMax < aMax / 3 {
                print("✅ 吞掉事件后矩形消失 —— 方案可行")
            } else {
                print("⚠️ 吞事件后仍有大面积变化（\(aMax) → \(bMax)），需要进一步分析")
            }
        } else {
            print("❓ 对照组未检出 marquee（aMax=\(aMax)），测试点可能不在桌面可见区")
        }
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
