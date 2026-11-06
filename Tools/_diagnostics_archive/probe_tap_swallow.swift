import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// 决定性实验：用 CGEvent tap 在**事件层**吞掉落在矩形内的鼠标事件，
/// 验证能否彻底消除 Finder 的桌面框选矩形。
///
/// 这是当前唯一可靠的路线：
///   - 负层级窗口（桌面图标层之下）**完全不参与鼠标命中测试**
///     （实测 `hitTest` 从未被调用），所以「再放一块高一点的透明窗」解决不了；
///   - 但 `CGEvent.tapCreate` 可用（AX 权限已授予），
///     能在事件派发给 Finder **之前**把它吞掉 → Finder 收不到 → 不画矩形。
///
/// 实验设计（A/B）：
///   组 A：不吞事件，在桌面空白处拖拽 → 期望出现 marquee
///   组 B：吞掉矩形内的 down/dragged/up，同样拖拽 → 期望没有 marquee
///
/// 判定：比较「拖拽路径包围盒」在基线帧与拖拽帧之间的差异。
/// marquee 是半透明蓝色填充，会造成大面积变化。
///
/// 用法：swift Tools/probe_tap_swallow.swift

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

let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame
let primaryHeight = screenFrame.height

/// Quartz 全局坐标（左上原点） → AppKit 全局坐标（左下原点）
func toAppKit(_ q: CGPoint) -> NSPoint {
    NSPoint(x: q.x, y: primaryHeight - q.y)
}

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func capture(to path: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-t", "png", path]
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
    catch { return false }
}

func loadImage(_ path: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

func changedCount(_ a: CGImage, _ b: CGImage, rectPx: CGRect) -> Int {
    guard let ca = a.cropping(to: rectPx), let cb = b.cropping(to: rectPx) else { return -1 }
    let w = ca.width, h = ca.height
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
    guard let ba = bytes(ca), let bb = bytes(cb) else { return -1 }
    var n = 0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        if d > 24 { n += 1 }
    }
    return n
}

// MARK: - 事件 tap 状态

var swallowRect = NSRect.zero
var swallowEnabled = false
var swallowedCount = 0

let tapMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
    | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

let tapCallback: CGEventTapCallBack = { _, _, event, _ in
    guard swallowEnabled else { return Unmanaged.passUnretained(event) }
    if swallowRect.contains(toAppKit(event.location)) {
        swallowedCount += 1
        return nil                       // 吞掉：Finder 收不到
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - 测试区域：屏幕左下角一块空白（避开其他 App 窗口）

/// 拖拽路径（AppKit 坐标，左下原点）—— 用探针找到的裸桌面点附近
let dragStart = NSPoint(x: 3180, y: 1240)
let dragEnd = NSPoint(x: 2780, y: 900)

/// 关注区域（AppKit 坐标）
let region = NSRect(x: 2720, y: 840, width: 520, height: 460)

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        print("主屏 frame = \(screenFrame)")
        print("AX 信任 = \(AXIsProcessTrusted())")

        // 确认测试区域上方没有普通 App 窗口
        let blockers = content.windows.filter { $0.windowLayer > iconLevel && $0.isOnScreen }
        let cgStart = CGPoint(x: dragStart.x, y: primaryHeight - dragStart.y)
        let cgEnd = CGPoint(x: dragEnd.x, y: primaryHeight - dragEnd.y)
        print("测试起点被遮挡: \(blockers.filter { $0.frame.contains(cgStart) }.map { "\($0.owningApplication?.applicationName ?? "?")" })")
        print("测试终点被遮挡: \(blockers.filter { $0.frame.contains(cgEnd) }.map { "\($0.owningApplication?.applicationName ?? "?")" })")

        // 安装 tap
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: tapMask,
                                          callback: tapCallback,
                                          userInfo: nil) else {
            print("❌ tap 创建失败"); exit(1)
        }
        let rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ 事件 tap 已安装")

        func simulateDrag() {
            let a = CGPoint(x: dragStart.x, y: primaryHeight - dragStart.y)
            let b = CGPoint(x: dragEnd.x, y: primaryHeight - dragEnd.y)
            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(a)
            pump(0.35)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: a, mouseButton: .left) {
                d.post(tap: .cghidEventTap)
            }
            pump(0.15)
            for i in 1...20 {
                let t = Double(i) / 20.0
                let x = a.x + (b.x - a.x) * t
                let y = a.y + (b.y - a.y) * t
                if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                                   mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                    e.post(tap: .cghidEventTap)
                }
                pump(0.03)
            }
            pump(0.5)
            if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                               mouseCursorPosition: b, mouseButton: .left) {
                u.post(tap: .cghidEventTap)
            }
            pump(0.5)
        }

        // ---- 组 A：对照组，不吞 ----
        swallowEnabled = false
        let baseA = "/tmp/probe_A_base.png", duringA = "/tmp/probe_A_during.png"
        _ = capture(to: baseA)
        pump(0.5)
        simulateDrag()
        _ = capture(to: duringA)
        pump(0.5)

        // ---- 组 B：实验组，吞掉矩形内事件 ----
        swallowRect = region
        swallowEnabled = true
        swallowedCount = 0
        let baseB = "/tmp/probe_B_base.png", duringB = "/tmp/probe_B_during.png"
        _ = capture(to: baseB)
        pump(0.5)
        simulateDrag()
        _ = capture(to: duringB)
        swallowEnabled = false
        pump(0.5)

        // ---- 分析 ----
        guard let ia = loadImage(baseA), let ib = loadImage(duringA),
              let ic = loadImage(baseB), let id = loadImage(duringB) else {
            print("❌ 图片读取失败"); exit(1)
        }
        let pxScale = Double(ia.width) / Double(screenFrame.width)
        // CG 坐标（左上原点）
        let regionCG = CGRect(x: region.minX,
                              y: primaryHeight - region.maxY,
                              width: region.width,
                              height: region.height)
        let regionPx = CGRect(x: regionCG.minX * pxScale, y: regionCG.minY * pxScale,
                              width: regionCG.width * pxScale, height: regionCG.height * pxScale)
        let total = Int(regionPx.width) * Int(regionPx.height)

        let aCount = changedCount(ia, ib, rectPx: regionPx)
        let bCount = changedCount(ic, id, rectPx: regionPx)

        print("")
        print("=== 拖拽区域差异（区域 \(Int(regionPx.width))x\(Int(regionPx.height)) = \(total) px）===")
        print("对照组 A（不吞事件）: \(aCount) 变化像素 (\(String(format: "%.1f%%", Double(aCount) / Double(total) * 100)))")
        print("实验组 B（吞掉事件）: \(bCount) 变化像素 (\(String(format: "%.1f%%", Double(bCount) / Double(total) * 100)))  已吞=\(swallowedCount)")
        print("")

        if aCount > 2000 && bCount < aCount / 4 {
            print("✅ 吞掉事件后矩形消失 —— 事件层拦截方案可行")
            exit(0)
        } else if aCount <= 2000 {
            print("❓ 对照组没检出矩形（aCount=\(aCount)），测试区域选点可能不对")
            exit(3)
        } else {
            print("⚠️ 吞事件后仍有大面积变化（\(aCount) → \(bCount)）")
            exit(2)
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
