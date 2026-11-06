import AppKit

/// 输入捕获面板。
///
/// ## 职责
///
/// 它**完全透明**（用户看不见），唯一作用是：
/// **在 Finder 的桌面窗口之前接管落在挂件矩形内的鼠标事件**，
/// 让 Finder 收不到这次按下 —— 桌面就不会再画出框选矩形。
///
/// ## 为什么需要它
///
/// 挂件的可视窗口在**桌面图标层之下**（`desktopIconWindow - 1`），
/// 这是「融进桌面」观感的前提 —— 桌面图标会盖在挂件上面。
///
/// 但代价是：**该层级的窗口完全不参与系统的鼠标命中测试**。
/// 实测（`Tools/probe_definitive.swift`）：
///
/// ```
/// 图标层-1  →  hitTest 从未被调用     ← 事件根本不路由过来
/// 图标层+1  →  hitTest 被调用         ← 事件路由过来了
/// ```
///
/// 所以把透明面板放到 floating window level，它就能先于 Finder 的桌面窗口拿到点击。
///
/// ## 首次点击（acceptsFirstMouse）
///
/// 本应用是 `LSUIElement`（纯菜单栏，从不激活）。
/// AppKit 默认行为是：非激活 App 的第一次点击只用来激活 App，不派发 mouseDown。
/// 因此视图必须重写 `acceptsFirstMouse(for:)` 返回 `true`。
final class WidgetInputPanel: NSPanel {

    /// 允许成为 key window —— 否则 mouseDown 会被窗口的 responder 链丢弃
    override var canBecomeKey: Bool { true }

    /// 不参与 main window
    override var canBecomeMain: Bool { false }
}

/// 输入捕获面板的宿主视图。
///
/// 事件回调全部使用 **AppKit 全局屏幕坐标**（左下原点）。
final class WidgetInputView: NSView {

    /// 事件回调
    var onDown: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onUp: ((NSPoint) -> Void)?
    var onHover: (() -> Void)?
    var onContextMenu: ((NSPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 始终接管命中测试，保证事件稳定送达
    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) { return self }
        return super.hitTest(point)
    }

    /// 允许未激活状态下直接接收首次点击（见 `WidgetInputPanel` 文档）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onDown?(screenPoint(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(screenPoint(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        onUp?(screenPoint(of: event))
    }

    // 右键只打开菜单，不进入左键拖拽状态机，也不向桌面回放点击。
    override func rightMouseDown(with event: NSEvent) {}

    override func rightMouseDragged(with event: NSEvent) {}

    override func rightMouseUp(with event: NSEvent) {
        onContextMenu?(screenPoint(of: event))
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?()
    }

    /// 事件坐标 → 屏幕坐标。
    ///
    /// 用 `convertPoint(toScreen:)` 而不是 `NSEvent.mouseLocation`：
    /// 前者直接来自事件本身，拖拽中也不会有额外延迟。
    private func screenPoint(of event: NSEvent) -> NSPoint {
        guard let window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}
