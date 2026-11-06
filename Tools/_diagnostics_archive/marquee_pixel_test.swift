import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit

/// 像素法交叉验证：在**裸桌面区域**上拖拽，检查是否出现半透明蓝色框选矩形。
///
/// ## 为什么之前的像素比对不可靠
///
/// 1. 拖拽路径可能落在别的 App 窗口上（那些窗口本来就会变化）；
/// 2. 光标本身在移动，会造成小范围差异；
/// 3. 挂件自己在移动，也会造成差异。
///
/// 这一版：
///   - 只看**裸桌面区域**（无任何 App 窗口覆盖）；
///   - 拖拽路径完全在裸桌面内；
///   - 判定用「蓝色调 B-R」：Finder 的框选矩形是蓝色半透明填充，
///     会大面积抬高 B-R；而挂件的蓝色进度环面积很小。
///
/// ## A/B 对照
///
/// 通过环境变量 `EYETIMER_DISABLE_CAPTURE=1` 可以关掉补发 mouseUp 的机制，
/// 用来做对照：关闭后应当能复现矩形。
///
/// 用法：swift Tools/marquee_pixel_test.swift

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

/// 区域内变化像素数 + 蓝色调统计
func analyze(_ a: CGImage, _ b: CGImage, rectPx: CGRect) -> (changed: Int, blueMean: Double, bluePeak: Double) {
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
    var blueSum = 0.0
    var bluePeak = 0.0
    var n = 0.0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        if d > 24 {
            changed += 1
            let bl = Double(bb[i + 2]) - Double(bb[i])
            blueSum += bl
            bluePeak = max(bluePeak, bl)
            n += 1
        }
    }
    return (changed, n > 0 ? blueSum / n : 0, bluePeak)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        // 遮挡源：普通 App 窗口 + 系统 UI（排除 Finder 桌面与 EyeTimer）
        let blockers = content.windows.filter { w in
            guard w.isOnScreen else { return false }
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") { return false }
            if w.windowLayer >= 0 { return true }
            if w.windowLayer > iconLevel {
                if bid == "com.apple.finder" { return false }
                return true
            }
            return false
        }

        // 找裸桌面点
        var target: CGPoint?
        let step: CGFloat = 20
        outer: for fy in stride(from: 250.0, through: 1250.0, by: step) {
            for fx in stride(from: 150.0, through: 3300.0, by: step) {
                let p = CGPoint(x: fx, y: fy)
                if blockers.contains(where: { $0.frame.contains(p) }) { continue }
                var clear = true
                for dx in [-160.0, 0, 160.0] {
                    for dy in [-160.0, 0, 160.0] {
                        let q = CGPoint(x: p.x + dx, y: p.y + dy)
                        if blockers.contains(where: { $0.frame.contains(q) }) { clear = false }
                    }
                }
                if clear { target = p; break outer }
            }
        }

        guard let target else {
            print("❌ 找不到裸桌面点"); exit(1)
        }
        print("裸桌面点 (CG) = \(target)")

        // 拖拽路径完全在裸桌面内
        let end = CGPoint(x: target.x + 260, y: target.y + 180)

        let basePath = "/tmp/mq_base.png"
        let duringPath = "/tmp/mq_during.png"

        guard capture(to: basePath) else { print("❌ 基线截图失败"); exit(1) }
        pump(0.6)

        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(target)
        pump(0.5)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: target, mouseButton: .left) {
            d.post(tap: .cghidEventTap)
        }
        pump(0.15)

        for i in 1...14 {
            let t = Double(i) / 14.0
            let x = target.x + (end.x - target.x) * t
            let y = target.y + (end.y - target.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.035)
        }
        pump(0.45)

        guard capture(to: duringPath) else { print("❌ 拖拽中截图失败"); exit(1) }
        print("拖拽中截图完成")

        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: end, mouseButton: .left) {
            u.post(tap: .cghidEventTap)
        }
        pump(0.8)

        guard let baseImg = loadImage(basePath), let duringImg = loadImage(duringPath) else {
            print("❌ 图片读取失败"); exit(1)
        }

        // 关注区域：拖拽路径包围盒（CG 坐标）
        let region = CGRect(x: min(target.x, end.x) - 70,
                            y: min(target.y, end.y) - 70,
                            width: abs(end.x - target.x) + 140,
                            height: abs(end.y - target.y) + 140)
        let pxScale = Double(baseImg.width) / Double(screenFrame.width)
        let regionPx = CGRect(x: region.minX * pxScale, y: region.minY * pxScale,
                              width: region.width * pxScale, height: region.height * pxScale)

        let stats = analyze(baseImg, duringImg, rectPx: regionPx)
        let total = Int(regionPx.width) * Int(regionPx.height)

        print("")
        print("=== 裸桌面拖拽区域分析 ===")
        print("区域(像素): \(Int(regionPx.width))x\(Int(regionPx.height)) = \(total) px")
        print("变化像素数: \(stats.changed) (\(String(format: "%.2f%%", Double(stats.changed) / Double(total) * 100)))")
        print("变化像素蓝色调 均值/峰值 (B-R): \(String(format: "%.1f", stats.blueMean)) / \(String(format: "%.1f", stats.bluePeak))")
        print("")

        // 判定：框选矩形 = 大面积变化 + 高蓝色调
        if stats.changed > 4000 && stats.blueMean > 25 {
            print("❌ 检测到大面积蓝色填充 → 框选矩形存在")
            exit(2)
        } else {
            print("✅ 未检测到大面积蓝色填充 → 无框选矩形")
            exit(0)
        }
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
