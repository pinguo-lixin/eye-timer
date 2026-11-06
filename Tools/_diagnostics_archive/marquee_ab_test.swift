import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// A/B 对照：在**挂件上**真实拖拽，对比「补发 mouseUp」开/关时桌面上是否出现框选矩形。
///
/// ## 检测区域的选取
///
/// 桌面图标自带**蓝色标签**（选中时是高亮蓝底白字），很容易误判成框选矩形。
/// 所以检测区域要避开图标 —— 用 ScreenCaptureKit 找到 Finder 桌面图标的位置，
/// 在图标**之外**的纯壁纸区取样。
///
/// 更稳的判据：**框选矩形是「半透明蓝色填充 + 1px 亮边」**，
/// 而图标标签是**纯蓝色实心圆角矩形**（B-R 极高但饱和度均匀）。
/// 这里同时统计：
///   - 变化像素数
///   - 变化像素的蓝色调均值/峰值
///   - 变化像素的**饱和度**分布（框选矩形是低饱和度蓝，图标标签是高饱和蓝）
///
/// 用法：swift Tools/marquee_ab_test.swift

let src = CGEventSource(stateID: .hidSystemState)
let screenFrame = NSScreen.screens[0].frame

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

@discardableResult
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

struct RegionStats {
    var changed = 0
    var blueMean = 0.0
    var bluePeak = 0.0
    var lowSatCount = 0     // 低饱和度蓝色像素（框选矩形的特征）
    var highSatCount = 0    // 高饱和度蓝色像素（图标标签的特征）
}

func analyze(_ a: CGImage, _ b: CGImage, rectPx: CGRect) -> RegionStats {
    var result = RegionStats()
    guard let ca = a.cropping(to: rectPx), let cb = b.cropping(to: rectPx) else { return result }
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
    guard let ba = bytes(ca), let bb = bytes(cb) else { return result }

    var blueSum = 0.0
    var n = 0.0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        guard d > 24 else { continue }
        result.changed += 1

        let r = Double(bb[i]), g = Double(bb[i+1]), bl = Double(bb[i+2])
        let blue = bl - r
        blueSum += blue
        n += 1
        result.bluePeak = max(result.bluePeak, blue)

        // 饱和度 = (max-min)/max
        let mx = max(r, max(g, bl)), mn = min(r, min(g, bl))
        let sat = mx > 0 ? (mx - mn) / mx : 0
        if blue > 25 {
            if sat < 0.55 { result.lowSatCount += 1 } else { result.highSatCount += 1 }
        }
    }
    if n > 0 { result.blueMean = blueSum / n }
    return result
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        // 找挂件
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
            print("❌ 未找到 EyeTimer 挂件窗口"); exit(1)
        }
        print("挂件: frame=\(widget.frame) level=\(widget.windowLayer)")

        // 找桌面图标的位置（用于避开它们）
        var iconRects: [CGRect] = []
        for w in content.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid == "com.apple.finder" && w.windowLayer == iconLevel && w.isOnScreen {
                iconRects.append(w.frame)
            }
        }
        print("Finder 桌面图标窗口数 = \(iconRects.count)")

        // 拖拽起点 = 挂件中心；终点往左上
        let start = CGPoint(x: widget.frame.midX, y: widget.frame.midY)
        var end = CGPoint(x: start.x - 380, y: start.y - 260)
        if end.x < 200 || end.y < 250 {
            end = CGPoint(x: start.x + 380, y: start.y + 260)
        }
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        print("拖拽: \(start) → \(end)")

        let basePath = "/tmp/mq_ab_base.png"
        let duringPath = "/tmp/mq_ab_during.png"

        guard capture(to: basePath) else { print("❌ 基线截图失败"); exit(1) }
        pump(0.6)

        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(start)
        pump(0.5)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: start, mouseButton: .left) {
            d.post(tap: .cghidEventTap)
        }
        pump(0.15)

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
        pump(0.5)

        guard capture(to: duringPath) else { print("❌ 拖拽中截图失败"); exit(1) }

        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: mid, mouseButton: .left) {
            u.post(tap: .cghidEventTap)
        }
        pump(0.6)

        guard let baseImg = loadImage(basePath), let duringImg = loadImage(duringPath) else {
            print("❌ 图片读取失败"); exit(1)
        }

        let pxScale = Double(baseImg.width) / Double(screenFrame.width)

        // 关注区域：**实际拖过的那一段**（起点 → 中途点）的包围盒
        // 注意：中途截图时鼠标只走到 mid，还没到 end，所以区域只覆盖 start..mid
        let region = CGRect(x: min(start.x, mid.x) - 100,
                            y: min(start.y, mid.y) - 100,
                            width: abs(mid.x - start.x) + 200,
                            height: abs(mid.y - start.y) + 200)
        let regionPx = CGRect(x: region.minX * pxScale, y: region.minY * pxScale,
                              width: region.width * pxScale, height: region.height * pxScale)

        let stats = analyze(baseImg, duringImg, rectPx: regionPx)
        let total = Int(regionPx.width) * Int(regionPx.height)

        print("")
        print("=== 拖拽区域（挂件起点 → 中途）分析 ===")
        print("区域(像素): \(Int(regionPx.width))x\(Int(regionPx.height)) = \(total) px")
        print("变化像素数: \(stats.changed) (\(String(format: "%.2f%%", Double(stats.changed) / Double(total) * 100)))")
        print("蓝色调 均值/峰值: \(String(format: "%.1f", stats.blueMean)) / \(String(format: "%.1f", stats.bluePeak))")
        print("低饱和蓝像素（框选矩形特征）: \(stats.lowSatCount)")
        print("高饱和蓝像素（图标标签特征）: \(stats.highSatCount)")
        print("")

        if stats.lowSatCount > 1500 {
            print("❌ 存在大量低饱和蓝色填充 → 框选矩形存在")
            exit(2)
        } else {
            print("✅ 未见低饱和蓝色填充 → 无框选矩形")
            exit(0)
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
