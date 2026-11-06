import AppKit
import CoreGraphics

/// 鼠标事件拦截器。
///
/// ## 为什么需要它（修复「拖拽时桌面画矩形」）
///
/// 挂件的可视窗口放在**桌面图标层之下**（`desktopIconWindow - 1`），
/// 这是「融进桌面」观感的前提 —— 桌面图标会盖在挂件上面。
///
/// 但代价是：**该层级的窗口完全不参与系统的鼠标命中测试**。
/// 实测（`Tools/probe_desktop_point.swift`）：
///
/// ```
/// 图标层-1  →  hitTest 从未被调用   ← 事件根本不会路由过来
/// 图标层    →  hitTest 被调用，但 mouseDown 不派发
/// 图标层+1  →  hitTest 被调用，但 mouseDown 不派发
/// ```
///
/// 负层级窗口不属于前台 App 的事件路由，所以哪怕把一块透明窗提到图标层之上，
/// 点击也依然穿透给 Finder —— Finder 于是启动桌面框选，拖动时画出那个矩形。
///
/// ## 解法 A：事件 tap（首选，需辅助功能授权）
///
/// `CGEvent.tapCreate` 能在事件**派发给 Finder 之前**把它拦下来。
/// 本类在 session 层挂一个 tap：
///   - 落在挂件矩形内的 `mouseDown`  → **吞掉**（返回 nil），Finder 收不到 → 不画矩形
///   - 后续 `mouseDragged`            → 吞掉 + 驱动挂件 1:1 跟手
///   - `mouseUp`                      → 吞掉 + 结束拖拽
///   - 若全程没移动（是一次点击）      → 把点击**回放**给桌面，保证下面的图标仍可点
///
/// ⚠️ **授权与启动方式的关系**（实测，详见 `AccessibilityAuthorization`）：
/// 用户双击（`open`）启动时拿不到辅助功能授权 → `defaultTap` 创建失败 → 本类不可用。
/// 此时走解法 B。
///
/// ## 解法 B：全局监视器 + 事件抵消（兜底，无需授权）
///
/// 没有事件 tap 时，退而求其次：由 `DesktopWidgetController` 用
/// `NSEvent.addGlobalMonitorForEvents` 观察鼠标事件，并在
/// 「按下瞬间」补发一个 mouseUp、在「拖拽过程中」持续补发无按键的 mouseMoved，
/// 让 Finder 始终认为「鼠标没有按下」—— 从而不画出框选矩形。
///
/// 详见 `DesktopWidgetController.cancelDesktopMarquee` 与
/// `DesktopWidgetController.cancelDesktopDragEcho`。
///
/// ## 权限
///
/// - 解法 A（defaultTap）需要「辅助功能」授权
/// - 解法 B 不需要任何权限
final class MouseEventInterceptor {

    /// 事件回调协议（全部使用 **AppKit 全局坐标**，左下原点）。
    protocol Delegate: AnyObject {
        /// 该点是否由我们接管（返回 true 表示吞掉这个事件）
        func shouldCapture(at point: NSPoint) -> Bool
        /// 按下（已被接管）
        func didPress(at point: NSPoint)
        /// 拖动（已被接管）
        func didDrag(to point: NSPoint)
        /// 右键释放后请求菜单（展示必须异步离开 tap 回调）。
        func didRequestContextMenu(at point: NSPoint)
        /// 抬起（已被接管）
        func didRelease(at point: NSPoint)
    }

    weak var delegate: Delegate?

    /// 是否已成功挂上事件 tap
    private(set) var isActive = false

    /// 事件 tap 句柄
    private var tap: CFMachPort?

    /// 当前是否正在接管一次按下
    private var capturing = false
    private var capturingContextClick = false

    /// 回放点击时置位：让回放出去的事件不再被自己吞掉
    private var replayingClick = false

    /// 正在被接管的按下所发生的位移（用于区分「点击」与「拖拽」）
    private var pressOrigin: NSPoint = .zero
    private var movedBeyondThreshold = false
    /// 拖拽判定阈值（点）
    private let dragThreshold: CGFloat = 3

    // MARK: - 事件类型掩码

