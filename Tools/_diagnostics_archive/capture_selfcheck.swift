import AppKit
import CoreGraphics
import ImageIO

/// 自检：验证「screencapture 抓取动态画面」这条链路本身可靠。
///
/// 做法：抓一张基线 → 移动鼠标 → 再抓一张 → 比较两图的差异。
/// 屏幕上有一个明显的彩色方块（我们绘制），移动鼠标后光标位置会变，
/// 差异像素数应该显著大于 0。
///
/// 用法：swift Tools/capture_selfcheck.swift

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
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    } catch { return false }
}

func load(_ path: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

func changedCount(_ a: CGImage, _ b: CGImage) -> Int {
    let w = min(a.width, b.width), h = min(a.height, b.height)
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
    guard let ba = bytes(a), let bb = bytes(b) else { return -1 }
    var n = 0
    for i in stride(from: 0, to: ba.count, by: 4) {
        let d = abs(Int(ba[i]) - Int(bb[i]))
            + abs(Int(ba[i+1]) - Int(bb[i+1]))
            + abs(Int(ba[i+2]) - Int(bb[i+2]))
        if d > 24 { n += 1 }
    }
    return n
}

// 在屏幕中央画一个醒目色块，位置固定
final class Marker: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        dirtyRect.fill()
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    let m = Marker(frame: NSRect(x: 1700, y: 700, width: 300, height: 200))
    let w = NSWindow(contentRect: m.frame, styleMask: [.borderless],
                     backing: .buffered, defer: false)
    w.level = .floating
    w.contentView = m
    w.orderFrontRegardless()
    pump(1.0)

    let a = "/tmp/sc_a.png", b = "/tmp/sc_b.png"
    print("抓基线…")
    _ = capture(to: a)
    pump(0.6)

    // 把鼠标移到色块正中央（光标会遮住色块 → 差异显著）
    let p = CGPoint(x: 1850, y: screenFrame.maxY - 800)
    CGAssociateMouseAndMouseCursorPosition(1)
    CGWarpMouseCursorPosition(p)
    pump(0.8)
    print("抓第二张…")
    _ = capture(to: b)
    pump(0.4)

    if let ia = load(a), let ib = load(b) {
        let n = changedCount(ia, ib)
        print("两图差异像素数 = \(n)  (整图 \(ia.width)x\(ia.height))")
        if n > 100 {
            print("✅ 截图链路能捕捉到动态变化")
        } else {
            print("❌ 截图链路无法捕捉动态变化 —— 之前的验证方法不可靠")
        }
    } else {
        print("❌ 图片读取失败")
    }
    exit(0)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
