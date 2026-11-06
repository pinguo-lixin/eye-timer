import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// A/B 对照（可靠版）：在挂件上真实拖拽，用**独立的辅助抓屏进程**持续抓帧，
/// 避免主进程 `Process.run()` 与 run loop 互相干扰导致抓不到实时画面。
///
/// ## 流程
///
/// 1. 起一个后台 shell 循环，每 0.25s 抓一张图（带序号）；
/// 2. 在主进程做真实拖拽（挂件上按下 → 拖 → 停住 → 继续 → 松开）；
/// 3. 停掉抓屏循环；
/// 4. 找出「拖拽期间」的那几张图，与拖拽前的基线对比。
///
/// ## 判据
///
/// Finder 的框选矩形 = **半透明蓝色填充 + 亮边**。
/// 桌面图标的蓝色标签是**高饱和**纯蓝，且面积小。
/// 用「低饱和蓝像素数」区分两者。
///
/// 用法：swift Tools/marquee_ab2_test.swift

let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func loadImage(_ path: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

struct Stats {
    var changed = 0
    var lowSat = 0
    var highSat = 0
    var blueMean = 0.0
}

func analyze(_ a: CGImage, _ b: CGImage, rectPx: CGRect) -> Stats {
    var r = Stats()
    guard let ca = a.cropping(to: rectPx), let cb = b.cropping(to: rectPx) else { return r }
    let w = ca.width, h = ca.height
    func bytes(_ img: CGImage) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = out.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? out : nil
    }
    guard let ba = bytes(ca), let bb = bytes(cb) else { return r }
    var blueSum = 0.0, n = 0.0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        guard d > 24 else { continue }
        r.changed += 1
        let rr = Double(bb[i]), gg = Double(bb[i+1]), bl = Double(bb[i+2])
        let blue = bl - rr
        blueSum += blue; n += 1
        let mx = max(rr, max(gg, bl)), mn = min(rr, min(gg, bl))
        let sat = mx > 0 ? (mx - mn) / mx : 0
        if blue > 25 {
            if sat < 0.55 { r.lowSat += 1 } else { r.highSat += 1 }
        }
    }
    if n > 0 { r.blueMean = blueSum / n }
    return r
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        var widget: SCWindow?
        for w in content.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") && w.isOnScreen {
                if widget == nil || w.frame.width * w.frame.height > widget!.frame.width * widget!.frame.height {
                    widget = w
                }
            }
        }
        guard let widget else { print("❌ 未找到挂件窗口"); exit(1) }
        print("挂件: frame=\(widget.frame)")

        let start = CGPoint(x: widget.frame.midX, y: widget.frame.midY)
        var end = CGPoint(x: start.x - 360, y: start.y - 240)
        if end.x < 250 || end.y < 300 {
            end = CGPoint(x: start.x + 360, y: start.y + 240)
        }
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        print("拖拽: \(start) → \(end)")

        // ---- 起后台抓屏循环 ----
        let shotDir = "/tmp/mq_frames"
        try? FileManager.default.removeItem(atPath: shotDir)
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)

        let script = """
        i=0
        while [ ! -f "\(shotDir)/STOP" ]; do
            screencapture -x -t png "\(shotDir)/f_$(printf %03d $i).png" 2>/dev/null
            i=$((i+1))
            sleep 0.25
        done
        """
        let grabber = Process()
        grabber.executableURL = URL(fileURLWithPath: "/bin/bash")
        grabber.arguments = ["-c", script]
        grabber.standardOutput = FileHandle.nullDevice
        grabber.standardError = FileHandle.nullDevice
        try? grabber.run()

        // ---- 等抓到几帧基线 ----
        pump(1.6)

        // ---- 真实拖拽 ----
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(start)
        pump(0.5)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: start, mouseButton: .left) {
            d.post(tap: .cghidEventTap)
        }
        pump(0.2)

        // 拖到中途并**停住**（停住时矩形最明显）
        for i in 1...14 {
            let t = Double(i) / 14.0
            let x = start.x + (mid.x - start.x) * t
            let y = start.y + (mid.y - start.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.035)
        }
        pump(1.4)          // 在中途停 1.4 秒，让抓屏循环拍到矩形

        // 继续拖到终点
        for i in 1...10 {
            let t = Double(i) / 10.0
            let x = mid.x + (end.x - mid.x) * t
            let y = mid.y + (end.y - mid.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.035)
        }
        pump(0.3)
        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: end, mouseButton: .left) {
            u.post(tap: .cghidEventTap)
        }
        pump(1.0)

        // ---- 停止抓屏 ----
        try? "STOP".write(toFile: "\(shotDir)/STOP", atomically: true, encoding: .utf8)
        grabber.waitUntilExit()

        // ---- 分析所有帧 ----
        let files = (try? FileManager.default.contentsOfDirectory(atPath: shotDir))?
            .filter { $0.hasSuffix(".png") }
            .sorted() ?? []
        print("\n抓到 \(files.count) 帧")

        guard files.count > 3 else { print("❌ 帧数不足"); exit(1) }
        guard let baseImg = loadImage("\(shotDir)/\(files[0])") else { print("❌ 基线读取失败"); exit(1) }

        let pxScale = Double(baseImg.width) / Double(screenFrame.width)
        let region = CGRect(x: min(start.x, mid.x) - 120,
                            y: min(start.y, mid.y) - 120,
                            width: abs(mid.x - start.x) + 240,
                            height: abs(mid.y - start.y) + 240)
        let regionPx = CGRect(x: region.minX * pxScale, y: region.minY * pxScale,
                              width: region.width * pxScale, height: region.height * pxScale)
        let total = Int(regionPx.width) * Int(regionPx.height)

        var best = Stats()
        var bestIdx = -1
        for (i, f) in files.enumerated() {
            guard let img = loadImage("\(shotDir)/\(f)") else { continue }
            let s = analyze(baseImg, img, rectPx: regionPx)
            if s.changed > best.changed {
                best = s
                bestIdx = i
            }
        }

        print("\n=== 拖拽期间最大差异帧 ===")
        print("帧索引 = \(bestIdx) / \(files.count)")
        print("区域(像素): \(Int(regionPx.width))x\(Int(regionPx.height)) = \(total) px")
        print("变化像素数: \(best.changed) (\(String(format: "%.2f%%", Double(best.changed) / Double(max(1, total)) * 100)))")
        print("蓝色调均值: \(String(format: "%.1f", best.blueMean))")
        print("低饱和蓝像素（框选矩形特征）: \(best.lowSat)")
        print("高饱和蓝像素（图标标签特征）: \(best.highSat)")
        print("")

        if best.lowSat > 1200 {
            print("❌ 存在大面积低饱和蓝色填充 → 框选矩形存在")
            exit(2)
        } else {
            print("✅ 未见低饱和蓝色填充 → 无框选矩形")
            exit(0)
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
