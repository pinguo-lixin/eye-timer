import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 视觉验证：在**裸桌面**上真实拖拽，拖到中途停住，
/// 用 `screencapture -R` 只截拖拽区域，检测有没有蓝色框选矩形。
///
/// ## 设计要点（都是踩过坑之后定下来的）
///
/// 1. **完全自足** —— 不依赖任何预先算好的 plan 文件。
///    起点 = 挂件窗口的**实际**位置；终点 = 从实际位置出发，
///    动态挑选一条全程无遮挡的方向。之前依赖过期 plan，
///    导致截屏区域偏离 430px，截到菜单栏上，误报「检出矩形」。
/// 2. **只算普通 App 窗口**（level 0~17）作为遮挡者。
///    Dock、通知中心容器、菜单栏条这些看不见的容器窗口铺满全屏，
///    但**不遮挡像素**，算进来会让所有区域都"不干净"。
/// 3. **截图前再确认一次**区域干净 —— 测试途中可能有别的窗口弹出。
/// 4. **拖拽中途截图** —— 框选矩形在拖拽过程中最明显。
///
/// 用法：swift Tools/visual_marquee_test.swift <标签>
///       例：swift Tools/visual_marquee_test.swift A

let tag = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "vis"
let src = CGEventSource(stateID: .hidSystemState)

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 找到 EyeTimer 进程的 PID。
///
/// 不能靠窗口 owner 的显示名排除 —— 它的显示名是中文「护眼提醒」，
/// 而 bundle 名 / 进程名才是 EyeTimer。
func eyeTimerPID() -> Int? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list {
        let name = (w[kCGWindowOwnerName as String] as? String) ?? ""
        if name.contains("EyeTimer") || name.contains("护眼提醒") {
            return (w[kCGWindowOwnerPID as String] as? Int) ?? -1
        }
    }
    return nil
}

/// 只把「普通 App 窗口」算作遮挡者。
///
/// - layer 0~17：普通 App 窗口，真的会挡像素
/// - layer ≥ 18：系统浮层（Control Center / 菜单栏条 / Dock 容器），
///   多数是透明容器，不挡像素 —— 但通知中心的小面板会挡，
///   所以单独处理：面积小于屏幕 30% 的才算遮挡。
///
/// ⚠️ 必须排除**测试脚本自己**（swift-frontend）：它以 layer 0 跑在挂件旁边，
/// 不排除的话会把挂件位置判成「被覆盖」。用 owner PID 精确排除，不按名字猜。
///
/// 改用 `CGWindowList`（带 owner PID），而不是 ScreenCaptureKit ——
/// 后者的 `SCRunningApplication` 没有暴露 PID。
func blockers() -> [(layer: Int, owner: String, pid: Int, frame: CGRect)] {
    let screenArea = 3440.0 * 1440.0
    let myPID = ProcessInfo.processInfo.processIdentifier
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

    var out: [(Int, String, Int, CGRect)] = []
    for w in list {
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        let pid = (w[kCGWindowOwnerPID as String] as? Int) ?? -1
        let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
        guard let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
        let rect = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                          width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
        // 排除自己（测试脚本）和 EyeTimer
        // ⚠️ 不能靠 owner 名字匹配 —— 它的显示名是中文「护眼提醒」，
        // 只能靠 PID 排除。
        if pid == myPID || owner.contains("swift") { continue }
        if let eyePID = eyeTimerPID(), pid == eyePID { continue }
        // 零尺寸的窗口不挡像素
        if rect.width < 1 || rect.height < 1 { continue }

        if layer >= 0 && layer < 18 {
            // 普通 App 窗口 —— 真的挡像素
            out.append((layer, owner, pid, rect))
        } else if layer > Int(CGWindowLevelForKey(.desktopIconWindow)) {
            // 高于桌面图标层的系统浮层。
            // 其中**通知横幅**（Notification Center，layer=-2147483601）会挡像素，
            // 但它的容器窗口铺满全屏 —— 用面积区分：小的才算遮挡。
            if rect.width * rect.height < screenArea * 0.3 {
                out.append((layer, owner, pid, rect))
            }
        }
    }
    return out
}

