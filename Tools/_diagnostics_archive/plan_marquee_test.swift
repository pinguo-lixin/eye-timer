import Foundation
import ScreenCaptureKit

/// 第一阶段：规划一次「完全落在裸桌面上」的拖拽。
///
/// ## 为什么需要单独规划
///
/// 视觉验证要证明的是「桌面**没有**画出框选矩形」。
/// 截图必须拍到**真正的桌面壁纸**——如果那块区域被 Edge / WorkBuddy 等
/// 窗口盖住，截到的就是别人的界面，矩形根本没入镜，验证就是无效的。
///
/// 所以这里先算出：
///   - 一个**没有任何窗口覆盖**的挂件落点（连同 240×240 的余量）；
///   - 一条**全程都在裸桌面内**的拖拽路径。
///
/// 结果写入 `/tmp/et_marquee_plan.json`，第二阶段（`visual_marquee_test.swift`）读取。
///
/// 用法：swift Tools/plan_marquee_test.swift

struct Plan: Codable {
    /// 挂件左上角的 Quartz 坐标（左上原点）
    var widgetOriginCG: CGPoint
    /// 挂件中心（Quartz）
    var widgetCenterCG: CGPoint
    /// 拖拽终点（Quartz）
    var dragEndCG: CGPoint
    /// 挂件**左下角**的 AppKit 坐标（给 `--move` 用）
    var widgetOriginAppKit: NSPoint
}

let sem = DispatchSemaphore(value: 0)

Task {
    let content = try! await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

    // 只关心「普通 App 窗口」和「比图标层高的系统浮层」
    //
    // ⚠️ 关键：Dock（level 18/20）、通知中心的全屏容器、菜单栏条
    // 这些**看不见的容器窗口**虽然铺满全屏，但它们**不遮挡**任何像素。
    // 把它们当成遮挡者会导致「永远找不到裸桌面」。
    //
    // 真正的遮挡者 = 普通 App 窗口（level 0 ~ 17）。
    let blockers = content.windows.filter { w in
        guard w.isOnScreen else { return false }
        let bid = w.owningApplication?.bundleIdentifier ?? ""
        if bid.contains("eyetimer") { return false }
        let layer = w.windowLayer
        // 普通 App 窗口
        if layer >= 0 && layer < 18 { return true }
        // 通知中心的小面板（真正的浮层）
        if bid == "com.apple.notificationcenterui" {
            let screenArea = 3440.0 * 1440.0
            return w.frame.width * w.frame.height < screenArea * 0.3
        }
        return false
    }

    func isClear(_ p: CGPoint) -> Bool {
        !blockers.contains { $0.frame.contains(p) }
    }
    /// 半径 r 的整个圆盘都干净
    func isClearDisk(_ p: CGPoint, r: CGFloat) -> Bool {
        for dx in stride(from: -r, through: r, by: r / 4) {
            for dy in stride(from: -r, through: r, by: r / 4) {
                if !isClear(CGPoint(x: p.x + dx, y: p.y + dy)) { return false }
            }
        }
        return true
    }

    // 挂件落点：要求圆盘全干净。
    // 半径 150 太苛刻（环境里随便一个 App 窗口就废掉），
    // 改成 110 —— 够覆盖挂件本身 + 一圈余量即可。
    //
    // ⚠️ 从屏幕**中下部**开始找：顶部是通知中心（Notification Center）
    // 的地盘，它会不定时弹出浮层把测试区域盖掉。
    var anchor: CGPoint?
    outer: for fy in stride(from: 620.0, through: 1340.0, by: 10.0) {
        for fx in stride(from: 260.0, through: 3320.0, by: 10.0) {
            let p = CGPoint(x: fx, y: fy)
            if isClearDisk(p, r: 110) { anchor = p; break outer }
        }
    }
    if anchor == nil {
        // 中下部没有就退回全屏搜索
        outer2: for fy in stride(from: 260.0, through: 1340.0, by: 10.0) {
            for fx in stride(from: 260.0, through: 3320.0, by: 10.0) {
                let p = CGPoint(x: fx, y: fy)
                if isClearDisk(p, r: 110) { anchor = p; break outer2 }
            }
        }
    }
    guard let anchor else {
        print("❌ 找不到足够大的裸桌面区域")
        sem.signal(); return
    }

    // 拖拽方向：八个方向都试，要求**整条路径**（含终点 90 半径余量）都干净
    //
    // 优先用**斜向**：macOS 的桌面框选矩形高度 = 拖拽的垂直位移，
    // 纯水平拖拽时矩形高度为 0 → 视觉上根本看不见，验证就失效了。
    let reach = 170.0
    let dirs: [(CGPoint, String)] = [
        (CGPoint(x: 1, y: 1), "右下"),
        (CGPoint(x: -1, y: 1), "左下"),
        (CGPoint(x: -1, y: -1), "左上"),
        (CGPoint(x: 1, y: -1), "右上"),
        (CGPoint(x: 1, y: 0), "右"),
        (CGPoint(x: 0, y: 1), "下"),
        (CGPoint(x: -1, y: 0), "左"),
        (CGPoint(x: 0, y: -1), "上"),
    ]
    var chosen: (CGPoint, String)?
    for (d, name) in dirs {
        let end = CGPoint(x: anchor.x + d.x * reach, y: anchor.y + d.y * reach)
        var ok = true
        // 路径采样
        for i in 0...20 {
            let t = Double(i) / 20.0
            let q = CGPoint(x: anchor.x + (end.x - anchor.x) * t,
                            y: anchor.y + (end.y - anchor.y) * t)
            if !isClearDisk(q, r: 75) { ok = false; break }
        }
        if ok { chosen = (end, name); break }
    }
    guard let (end, dirName) = chosen else {
        print("❌ 找不到干净的拖拽路径")
        sem.signal(); return
    }

    // 挂件本体 106×108（左上角为 anchor）
    let widgetSize = CGSize(width: 106, height: 108)
    let origin = CGPoint(x: anchor.x - widgetSize.width / 2,
                         y: anchor.y - widgetSize.height / 2)

    let screenH = NSScreen.screens.first?.frame.height ?? 1440
    // `--move` 传的是**左下角**（AppKit 原点语义）
    // 面板高 108 → 左下角 y = 屏幕高 - (顶边 y + 108)
    let plan = Plan(
        widgetOriginCG: origin,
        widgetCenterCG: anchor,
        dragEndCG: end,
        widgetOriginAppKit: NSPoint(x: origin.x, y: screenH - origin.y - widgetSize.height)
    )

    let data = try! JSONEncoder().encode(plan)
    try! data.write(to: URL(fileURLWithPath: "/tmp/et_marquee_plan.json"))
    let out = String(data: data, encoding: .utf8)!

    print("裸桌面锚点 (CG): \(anchor)")
    print("拖拽方向: \(dirName)  终点 (CG): \(end)")
    print("挂件左上角 (CG): \(origin)")
    print("--move 参数 (AppKit): \(Int(plan.widgetOriginAppKit.x)) \(Int(plan.widgetOriginAppKit.y))")
    print("计划已写入 /tmp/et_marquee_plan.json")
    print(out)
    sem.signal()
}

sem.wait()
