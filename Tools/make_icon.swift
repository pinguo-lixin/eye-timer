#!/usr/bin/swift
// 生成 App 图标（.icns）—— 纯代码绘制，无外部素材依赖。
// 用法: swift Tools/make_icon.swift <输出目录>

import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default

// MARK: - 绘制

/// 直接用 CGContext 绘制图标位图，避免 NSBitmapImageRep 的内存布局坑。
func renderIcon(size: Int) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil,
                              width: size,
                              height: size,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }

    let s = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // macOS 图标圆角比例
    let radius = s * 0.2237
    let rounded = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(rounded)
    ctx.clip()

    // 背景渐变：蓝 → 绿（护眼主题）
    let bgColors = [
        NSColor(calibratedRed: 0.24, green: 0.55, blue: 0.96, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.24, green: 0.76, blue: 0.66, alpha: 1).cgColor
    ] as CFArray
    if let bg = CGGradient(colorsSpace: space, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bg,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: s, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    // 眼睛：上下两段贝塞尔弧
    let cx = s / 2
    let cy = s / 2 + s * 0.012
    let eyeW = s * 0.60
    let eyeH = s * 0.335

    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: cx - eyeW / 2, y: cy))
    eye.addCurve(to: CGPoint(x: cx + eyeW / 2, y: cy),
                 control1: CGPoint(x: cx - eyeW / 2 + eyeW * 0.28, y: cy + eyeH * 0.98),
                 control2: CGPoint(x: cx + eyeW / 2 - eyeW * 0.28, y: cy + eyeH * 0.98))
    eye.addCurve(to: CGPoint(x: cx - eyeW / 2, y: cy),
                 control1: CGPoint(x: cx + eyeW / 2 - eyeW * 0.28, y: cy - eyeH * 0.98),
                 control2: CGPoint(x: cx - eyeW / 2 + eyeW * 0.28, y: cy - eyeH * 0.98))
    eye.closeSubpath()

    ctx.saveGState()
    ctx.addPath(eye)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 虹膜
    let irisR = s * 0.145
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: cx - irisR, y: cy - irisR, width: irisR * 2, height: irisR * 2))
    ctx.clip()
    let irisColors = [
        NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.66, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.17, green: 0.50, blue: 0.53, alpha: 1).cgColor
    ] as CFArray
    if let iris = CGGradient(colorsSpace: space, colors: irisColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(iris,
                               startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy), endRadius: irisR,
                               options: [])
    }
    ctx.restoreGState()

    // 瞳孔
    let pupilR = irisR * 0.46
    ctx.setFillColor(NSColor(calibratedWhite: 0.11, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: cx - pupilR, y: cy - pupilR, width: pupilR * 2, height: pupilR * 2))

    // 高光
    let hlR = irisR * 0.27
    ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.95).cgColor)
    ctx.fillEllipse(in: CGRect(x: cx - irisR * 0.40 - hlR,
                               y: cy + irisR * 0.32 - hlR,
                               width: hlR * 2, height: hlR * 2))
    let hl2R = irisR * 0.13
    ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.55).cgColor)
    ctx.fillEllipse(in: CGRect(x: cx + irisR * 0.22 - hl2R,
                               y: cy - irisR * 0.34 - hl2R,
                               width: hl2R * 2, height: hl2R * 2))

    // 顶部玻璃高光弧
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor)
    ctx.setLineWidth(s * 0.020)
    ctx.setLineCap(.round)
    let gloss = CGMutablePath()
    gloss.move(to: CGPoint(x: s * 0.16, y: s * 0.855))
    gloss.addCurve(to: CGPoint(x: s * 0.84, y: s * 0.855),
                   control1: CGPoint(x: s * 0.36, y: s * 0.985),
                   control2: CGPoint(x: s * 0.64, y: s * 0.985))
    ctx.addPath(gloss)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

// MARK: - PNG 输出

func writePNG(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// MARK: - 生成各尺寸

let iconsetDir = "\(outDir)/AppIcon.iconset"
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

var allOK = true
for (name, size) in variants {
    guard let img = renderIcon(size: size),
          writePNG(img, to: "\(iconsetDir)/\(name)") else {
        print("生成失败: \(name)")
        allOK = false
        continue
    }
    let sz = (try? fm.attributesOfItem(atPath: "\(iconsetDir)/\(name)")[.size] as? Int) ?? 0
    print("  \(name): \(sz ?? 0) bytes")
}

// 转换为 icns
let icnsPath = "\(outDir)/AppIcon.icns"
if allOK {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
    try? process.run()
    process.waitUntilExit()
}

if fm.fileExists(atPath: icnsPath), ((try? fm.attributesOfItem(atPath: icnsPath)[.size] as? Int) ?? 0) ?? 0 > 0 {
    print("图标已生成: \(icnsPath)")
} else {
    // 降级：输出 1024 png
    if let img = renderIcon(size: 1024) {
        let png = "\(outDir)/AppIcon.png"
        if writePNG(img, to: png) {
            print("iconset 转换失败，已输出 \(png)")
        } else {
            print("图标生成完全失败")
        }
    }
}