    /// 事件类型掩码
    private static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.rightMouseDragged.rawValue)
        | (1 << CGEventType.rightMouseUp.rawValue)

    // MARK: - 生命周期

    /// 挂上事件 tap。
    ///
    /// - Returns: 是否成功（失败通常意味着缺少「辅助功能」授权）
    @discardableResult
    func start() -> Bool {
        stop()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MouseEventInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handle(type: type, event: event)
        }

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: callback,
            userInfo: unmanagedSelf
        ) else {
            AppLog.write("❌ 事件 tap 创建失败（缺少辅助功能授权？）")
            isActive = false
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        isActive = true
        AppLog.write("✅ 事件 tap 已挂载")
        return true
    }

    /// 卸载事件 tap
    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        isActive = false
        capturing = false
        capturingContextClick = false
    }

    deinit {
        stop()
    }

    // MARK: - 事件处理

    /// tap 回调
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 回放点击时，放行事件
        if replayingClick {
            return Unmanaged.passUnretained(event)
        }

        let point = Self.appKitPoint(fromQuartz: event.location)

        switch type {
        case .rightMouseDown:
            guard !capturing, let delegate, delegate.shouldCapture(at: point) else {
                return Unmanaged.passUnretained(event)
            }
            capturingContextClick = true
            return nil

        case .rightMouseDragged:
            return capturingContextClick ? nil : Unmanaged.passUnretained(event)

        case .rightMouseUp:
            guard capturingContextClick else { return Unmanaged.passUnretained(event) }
            capturingContextClick = false
            // 菜单跟踪会运行嵌套事件循环，必须离开 tap 回调后再打开。
            delegate?.didRequestContextMenu(at: point)
            return nil

        case .leftMouseDown:
            guard let delegate, delegate.shouldCapture(at: point) else {
                return Unmanaged.passUnretained(event)
            }
            // 关键：吞掉这次按下 → Finder 收不到 → 不会画框选矩形
            capturing = true
            pressOrigin = point
            movedBeyondThreshold = false
            delegate.didPress(at: point)
            return nil

        case .leftMouseDragged:
            guard capturing, let delegate else {
                return Unmanaged.passUnretained(event)
            }
            let dx = point.x - pressOrigin.x
            let dy = point.y - pressOrigin.y
            if !movedBeyondThreshold {
                if abs(dx) < dragThreshold && abs(dy) < dragThreshold {
                    // 还没超过阈值：可能只是一次点击，先不移动
                    return nil
                }
                movedBeyondThreshold = true
            }
            delegate.didDrag(to: point)
            return nil

        case .leftMouseUp:
            guard capturing, let delegate else {
                return Unmanaged.passUnretained(event)
            }
            capturing = false
            delegate.didRelease(at: point)
            // 若是「点击」而非拖拽，把点击回放给桌面
            if !movedBeyondThreshold {
                replayClick(at: point)
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// 把一次「点击」回放给桌面。
    ///
    /// 捕获面板挡住了挂件正下方那一小块区域，
    /// 若桌面图标与挂件重叠就点不到了 —— 回放让 Finder 照常处理。
    private func replayClick(at point: NSPoint) {
        replayingClick = true
        let quartz = Self.quartzPoint(fromAppKit: point)
        let source = CGEventSource(stateID: .hidSystemState)

        if let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                              mouseCursorPosition: quartz, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                            mouseCursorPosition: quartz, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }

        // 下一个 runloop 回合再恢复放行，确保回放的事件不被自己吞掉
        DispatchQueue.main.async { [weak self] in
            self?.replayingClick = false
        }
    }

    // MARK: - 坐标转换

    /// Quartz 全局坐标（左上原点） → AppKit 全局坐标（左下原点）。
    ///
    /// Quartz 的全局坐标系原点固定在**主显示器左上角**，
    /// AppKit 的原点在主显示器左下角，两者相差一个主屏高度。
    /// 副屏在上方时 Quartz 的 y 为负、AppKit 的 y 大于主屏高度，公式依然成立。
    static func appKitPoint(fromQuartz point: CGPoint) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// AppKit 全局坐标（左下原点） → Quartz 全局坐标（左上原点）。
    static func quartzPoint(fromAppKit point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
