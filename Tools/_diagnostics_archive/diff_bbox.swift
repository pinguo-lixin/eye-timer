import Foundation
import CoreGraphics
import ImageIO

/// 比较两张 PNG，找出「发生变化的像素」的包围盒。
///
/// 用途：判断桌面框选矩形到底画在了哪里、多大。
/// 只关心变化区域的位置和尺寸，不看颜色细节。
///
/// 用法：swift Tools/diff_bbox.swift <a.png> <b.png> [阈值]

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift diff_bbox.swift <a.png> <b.png> [阈值]")
    exit(1)
}

let threshold = args.count > 3 ? Int(args[3])! : 24

func load(_ path: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

guard let a = load(args[1]), let b = load(args[2]) else {
    print("❌ 读取失败"); exit(1)
}

let w = min(a.width, b.width)
let h = min(a.height, b.height)
print("图1: \(a.width)x\(a.height)   图2: \(b.width)x\(b.height)   对比区域: \(w)x\(h)")

func bytes(_ img: CGImage) -> [UInt8]? {
    guard let c = img.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) else { return nil }
    var out = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ok: Bool = out.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(c, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
        }
    return ok ? out : nil
}

guard let ba = bytes(a), let bb = bytes(b) else {
    print("❌ 像素读取失败"); exit(1)
}

var minX = w, minY = h, maxX = -1, maxY = -1
var count = 0
var blueCount = 0
var blueSum = 0.0

for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        if d > threshold {
            count += 1
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
            let bl = Double(bb[i+2]) - Double(bb[i])
            if bl > 25 { blueCount += 1; blueSum += bl }
        }
    }
}

print("")
print("变化像素数: \(count)  (阈值 \(threshold))")
if count == 0 {
    print("两图完全一致（无变化）")
    exit(0)
}

let bw = maxX - minX + 1
let bh = maxY - minY + 1
print("变化区域包围盒 (像素坐标, 左上原点): x=\(minX) y=\(minY) w=\(bw) h=\(bh)")
print("变化区域占屏比例: \(String(format: "%.1f%%", Double(bw * bh) / Double(w * h) * 100))")
print("蓝色像素数 (B-R>25): \(blueCount)  蓝色调均值: \(String(format: "%.1f", blueCount > 0 ? blueSum / Double(blueCount) : 0))")
print("")

if bw > 300 && bh > 200 && blueCount > 2000 {
    print("⚠️  存在大面积蓝色区域 —— 疑似 Finder 的框选矩形")
} else {
    print("✅ 未见大面积蓝色框选矩形")
}