/// 该点周围半径 r 的圆盘是否干净
func isClear(_ p: CGPoint, r: Double, in bl: [(layer: Int, owner: String, pid: Int, frame: CGRect)]) -> Bool {
    for dx in stride(from: -r, through: r, by: max(r / 4, 1)) {
        for dy in stride(from: -r, through: r, by: max(r / 4, 1)) {
            if bl.contains(where: { $0.frame.contains(CGPoint(x: p.x + dx, y: p.y + dy)) }) {
                return false
            }
        }
    }
    return true
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    Task {
        let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // ---- 找挂件窗口 ----
        var widget: SCWindow?
        for w in content.windows {
            let bid = w.owningApplication?.bundleIdentifier ?? ""
            if bid.contains("eyetimer") && w.isOnScreen {
                if widget == nil || w.frame.width * w.frame.height > widget!.frame.width * widget!.frame.height {
                    widget = w
                }
            }
        }
        guard let widget else { print("❌ 未找到挂件窗口"); exit(1) }
        print("挂件: frame=\(widget.frame) level=\(widget.windowLayer)")

        let bl = blockers()
        let start = CGPoint(x: widget.frame.midX, y: widget.frame.midY)
        print("挂件中心: \(start)")

        // ---- 起点必须干净 ----
        guard isClear(start, r: 90, in: bl) else {
            // 打印真正命中的窗口（可能是采样点上的，不是 start 本身）
            for w in bl where w.frame.intersects(CGRect(x: start.x - 90, y: start.y - 90, width: 180, height: 180)) {
                print("   命中窗口: layer=\(w.layer) owner=[\(w.owner)] pid=\(w.pid) rect=\(w.frame)")
            }
            print("❌ 挂件周围有其它窗口，无法在裸桌面测试")
            exit(3)
        }
        print("✅ 挂件位于裸桌面")

        // ---- 从实际起点动态挑一条干净方向 ----
        let reach = 170.0
        let dirs: [(CGPoint, String)] = [
            (CGPoint(x: 1, y: 1), "右下"), (CGPoint(x: -1, y: 1), "左下"),
            (CGPoint(x: 1, y: -1), "右上"), (CGPoint(x: -1, y: -1), "左上"),
            (CGPoint(x: 1, y: 0), "右"),   (CGPoint(x: -1, y: 0), "左"),
            (CGPoint(x: 0, y: 1), "下"),   (CGPoint(x: 0, y: -1), "上"),
        ]
        var end: CGPoint? = nil
        var dirName = ""
        outer: for (d, name) in dirs {
            let candidate = CGPoint(x: start.x + d.x * reach, y: start.y + d.y * reach)
            // 终点周围要留 90 半径余量（框选矩形会覆盖这段）
            guard candidate.y > 150, candidate.y < 1400 else { continue }
            guard candidate.x > 130, candidate.x < 3350 else { continue }
            // 路径采样
            var ok = true
            for i in 0...20 {
                let t = Double(i) / 20.0
                let q = CGPoint(x: start.x + (candidate.x - start.x) * t,
                                y: start.y + (candidate.y - start.y) * t)
                if !isClear(q, r: 90, in: bl) { ok = false; break }
            }
            if ok { end = candidate; dirName = name; break outer }
        }
        guard let end else {
            print("❌ 找不到全程干净的拖拽方向（周围窗口太多）")
            exit(3)
        }
        print("✅ 拖拽方向: \(dirName)  终点=\(end)")

        // ---- 截图区域：包住起点、终点 ----
        let rectCG = CGRect(x: min(start.x, end.x) - 120,
                            y: min(start.y, end.y) - 120,
                            width: abs(end.x - start.x) + 240,
                            height: abs(end.y - start.y) + 240)
        print("截图区域(Quartz): \(rectCG)")

        func snap(_ path: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-R",
                           "\(Int(rectCG.minX)),\(Int(rectCG.minY)),\(Int(rectCG.width)),\(Int(rectCG.height))",
                           "-t", "png", path]
            try? p.run(); p.waitUntilExit()
        }

        /// 截图前再确认一次区域仍然干净
        func regionStillClear() async -> Bool {
            let bl2 = blockers()
            let probes = [
                CGPoint(x: rectCG.minX + 5, y: rectCG.minY + 5),
                CGPoint(x: rectCG.maxX - 5, y: rectCG.minY + 5),
                CGPoint(x: rectCG.minX + 5, y: rectCG.maxY - 5),
                CGPoint(x: rectCG.maxX - 5, y: rectCG.maxY - 5),
                CGPoint(x: rectCG.midX, y: rectCG.midY),
            ]
            for w in bl2 {
                for p in probes where w.frame.contains(p) {
                    print("❌ 截图时区域被 \(w.owner) 覆盖，测试作废")
                    return false
                }
            }
            return true
        }

        // 基线（拖拽前）
        snap("/tmp/vis_base_\(tag).png")

        // ---- 真实拖拽，中途截图 ----
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(start)
        pump(0.7)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                          mouseCursorPosition: start, mouseButton: .left) {
            d.post(tap: .cghidEventTap)
        }
        pump(0.3)
        for i in 1...18 {
            let t = Double(i) / 18.0
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            if let e = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                e.post(tap: .cghidEventTap)
            }
            pump(0.045)
        }

        // 停在终点（按住不放）—— 框选矩形此刻应完整可见
        pump(0.35)
        guard await regionStillClear() else { exit(4) }
        snap("/tmp/vis_during_\(tag).png")
        print("拖拽中截图 → /tmp/vis_during_\(tag).png")

        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: end, mouseButton: .left) {
            u.post(tap: .cghidEventTap)
        }
        pump(0.9)
        exit(0)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
