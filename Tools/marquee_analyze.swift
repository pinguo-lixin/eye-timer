import AppKit
import CoreGraphics

/// 框选矩形像素分析。
///
/// 判定「拖拽时桌面画了矩形」的客观指标。
///
/// ## 判据
///
/// macOS 的桌面框选矩形是**半透明浅色填充 + 一圈亮边框**，
/// 叠在深色壁纸上会明显提亮，并带一点冷蓝色调。
///
/// 用两个量刻画：
///   - **提亮度**：相对「拖拽前基线图」，区域内像素变亮的幅度
///   - **蓝移**：B 通道相对 R 通道的增量（B − R）
///
/// 桌面图标标签的高饱和蓝要被排除 → 所以同时统计**饱和度**，
/// 只把「低饱和 + 明显提亮」的像素算作框选填充。
///
/// 用法：swift Tools/marquee_analyze.swift <基线.png> <拖拽中.png> [标签]

import ImageIO

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
guard args.count >= 3 else {
    print("用法: swift Tools/marquee_analyze.swift <基线.png> <拖拽中.png> [标签]")
    exit(1)
}
let label = args.count >= 4 ? args[3] : "run"

guard let baseImg = loadImage(args[1]), let durImg = loadImage(args[2]),
      let base = pixels(baseImg), let dur = pixels(durImg) else {
    print("❌ 图片读取失败")
    exit(1)
}
guard baseImg.width == durImg.width, baseImg.height == durImg.height else {
    print("❌ 尺寸不一致: \(baseImg.width)x\(baseImg.height) vs \(durImg.width)x\(durImg.height)")
    exit(1)
}

let w = baseImg.width, h = baseImg.height

/// 找出「相对基线变亮很多」且「低饱和」的像素 → 框选填充候选
struct Hit { var x: Int; var y: Int; var delta: Double; var bMinusR: Double; var sat: Double }

var hits: [Hit] = []
var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
var sumDelta = 0.0

for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let bR = Double(base[i]), bG = Double(base[i+1]), bB = Double(base[i+2])
        let dR = Double(dur[i]),  dG = Double(dur[i+1]),  dB = Double(dur[i+2])

        let baseLum = (bR + bG + bB) / 3
        let durLum  = (dR + dG + dB) / 3
        let delta = durLum - baseLum

        // 明显提亮（框选填充的典型特征）
        guard delta > 12 else { continue }

        // 饱和度：排除桌面图标标签那种高饱和蓝
        let mx = max(dR, max(dG, dB)), mn = min(dR, min(dG, dB))
        let sat = mx > 0 ? (mx - mn) / mx : 0
        guard sat < 0.22 else { continue }

        let bMinusR = dB - dR
        hits.append(Hit(x: x, y: y, delta: delta, bMinusR: bMinusR, sat: sat))
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
        sumDelta += delta
    }
}

print("── \(label) ──")
print("图片尺寸: \(w)x\(h)")
print("候选像素数: \(hits.count)  (占比 \(String(format: "%.2f", Double(hits.count) / Double(w*h) * 100))%)")

if hits.isEmpty {
    print("✅ 没有检出框选矩形特征像素 → 桌面未画矩形")
    exit(0)
}

let avgDelta = sumDelta / Double(hits.count)
let avgBR = hits.reduce(0.0) { $0 + $1.bMinusR } / Double(hits.count)
let avgSat = hits.reduce(0.0) { $0 + $1.sat } / Double(hits.count)
print("包围盒: x[\(minX)...\(maxX)] y[\(minY)...\(maxY)]  (宽 \(maxX-minX+1) 高 \(maxY-minY+1))")
print("平均提亮: \(String(format: "%.1f", avgDelta))  平均 B-R: \(String(format: "%.1f", avgBR))  平均饱和度: \(String(format: "%.3f", avgSat))")
print("⚠️  检出框选矩形特征 → 桌面画了矩形")
