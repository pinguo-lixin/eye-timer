import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// 裁剪 PNG 的指定区域（屏幕坐标 → 图像像素坐标）。
///
/// 用法：swift Tools/crop.swift <输入png> <输出png> <x> <y> <w> <h> [scale]
///   x/y/w/h 为**屏幕逻辑坐标**（左下原点，与 AppKit 一致）
///   scale 为图像像素 / 屏幕逻辑坐标 的倍率（Retina 通常为 2）
///
/// 注意：屏幕坐标 y 轴向上，而图像像素 y 轴向下，需要翻转。
let args = CommandLine.arguments
guard args.count >= 7 else {
    print("用法: swift crop.swift <in> <out> <x> <y> <w> <h> [scale]")
    exit(1)
}

let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let x = Double(args[3])!
let y = Double(args[4])!
let w = Double(args[5])!
let h = Double(args[6])!
let scale = args.count > 7 ? Double(args[7])! : 2.0

guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("❌ 读取失败")
    exit(1)
}

print("整图尺寸: \(img.width)x\(img.height)")

// 屏幕坐标 → 像素坐标
let px = x * scale
let py = (y + h) * scale          // 翻转：屏幕左下原点 → 像素左上原点
let pw = w * scale
let ph = h * scale

let rect = CGRect(x: px, y: py - ph, width: pw, height: ph)
print("像素裁剪: \(rect)")

guard let cropped = img.cropping(to: rect) else {
    print("❌ 裁剪失败")
    exit(1)
}

guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else {
    print("❌ 输出失败")
    exit(1)
}
CGImageDestinationAddImage(dest, cropped, nil)
CGImageDestinationFinalize(dest)
print("✅ 已保存: \(outURL)  \(cropped.width)x\(cropped.height)")
