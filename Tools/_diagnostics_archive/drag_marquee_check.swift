import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// 端到端验证：真实拖拽 EyeTimer 挂件，并检测桌面是否出现 Finder 的框选矩形。
///
/// 判定逻辑：
///   1. 用 ScreenCaptureKit 找到挂件窗口的精确位置；
///   2. 抓一张基线截图；
///   3. 按下并拖到中途（鼠标**仍按着**）—— 此时若 Finder 在画框选矩形就会出现在画面里；
///   4. 再抓一张截图，与基线逐像素对比**整块拖拽区域**；
///   5. 判定：出现大面积**半透明蓝色填充** → 框选矩形仍存在；
///            只有挂件自身在动 → 矩形已被消除。
///
/// 关键判据用**蓝色调**（B - R）：Finder 的框选矩形是蓝色半透明填充，
/// 会显著抬高 B-R；挂件自身的蓝色进度环面积很小。
///
/// 为了排除「光标移动」带来的干扰：
///   - 记录拖拽路径上光标自身的移动（已知），
///   - 同时报告「整图差异」与「区域差异」两个数字，便于交叉判断。
///
/// 用法：swift Tools/drag_marquee_check.swift

/// 分组标签：用于区分多次运行的基线/截图文件，避免互相覆盖
let label = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "run"

let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

@discardableResult
func captureScreen(to path: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-t", "png", path]
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0 && FileManager.default.fileExists(atPath: path)
    } catch {
        print("❌ screencapture 失败: \(error)")
        return false
    }
}

func loadImage(_ path: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

/// 统计两个图像在指定区域内的差异 + 蓝色调
func diffStats(_ a: CGImage, _ b: CGImage, rectPx: CGRect) -> (changed: Int, bluePeak: Double, blueMean: Double) {
    guard let ca = a.cropping(to: rectPx), let cb = b.cropping(to: rectPx) else { return (-1, 0, 0) }
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
    guard let ba = bytes(ca), let bb = bytes(cb) else { return (-1, 0, 0) }
    var changed = 0
    var bluePeak = 0.0
    var blueSum = 0.0
    var n = 0.0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        if d > 24 {
            changed += 1
            let bl = Double(bb[i + 2]) - Double(bb[i])
            bluePeak = max(bluePeak, bl)
            blueSum += bl
            n += 1
        }
    }
    return (changed, bluePeak, n > 0 ? blueSum / n : 0)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        var widget: SCWindow?
        for w in content.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") && w.isOnScreen {
                if widget == nil || w.frame.width * w.frame.height > widget!.frame.width * widget!.frame.height {
                    widget = w
                }
            }
        }
        guard let widget else {
            print("❌ 未找到 EyeTimer 窗口（应用是否在运行？）")
            exit(1)
        }
        print("挂件窗口: frame=\(widget.frame) level=\(widget.windowLayer)")
        print("图标层 = \(iconLevel)")

        let display = content.displays.first!
        let pxScale = Double(display.width) / Double(screenFrame.width)
        print("显示倍率 = \(pxScale)")

        let startCG = CGPoint(x: widget.frame.midX, y: widget.frame.midY)
        // 往左上拖（挂件默认在右下角），且终点留在屏幕内
        let wantDX: CGFloat = -420
        let wantDY: CGFloat = -240
        var endCG = CGPoint(x: startCG.x + wantDX, y: startCG.y + wantDY)
        if endCG.x < 150 || endCG.y < 200 {
            endCG = CGPoint(x: startCG.x + abs(wantDX), y: startCG.y + abs(wantDY))
        }
        let midCG = CGPoint(x: (startCG.x + endCG.x) / 2, y: (startCG.y + endCG.y) / 2)
        print("拖拽: \(startCG) → \(endCG)  (CG 坐标)")

        let baseline = "/tmp/et_baseline_\(label).png"
        let during = "/tmp/et_during_\(label).png"

        guard captureScreen(to: baseline) else { print("❌ 基线截图失败"); exit(1) }
        guard let baseImg = loadImage(baseline) else { print("❌ 基线图读取失败"); exit(1) }
        print("基线截图: \(baseImg.width)x\(baseImg.height)")

        // ---- 真实拖拽，中途抓一张（鼠标仍按着）----
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(startCG)
        pump(0.4)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: startCG, mouseButton: .left) {
            d.post(tap: .cghidEventTap)
        }
        pump(0.15)

        let stepsToMid = 12
        for i in 1...stepsToMid {
            let t = Double(i) / Double(stepsToMid)
            let x = startCG.x + (midCG.x - startCG.x) * t
            let y = startCG.y + (midCG.y - startCG.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.03)
        }
        pump(0.4)

        guard captureScreen(to: during) else { print("❌ 拖拽中截图失败"); exit(1) }
        print("拖拽中截图完成 → \(during)")

        // 继续拖到终点并松开
        let stepsToEnd = 12
        for i in 1...stepsToEnd {
            let t = Double(i) / Double(stepsToEnd)
            let x = midCG.x + (endCG.x - midCG.x) * t
            let y = midCG.y + (endCG.y - midCG.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.03)
        }
        pump(0.2)
        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: endCG, mouseButton: .left) {
            u.post(tap: .cghidEventTap)
        }
        pump(0.8)

        guard let duringImg = loadImage(during) else { print("❌ 拖拽中图片读取失败"); exit(1) }

        // ---- 分析 ----
        let region = CGRect(x: min(startCG.x, endCG.x) - 60,
                            y: min(startCG.y, endCG.y) - 60,
                            width: abs(endCG.x - startCG.x) + 120,
                            height: abs(endCG.y - startCG.y) + 120)
        let regionPx = CGRect(x: region.minX * pxScale,
                              y: region.minY * pxScale,
                              width: region.width * pxScale,
                              height: region.height * pxScale)

        let stats = diffStats(baseImg, duringImg, rectPx: regionPx)
        let totalPixels = Int(regionPx.width) * Int(regionPx.height)
        let fullStats = diffStats(baseImg, duringImg,
                                   rectPx: CGRect(x: 0, y: 0,
                                                  width: baseImg.width, height: baseImg.height))

        print("")
        print("=== 拖拽区域分析 ===")
        print("区域(像素): \(Int(regionPx.width))x\(Int(regionPx.height)) = \(totalPixels) px")
        print("区域变化像素数: \(stats.changed)")
        print("区域变化像素蓝色调 峰值/均值 (B-R): \(String(format: "%.1f", stats.bluePeak)) / \(String(format: "%.1f", stats.blueMean))")
        print("整图变化像素数: \(fullStats.changed)")
        print("整图变化像素蓝色调 峰值/均值 (B-R): \(String(format: "%.1f", fullStats.bluePeak)) / \(String(format: "%.1f", fullStats.blueMean))")
        print("")

        let changedRatio = Double(stats.changed) / Double(max(1, totalPixels))
        // Finder 的框选矩形：变化面积大 + 蓝色调高
        let significant = stats.changed > 3000 && stats.blueMean > 20

        if significant {
            print("❌ 检测到 Finder 的框选矩形（大面积蓝色填充）—— 矩形问题仍存在")
            print("   变化占比 \(String(format: "%.1f%%", changedRatio * 100))")
            exit(2)
        } else {
            print("✅ 未检测到框选矩形")
            print("   变化像素 \(stats.changed) / \(totalPixels) (\(String(format: "%.2f%%", changedRatio * 100)))")
            print("   蓝色调均值 \(String(format: "%.1f", stats.blueMean))")
            exit(0)
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
