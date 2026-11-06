import Foundation
import CoreGraphics
import ImageIO

/// 对比两张图在指定区域上的亮度差，用来客观判断「悬停变实心」是否生效。
///
/// 用法：swift analyze_opacity.swift <before.png> <after.png> <x> <y> <w> <h> [scale]
///
/// 实现说明：把裁剪区域画进一个 RGBA8 bitmap context 再读字节，
/// 这样不用关心源图的字节序 / 是否有 alpha 通道。
let args = CommandLine.arguments
guard args.count >= 7 else {
    print("用法: swift analyze_opacity.swift <before> <after> <x> <y> <w> <h> [scale]")
    exit(1)
}

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// 读取区域像素，返回 (平均亮度, 对比度/标准差)
///
/// 区域用**左上角原点**的像素坐标（与 `SCWindow.frame`、
/// `screencapture` 输出的 PNG 一致）。
/// 先用 `CGImage.cropping` 精确取到区域，再画进 bitmap context 读字节；
/// 统计量（均值 / 标准差）不受垂直翻转影响，所以不必再关心 context 的朝向。
func stats(_ img: CGImage, rect: CGRect, scale: Double) -> (mean: Double, sd: Double)? {
    let px = Int(rect.minX * scale)
    let py = Int(rect.minY * scale)
    let pw = Int(rect.width * scale)
    let ph = Int(rect.height * scale)
    guard pw > 0, ph > 0 else { return nil }

    let pixelRect = CGRect(x: px, y: py, width: pw, height: ph)
    guard let cropped = img.cropping(to: pixelRect) else { return nil }

    var pixels = [UInt8](repeating: 0, count: pw * ph * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let drew: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress,
                                  width: pw, height: ph,
                                  bitsPerComponent: 8, bytesPerRow: pw * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo) else { return false }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        return true
    }
    guard drew else { return nil }

    var sum = 0.0
    var sumSq = 0.0
    var n = 0.0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let r = Double(pixels[i])
        let g = Double(pixels[i + 1])
        let b = Double(pixels[i + 2])
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        sum = sum + lum
        sumSq = sumSq + (lum * lum)
        n = n + 1.0
    }
    let mean = sum / n
    let sd = sqrt(max(0, sumSq / n - mean * mean))
    return (mean, sd)
}

guard let before = load(args[1]), let after = load(args[2]) else {
    print("❌ 读取失败"); exit(1)
}
let x = Double(args[3])!, y = Double(args[4])!, w = Double(args[5])!, h = Double(args[6])!
let scale = args.count > 7 ? Double(args[7])! : 1.0
let rect = CGRect(x: x, y: y, width: w, height: h)

guard let b = stats(before, rect: rect, scale: scale),
      let a = stats(after, rect: rect, scale: scale) else {
    print("❌ 区域无效"); exit(1)
}

print("区域 \(rect)  scale=\(scale)")
print(String(format: "悬停前: 平均亮度=%.2f  对比度(标准差)=%.2f", b.mean, b.sd))
print(String(format: "悬停后: 平均亮度=%.2f  对比度(标准差)=%.2f", a.mean, a.sd))
print(String(format: "对比度变化: %+.2f  (%+.1f%%)", a.sd - b.sd, b.sd > 0 ? (a.sd - b.sd) / b.sd * 100 : 0))

if a.sd > b.sd * 1.25 {
    print("✅ 悬停后明显更实心（对比度提升超过 25%）")
} else if a.sd > b.sd * 1.05 {
    print("⚠️ 悬停后略有变化")
} else {
    print("❌ 悬停前后几乎无变化 —— 悬停效果可能未生效")
}
