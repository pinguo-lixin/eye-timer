import AppKit
import CoreGraphics
import ImageIO

/// A/B 直接比对：修复开启 vs 修复关闭的「拖拽中」截图。
///
/// ## 为什么不用「基线 vs 拖拽中」
///
/// 拖拽会让**挂件自己移动**，新旧位置产生巨大亮度差，
/// 很容易把「挂件移动」误判成「框选矩形」。
///
/// 直接拿 A（关闭修复）和 B（开启修复）两张**同样拖拽**的截图相减：
///   - 挂件两次都移动到几乎相同的位置 → 相减后抵消
///   - 只有**框选矩形**是 A 独有 → 差值里剩下的就是它
///
/// 用法：swift Tools/marquee_diff_ab.swift <A.png> <B.png>

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

func pixels(_ img: CGImage) -> [UInt8]? {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

let args = CommandLine.arguments
guard args.count >= 3,
      let imgA = loadImage(args[1]), let imgB = loadImage(args[2]),
      let a = pixels(imgA), let b = pixels(imgB) else {
    print("用法: marquee_diff_ab <A_修复关闭.png> <B_修复开启.png>")
    exit(1)
}
guard imgA.width == imgB.width, imgA.height == imgB.height else {
    print("❌ 尺寸不一致: \(imgA.width)x\(imgA.height) vs \(imgB.width)x\(imgB.height)")
    exit(1)
}

let w = imgA.width, h = imgA.height
var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
var count = 0
var sumA = 0.0
var sumBR = 0.0

for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let aR = Double(a[i]), aG = Double(a[i+1]), aB = Double(a[i+2])
        let bR = Double(b[i]), bG = Double(b[i+1]), bB = Double(b[i+2])
        let lumA = (aR + aG + aB) / 3
        let lumB = (bR + bG + bB) / 3
        // A 比 B 明显更亮 → A 独有的亮区（框选矩形）
        let d = lumA - lumB
        guard d > 20 else { continue }
        count += 1
        sumA += d
        sumBR += (aB - aR)
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}

print("图片尺寸: \(w)x\(h)")
print("A 独有亮像素: \(count)  (占比 \(String(format: "%.2f", Double(count) / Double(w*h) * 100))%)")
if count == 0 {
    print("✅ A 与 B 没有显著差异 → 修复没有引入变化（不应出现框选矩形）")
    exit(0)
}
print("包围盒: x[\(minX)...\(maxX)] y[\(minY)...\(maxY)]  (宽 \(maxX-minX+1) 高 \(maxY-minY+1))")
print("平均亮度差: \(String(format: "%.1f", sumA / Double(count)))  平均 B-R: \(String(format: "%.1f", sumBR / Double(count)))")
print("⚠️  A 独有亮区 = 修复关闭时存在的框选矩形 → 修复确实把它消除了")
