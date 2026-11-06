import AppKit
import SwiftUI
import Combine

/// 挂件的悬停 / 拖拽状态。
///
/// 单独抽成一个轻量 ObservableObject：视图只观察它，
/// 而不直接观察 `DesktopWidgetController`（否则视图 → 控制器 → 面板 → 视图 会形成引用环）。
final class WidgetAppearanceModel: ObservableObject {
    /// 鼠标是否正悬停在挂件上
    @Published var isHovering: Bool = false
    /// 拖拽中（用于切换光标）
    @Published var isDragging: Bool = false
    @Published private(set) var isPreviewingOpacity = false

    func previewOpacity() { isPreviewingOpacity = true }

    func updateHover(_ hovering: Bool) {
        // 离开挂件后解除预览；下次进入时照常提亮。
        if !hovering && isPreviewingOpacity { isPreviewingOpacity = false }
        if isHovering != hovering { isHovering = hovering }
    }

    func effectiveOpacity(base: Double, hoverHighlight: Bool) -> Double {
        hoverHighlight && isHovering && !isPreviewingOpacity ? 1 : min(1, max(0.05, base))
    }
}

/// 挂件宿主视图。
///
/// ## 拖拽为什么不用视图自己的 mouseDown / mouseDragged
///
/// 桌面模式下挂件的可视窗口层级低于桌面图标层，**系统完全不把它纳入鼠标命中测试** ——
/// 实测（`Tools/probe_desktop_point.swift`）在该层级下 `hitTest` 一次都不会被调用。
///
/// 因此真正的输入由 `MouseEventInterceptor`（事件 tap）在**事件层**接管，
/// 详见该类的文档。
///
/// ## 拖拽不平滑的根因（已修复）
///
/// 旧实现用 `NSPanGestureRecognizer.translation(in: nil)`，
/// 它返回的是**窗口坐标系**下的位移，而拖拽过程中窗口本身在移动：
///
/// ```
/// translation = (当前鼠标 - 当前窗口原点) - (起始鼠标 - 起始窗口原点)
///             = 起始窗口原点 - 当前窗口原点
///             = -Δ窗口
/// ```
///
/// 再套上 `newOrigin = dragOrigin + translation` 就变成
/// `newOrigin = 起始原点 - Δ窗口` —— **窗口朝拖拽的反方向跳**，
/// 形成负反馈，表现为拖拽剧烈抖动 / 跟不住鼠标。
///
/// 实测复现：632px 的拖拽，旧实现最终**滞后 316px**，且呈阶梯状跳动。
///
/// 正确做法是用**绝对屏幕坐标**算差值：
/// `newOrigin = 起始原点 + (当前鼠标 - 起始鼠标)`，完全绕开窗口坐标系，1:1 跟手。
final class WidgetHostView: NSHostingView<AnyView> {

    /// NSHostingView 的 `init(rootView:)` 是 required 的，
    /// 子类一旦声明了任何 designated init 就会失去自动继承，
    /// 所以这里显式补上并转发给 super。
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 命中测试

    /// 始终把鼠标事件交给自己处理。
    ///
    /// 挂件里没有任何可点击的子控件（纯展示），
    /// 显式接管命中测试可以保证事件稳定送达，
    /// 不受 SwiftUI 内部视图层级影响。
    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) { return self }
        return super.hitTest(point)
    }
}

/// 桌面挂件窗口控制器。
///
/// 核心是「桌面融合」：把 NSPanel 的 window level 设到
/// `kCGDesktopIconWindowLevel`（桌面图标层，-2147483603）**之下 1 级**，
/// 这样挂件会**夹在桌面背景和桌面图标之间**：
///  - 看得见（盖在桌面上）
///  - 不遮挡图标（图标在它上面）
///  - 切到别的 App 时被窗口盖住（像桌上真实摆件）
///
/// ## 鼠标输入怎么进来（修复「拖拽时桌面画矩形」）
///
/// 挂件在图标层之下 → 系统**完全不把它纳入鼠标命中测试**
/// → 点击穿透给 Finder → Finder 启动桌面框选 → 拖动时画出蓝色矩形。
///
/// 解决办法是 `MouseEventInterceptor`：在事件层拦截，
/// 把落在挂件矩形内的按下**吞掉**，Finder 收不到就不会画矩形。
/// 若缺少「辅助功能」授权导致拦截器不可用，会自动退回
/// `NSEvent.addGlobalMonitorForEvents` 方案（拖动仍然可用）。
final class DesktopWidgetController: NSObject, ObservableObject {

    static let shared = DesktopWidgetController()

    /// 壁纸层
    private static let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))      // -2147483623
    /// 桌面图标层
    private static let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) // -2147483603
    /// 插入点：**桌面图标层 - 1**（-2147483604）
    ///
    /// 为什么不是 `壁纸层 + 10`（-2147483613）：
    ///
    /// 挂件只要**低于桌面图标层**，渲染时桌面图标就会盖在它上面 ——
    /// 这正是「融进桌面」想要的观感。
    ///
    /// ⚠️ 实测结论（重要）：
    /// 低于图标层的窗口**完全不参与鼠标命中测试**，
    /// 且即便把透明窗提到图标层之上，`mouseDown` 也不会派发 ——
    /// 负层级窗口不属于前台 App 的事件路由。
    /// 所以必须在**事件层**拦截，见 `MouseEventInterceptor`。
    private static let widgetLevel = NSWindow.Level(desktopIconLevel - 1)

    /// 当前应当使用的挂件层级
    private func desiredLevel() -> NSWindow.Level {
        switch settings.layerMode {
        case .desktop:  return Self.widgetLevel
        case .floating: return NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)))
        case .hidden:   return Self.widgetLevel
        }
    }

    private var panel: NSPanel?
    /// 透明的输入捕获面板（与可视面板重叠，负责拦截鼠标事件）
    private var inputPanel: WidgetInputPanel?
    private var inputView: WidgetInputView?
    private let settings: AppSettings
    private let engine: TimerEngine
    private lazy var contextMenu: WidgetContextMenu = {
        let menu = WidgetContextMenu(engine: engine, settings: settings)
        menu.onOpacitySelected = { [weak self] in self?.appearance.previewOpacity() }
        menu.onFineAdjustment = { SettingsWindowController.shared.showOpacityControls() }
        return menu
    }()
    private var isContextMenuOpen = false
    private var cancellables = Set<AnyCancellable>()
    /// 层级守卫定时器
    private var levelGuardTimer: Timer?
    /// 悬停时短暂复用遮挡窗口的几何信息；按下时仍实时查询。
    private var occlusionCache: (time: TimeInterval, level: Int, rects: [CGRect])?

    /// 悬停 / 拖拽状态（供视图观察）
    let appearance = WidgetAppearanceModel()

    @Published var isVisible: Bool = true

    /// 挂件当前是否有辅助功能授权。
    ///
    /// 授权后事件 tap 可用 → 拖拽时直接吞掉按下事件，桌面完全不受影响。
    var isAccessibilityTrusted: Bool {
        AccessibilityAuthorization.isTrusted
    }

    /// 申请辅助功能授权（会弹出系统对话框）。
    func requestAccessibilityAuthorization() {
        AccessibilityAuthorization.request()
        AppLog.write("已请求辅助功能授权")
        // 用户在系统设置里勾选后需要重启 App 才完全生效，
        // 这里先刷新一次状态，尽早切换到干净模式。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibilityAuthorization()
        }
    }

    /// 打开「系统设置 → 隐私与安全性 → 辅助功能」。
    func openAccessibilitySettings() {
        AccessibilityAuthorization.openSystemSettings()
    }

    /// 重新检查授权状态；若已授权则立即切换到事件 tap 模式。
    func refreshAccessibilityAuthorization() {
        let trusted = AccessibilityAuthorization.isTrusted
        AppLog.write("辅助功能授权状态: \(trusted ? "已授权" : "未授权")")
        guard trusted else { return }
        // 已授权 → 重建输入处理，事件 tap 会挂上
        installInputHandling()
    }

    init(settings: AppSettings = .shared, engine: TimerEngine = .shared) {
        self.settings = settings
        self.engine = engine
        super.init()
        observeSettings()
    }

    // MARK: - 生命周期

    /// 创建并显示挂件
    func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }
        let panel = makePanel()
        self.panel = panel

        let inputPanel = makeInputPanel(size: targetSize)
        self.inputPanel = inputPanel
        self.inputView = inputPanel.contentView as? WidgetInputView

        panel.orderFrontRegardless()
        inputPanel.orderFrontRegardless()
        applyLevel()
        applyGeometry()
        restorePosition()
        startLevelGuard()
        installInputHandling()
        AppLog.write("挂件已创建 level=\(panel.level.rawValue) capture=\(inputPanel.level.rawValue) frame=\(panel.frame)")
    }

    /// 隐藏挂件
    func hide() {
        panel?.orderOut(nil)
        inputPanel?.orderOut(nil)
        isVisible = false
    }

    func destroy() {
        levelGuardTimer?.invalidate()
        levelGuardTimer = nil
        occlusionCache = nil
        removeInputHandling()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        inputPanel?.orderOut(nil)
        inputPanel?.contentView = nil
        inputPanel = nil
        inputView = nil
        setCursor(.none)
    }

    // MARK: - 面板构造

    private func makePanel() -> NSPanel {
        let size = targetSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 关键：无边框、不抢焦点、悬浮
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.level = Self.widgetLevel
        // 悬停检测需要接收 mouse-moved
        panel.acceptsMouseMovedEvents = true
        // 不参与窗口切换/Exposé
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isReleasedWhenClosed = false

        let host = WidgetHostView(rootView: AnyView(
            WidgetRootView()
                .environmentObject(engine)
                .environmentObject(settings)
                .environmentObject(appearance)
        ))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        return panel
    }

    /// 构造「输入捕获面板」：透明、盖在图标层之上，专门接管鼠标事件。
    ///
    /// 层级使用 floating window level（通常为 3），高于 Finder 的桌面窗口，
    /// 又低于菜单栏等系统浮层。面板只在鼠标位于挂件上时接收事件，
    /// 因此不会妨碍其它 App。
    private func makeInputPanel(size: NSSize) -> WidgetInputPanel {
        let panel = WidgetInputPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.level = desiredCaptureLevel()
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isReleasedWhenClosed = false
        // 只有鼠标位于挂件上方时才接收事件；离开后立即穿透给其它窗口。
        // 显式设置，避免依赖 NSWindow 默认值造成启动瞬间的点击被吞掉。
        panel.ignoresMouseEvents = true

        let view = WidgetInputView(frame: NSRect(origin: .zero, size: size))
        view.autoresizingMask = [.width, .height]
        view.onDown = { [weak self] point in self?.handleCaptureDown(at: point) }
        view.onDrag = { [weak self] point in self?.handleCaptureDrag(at: point) }
        view.onUp = { [weak self] point in self?.handleCaptureUp(at: point) }
        view.onContextMenu = { [weak self] point in self?.scheduleContextMenu(at: point) }
        view.onHover = { [weak self] in self?.refreshHoverState() }
        panel.contentView = view

        return panel
    }

    /// 输入捕获面板的层级。
    ///
    /// ## ⚠️ 必须使用 level ≥ 0（这是修复「拖拽时桌面画矩形」的关键）
    ///
    /// macOS 的桌面类窗口（壁纸 / Dock / 桌面图标）都位于**负层级**。
    /// 实测（`Tools/probe_widget_level.swift`，带 warp 自检）：
    ///
    /// ```
    /// level = icon+1  (-2147483602)  →  仍属于桌面背景，点击穿透给 Finder
    /// level = floating (3)          →  参与命中测试，能接管拖拽 ✅
    /// ```
    ///
    /// 原因：WindowServer 的命中测试**只在 level ≥ 0 的窗口之间做**；
    /// 负层级窗口属于「桌面背景」范畴，事件会直接落到其上层的
    /// 桌面窗口（Finder）手里。
    ///
    /// 所以捕获面板必须放在 **floating 层（level 3）** ——
    /// 它是普通「工具窗口」层级，参与命中测试，且低于菜单栏状态项（level 25）。
    ///
    /// ## 为什么不会挡住别的 App
    ///
    /// 捕获面板**完全透明**，且平时 `ignoresMouseEvents = true`（不接收事件）；
    /// 只有当鼠标**悬停在挂件上**时才临时设为 `false` 开始接管，
    /// 离开后立即恢复 —— 见 `refreshHoverState`。
    private func desiredCaptureLevel() -> NSWindow.Level {
        switch settings.layerMode {
        case .desktop, .hidden:
            return NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)))
        case .floating:
            return NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        }
    }

    // MARK: - 输入处理（事件 tap 优先，全局监视器兜底）

    /// 事件层拦截器
    private let interceptor = MouseEventInterceptor()

    /// 全局鼠标监视器（悬停 + 拦截器不可用时的拖拽兜底）
    private var globalMouseMonitor: Any?
    private var globalDragMonitor: Any?

    /// 拖拽起点（全局屏幕坐标，左下原点）
    private var dragStartMouseLocation: NSPoint = .zero
    /// 拖拽起点对应的挂件原点
    private var dragStartWindowOrigin: NSPoint = .zero
    private var isDragging = false
    /// 指针已按下但还没移动
    private var isPointerDown = false
    /// 本次按下过程中是否已经产生位移（用来区分「点击」与「拖拽」）
    private var hasMovedDuringPress = false
    /// 拖拽判定阈值（点）：小于它算点击
    private let dragThreshold: CGFloat = 3

    /// 自造 mouseUp 事件的标记。
    ///
    /// 全局监视器**无法吞掉**事件（`addGlobalMonitorForEvents` 的回调返回值被忽略），
    /// 所以要阻止 Finder 画框选矩形，只能在检测到按下的当下
    /// **补发一个 mouseUp** —— Finder 随即认为这次点击已经结束，框选立刻取消。
    ///
    /// 这个自造事件也会被全局监视器看到，
    /// 用 `eventSourceUserData` 字段打上标记，收到时直接忽略，
    /// 不影响我们自己的拖拽状态机。
    private static let syntheticUpTag: Int64 = 0x4554_494D_4549_4D01   // "ETIMEIM"
    /// 拖拽期间补发的无按键 mouseMoved 标记。
    private static let syntheticMoveTag: Int64 = 0x4554_494D_4549_4D02 // "ETIMEIM2"

    // MARK: - 按下的归属

    /// 一次按下的归属 —— 决定后续动作的唯一依据。
    ///
    /// 这是整个拖拽逻辑里**最关键**的判断，错误的判断会直接导致
    /// 「桌面画出蓝色矩形」且怎么补都补不掉。
    private enum PressOwnership {
        /// **我们吞掉了这次按下**（事件 tap 拦下了它，或捕获面板收到了 mouseDown）。
        ///
        /// Finder 从未见过这次按下 → 桌面上不可能有框选矩形。
        /// 此时**绝对不能补发 mouseUp**：
        /// 补发会把系统的「按键状态」提前改成「已抬起」，
        /// 而物理按键其实还按着 —— 下一批硬件 drag 事件到达时，
        /// 系统会认为这是一次**新的按下**，于是重新派发 mouseDown，
        /// Finder 由此**重新进入框选**，矩形又冒出来。
        /// 这正是「补了 mouseUp 反而还是画矩形」的真正原因。
        case captured

        /// **按下穿透给了别人**（Finder 的桌面窗口）。
        ///
        /// Finder 已经进入框选 → 必须补一个 mouseUp 把它的框选取消掉；
        /// 同时要激活本 App 接管后续的 drag 事件，
        /// 让 Finder 收不到拖拽，矩形才不会重新出现。
        case passedThrough
    }

    /// 当前这次按下的归属。
    private var pressOwnership: PressOwnership = .passedThrough

    // MARK: - 拖拽接管（激活本 App）

    /// 是否正在「激活接管」拖拽。
    private var takeoverActive = false
    /// 接管前的前台 App，拖拽结束后恢复。
    private var previousFrontmost: NSRunningApplication?
    /// 兜底定时器：万一 mouseUp 丢了，最多 3 秒后自动把前台还给用户。
    private var takeoverTimer: Timer?

    /// 安装输入处理。
    ///
    /// 首选事件 tap（能吞掉事件 → 桌面不画矩形）；
    /// 失败则退回全局监视器 + 激活接管。
    private func installInputHandling() {
        removeInputHandling()

        interceptor.delegate = self
        let tapOK = DebugSwitches.forceFallbackPath ? false : interceptor.start()
        let trusted = AccessibilityAuthorization.isTrusted
        AppLog.write("输入处理: 事件 tap=\(tapOK ? "可用" : "不可用")  辅助功能授权=\(trusted ? "有" : "无")")

        // 悬停：全局监听鼠标移动（鼠标在其他 App 上时生效）
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            self?.refreshHoverState()
        }

        // 启动时鼠标可能已经停在挂件上，不能等下一次 mouseMoved 才打开捕获面板。
        DispatchQueue.main.async { [weak self] in
            self?.refreshHoverState()
        }

        // 拖拽兜底：仅在事件 tap 不可用时启用
        if !tapOK {
            globalDragMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handleGlobalMouse(event)
            }
        }
    }

    private func removeInputHandling() {
        interceptor.stop()
        interceptor.delegate = nil
        if let m = globalMouseMonitor {
            NSEvent.removeMonitor(m)
            globalMouseMonitor = nil
        }
        if let m = globalDragMonitor {
            NSEvent.removeMonitor(m)
            globalDragMonitor = nil
        }
    }

    /// 全局兜底拖拽路径。
    ///
    /// 只在事件 tap 不可用（缺少辅助功能授权）时才会走到这里。
    /// 此时点击仍会穿透给 Finder，靠「补发 mouseUp + 持续抵消」来取消桌面的框选矩形。
    ///
    /// ## 为什么不能只补一次 mouseUp
    ///
    /// 实测（`Tools/probe_physical_drag.swift`，真实物理拖拽）：
    /// 物理拖拽时 HID 的按键状态**持续存在**，硬件 drag 事件会源源不断送达 Finder，
    /// 让它**重新进入**框选模式 —— 只补一次 mouseUp 只能抵消「按下瞬间」的那次框选，
    /// 用户快速拖动时矩形仍会闪现。
    ///
    /// 因此这里采用「**持续抵消**」：
    ///   - 按下时补一个 mouseUp                → 让 Finder 认为点击已结束
    ///   - 每个后续 drag 后补一个**无按键**的 mouseMoved
    ///     → 持续告诉系统「鼠标在移动，但没有按键」→ Finder 不会画出矩形
    private func handleGlobalMouse(_ event: NSEvent) {
        guard let panel, !isContextMenuOpen else { return }
        let mouse = NSEvent.mouseLocation          // 左下原点
        let frame = panel.frame

        switch event.type {
        case .leftMouseDown:
            guard frame.contains(mouse) else { return }
            // 挂件被别的 App 窗口盖住时，这次点击属于那个 App —— 不要插手。
            guard isWidgetTopmost(appKitPoint: mouse) else {
                AppLog.write("挂件被其它窗口覆盖，放弃接管本次点击")
                return
            }
            beginPress(at: mouse, origin: frame.origin)
            setCursor(.closedHand)
            // 关键：立刻补一个 mouseUp，取消 Finder 的桌面框选（否则会画出蓝色矩形）
            cancelDesktopMarquee(at: mouse)

        case .leftMouseDragged:
            guard isPointerDown else { return }
            updateDrag(to: mouse)
            // 持续抵消：补一个无按键的 mouseMoved，让 Finder 保持「未按下」状态
            cancelDesktopDragEcho(at: mouse)

        case .leftMouseUp:
            // 忽略我们自己补发的 mouseUp / mouseMoved —— 它们只是用来抵消桌面框选
            if let tag = event.cgEvent?.getIntegerValueField(CGEventField.eventSourceUserData),
               tag == Self.syntheticUpTag || tag == Self.syntheticMoveTag {
                return
            }
            guard isPointerDown else { return }
            endPress(at: mouse)

        default:
            break
        }
    }

    // MARK: - 右键菜单

    private func scheduleContextMenu(at point: NSPoint) {
        guard let panel, panel.isVisible, settings.layerMode != .hidden,
              !isContextMenuOpen, !isPointerDown else { return }
        isContextMenuOpen = true
        // 菜单期间交给 AppKit 跟踪点击，避免事件 tap 吞掉菜单项选择。
        inputPanel?.ignoresMouseEvents = true
        setCursor(.none)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer {
                self.isContextMenuOpen = false
                self.refreshHoverState()
            }
            guard self.panel?.isVisible == true, self.settings.layerMode != .hidden else { return }
            self.contextMenu.makeMenu().popUp(positioning: nil, at: point, in: nil)
        }
    }

    // MARK: - 输入捕获面板事件

    /// 捕获面板收到按下
    private func handleCaptureDown(at mouse: NSPoint) {
        guard let panel else { return }
        beginPress(at: mouse, origin: panel.frame.origin)
        setCursor(.closedHand)
    }

    /// 悬停命中挂件时，是否需要把光标切成「抓手」
    ///
    /// 由输入捕获面板的 `mouseMoved` 驱动。
    private func handleCaptureHover() {
        refreshHoverState()
    }

    /// 捕获面板收到拖动
    private func handleCaptureDrag(at mouse: NSPoint) {
        updateDrag(to: mouse)
    }

    /// 捕获面板收到抬起
    private func handleCaptureUp(at mouse: NSPoint) {
        // 全程没移动 → 这是一次「点击」而非拖拽。
        // 把它回放给桌面，保证压在挂件下面的桌面图标依然点得到。
        if !hasMovedDuringPress {
            replayClickToDesktop(at: mouse)
        }
        endPress(at: mouse)
    }

    /// 把一次「点击（而非拖拽）」回放给桌面。
    ///
    /// 输入捕获面板挡住了挂件正下方那一小块区域，
    /// 若桌面图标与挂件重叠就点不到了 ——
    /// 这里把点击重新发给系统，让 Finder 照常处理。
    private func replayClickToDesktop(at mouse: NSPoint) {
        guard let inputPanel else { return }
        inputPanel.ignoresMouseEvents = true

        let quartz = MouseEventInterceptor.quartzPoint(fromAppKit: mouse)
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                              mouseCursorPosition: quartz, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                            mouseCursorPosition: quartz, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            // 鼠标可能已经移出挂件；按当前命中状态决定是否重新打开捕获。
            self?.refreshHoverState()
        }
    }

    /// 补发一个 mouseUp，取消 Finder 的桌面框选矩形。
    ///
    /// ## 为什么需要它
    ///
    /// 挂件在**桌面图标层之下**，点击必然穿透给 Finder 的桌面窗口，
    /// Finder 于是启动「框选」—— 拖动时就在桌面上画出一个蓝色矩形。
    ///
    /// 全局鼠标监视器**不能吞掉**事件（回调的返回值会被忽略），
    /// 所以这里换个思路：既然按下的那一刻 Finder 已经开始框选，
    /// 那就**立刻补一个 mouseUp** 告诉它「这次点击已经结束」，
    /// 框选随即取消 —— 用户根本看不到那个矩形。
    ///
    /// 补发的事件用 `eventSourceUserData` 打上标记，
    /// 稍后被全局监视器收到时会被识别并忽略，不会干扰我们自己的拖拽状态机。
    private func cancelDesktopMarquee(at mouse: NSPoint) {
        // 对照开关：关掉后应当能复现「拖拽时桌面画矩形」
        if DebugSwitches.disableMarqueeFix {
            AppLog.write("补发 mouseUp 已禁用（对照模式）")
            return
        }
        let quartz = MouseEventInterceptor.quartzPoint(fromAppKit: mouse)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: quartz, mouseButton: .left) else { return }
        up.setIntegerValueField(CGEventField.eventSourceUserData, value: Self.syntheticUpTag)
        up.post(tap: .cghidEventTap)
        AppLog.write("已补发 mouseUp 取消桌面框选")
    }

    /// 拖拽期间持续抵消：补发一个**无按键**的 mouseMoved。
    ///
    /// ## 为什么需要它
    ///
    /// 「补一次 mouseUp」只能抵消**按下那一瞬间**触发的框选。
    /// 但物理拖拽时，HID 的按键状态**持续存在**，
    /// 后续的硬件 drag 事件会源源不断送到 Finder，
    /// 让它**重新进入**框选模式 —— 表现为拖动过程中矩形又冒出来。
    ///
    /// 实测（`Tools/probe_physical_drag.swift`）：
    /// 物理拖拽的典型时序是
    /// ```
    /// down ──(4~14ms)──► 我们的补偿 mouseUp
    ///      ──(245ms)─────► 第一个硬件 drag
    ///      ──(每 50~60ms)─► 后续硬件 drag ……
    /// ```
    /// 补偿虽然比第一个 drag 早得多，但只要硬件 drag 还在继续，
    /// Finder 就还有机会重新框选。
    ///
    /// 解决办法：在每个 drag 之后补一个**不带按键**的 mouseMoved，
    /// 持续告诉系统「鼠标在移动，但左键并没有按下」——
    /// Finder 因此不会进入框选，矩形也就不会出现。
    ///
    /// 补发的事件同样打上标记，被自己的全局监视器收到时忽略。
    private func cancelDesktopDragEcho(at mouse: NSPoint) {
        // 对照开关：关掉后应当能复现「拖拽时桌面画矩形」
        if DebugSwitches.disableMarqueeFix { return }

        let quartz = MouseEventInterceptor.quartzPoint(fromAppKit: mouse)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: quartz, mouseButton: .left) else { return }
        moved.setIntegerValueField(CGEventField.eventSourceUserData, value: Self.syntheticMoveTag)
        moved.post(tap: .cghidEventTap)
    }

    // MARK: - 拖拽状态机

    /// 开始一次按下
    private func beginPress(at mouse: NSPoint, origin: NSPoint) {
        dragStartMouseLocation = mouse
        dragStartWindowOrigin = origin
        isPointerDown = true
        hasMovedDuringPress = false
        isDragging = false
    }

    /// 拖动更新
    private func updateDrag(to mouse: NSPoint) {
        let dx = mouse.x - dragStartMouseLocation.x
        let dy = mouse.y - dragStartMouseLocation.y

        if !hasMovedDuringPress {
            // 还没超过阈值 → 这可能只是一次点击，先不动
            if abs(dx) < dragThreshold && abs(dy) < dragThreshold { return }
            hasMovedDuringPress = true
            isDragging = true
            appearance.isDragging = true
            setCursor(.closedHand)
        }

        // 关键：用绝对屏幕坐标算差值，绕开窗口坐标系 → 1:1 跟手
        setWidgetOrigin(NSPoint(x: dragStartWindowOrigin.x + dx,
                                y: dragStartWindowOrigin.y + dy))
    }

    /// 结束一次按下
    private func endPress(at mouse: NSPoint) {
        isPointerDown = false
        if isDragging {
            isDragging = false
            appearance.isDragging = false
            if let panel { savePosition(panel.frame.origin) }
            setCursor(appearance.isHovering ? .openHand : .none)
        }
        // 「点击而非拖拽」的回放由拦截器负责（这里不用管）
    }

    /// 刷新悬停状态（根据鼠标是否落在挂件矩形内）
    private func refreshHoverState() {
        guard let panel, panel.isVisible, !isContextMenuOpen, !isDragging, !isPointerDown else { return }
        let point = NSEvent.mouseLocation
        let inside = panel.frame.contains(point)
        // 被别的 App 窗口盖住时不要改光标 —— 那不是「指着挂件」
        let effective = inside && isWidgetTopmost(appKitPoint: point, maximumAge: 0.1)
        // 捕获面板位于 floating 层，若一直接收事件会挡住其它 App。
        // 只在挂件实际可交互时打开它，进入其它窗口后立即穿透。
        if let inputPanel, inputPanel.ignoresMouseEvents != !effective {
            inputPanel.ignoresMouseEvents = !effective
        }
        // 菜单关闭后即使悬停状态没变化，也要恢复此前让给菜单的光标。
        setCursor(effective ? .openHand : .none)
        appearance.updateHover(effective)
    }

    // MARK: - 光标

    /// 期望显示的光标。
    private enum WidgetCursor {
        case none, openHand, closedHand
    }

    /// 当前**期望**的光标（状态机输入）
    private var desiredCursor: WidgetCursor = .none
    /// 当前**实际**压栈的光标（用于保证 push / pop 严格配对）
    private var currentCursor: WidgetCursor = .none

    /// 切换光标。
    ///
    /// 用「期望值 + 实际值」两套状态来管理，保证 `push` / `pop` 严格配对 ——
    /// 旧实现 push 了 closedHand 却没对应 pop，光标会一直卡在闭手状态。
    private func setCursor(_ cursor: WidgetCursor) {
        guard cursor != desiredCursor else { return }
        desiredCursor = cursor

        // 先把当前压栈的弹掉
        switch currentCursor {
        case .openHand:   NSCursor.pop()
        case .closedHand: NSCursor.pop()
        case .none:       break
        }
        currentCursor = .none

        // 再压入新的
        switch cursor {
        case .openHand:
            NSCursor.openHand.push()
            currentCursor = .openHand
        case .closedHand:
            NSCursor.closedHand.push()
            currentCursor = .closedHand
        case .none:
            break
        }
    }

    // MARK: - 尺寸

    /// 挂件当前应有的屏幕尺寸 = 固有尺寸 × 用户缩放
    private var targetSize: NSSize {
        let base = settings.widgetStyle.intrinsicSize
        let scale = max(0.4, settings.widgetScale)
        return NSSize(width: base.width * scale, height: base.height * scale)
    }

    /// 更新面板尺寸（样式或缩放变化时调用）
    func applyGeometry() {
        guard let panel else { return }
        let size = targetSize
        var frame = panel.frame
        let origin = frame.origin
        frame.size = size
        frame.origin = clampToScreen(origin, size: size)
        panel.setFrame(frame, display: true)
        (panel.contentView as? WidgetHostView)?.frame = NSRect(origin: .zero, size: size)

        // 输入捕获面板与可视面板保持完全重叠
        if let inputPanel {
            var inputFrame = inputPanel.frame
            inputFrame.origin = frame.origin
            inputFrame.size = size
            inputPanel.setFrame(inputFrame, display: false)
            (inputPanel.contentView as? WidgetInputView)?.frame = NSRect(origin: .zero, size: size)
        }
    }

    // MARK: - 层级与位置

    /// 根据用户设置应用窗口层级
    func applyLevel() {
        guard let panel else { return }
        if settings.layerMode == .hidden {
            panel.orderOut(nil)
            inputPanel?.orderOut(nil)
            return
        }
        panel.level = desiredLevel()
        panel.orderFrontRegardless()
        applyCaptureLevel()
        // SwiftUI 的 NSHostingView 在完成首次布局后会把宿主窗口的 level 重置为 0，
        // 因此需要在布局完成后再设一次。连续设几次可以覆盖不同的布局时机。
        for delay in [0.0, 0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let p = self.panel, self.settings.layerMode != .hidden else { return }
                let desired = self.desiredLevel()
                if p.level != desired {
                    p.level = desired
                }
                self.applyCaptureLevel()
            }
        }
    }

    /// 设置输入捕获面板的层级并前置显示。
    ///
    /// 它必须始终压过 Finder 的桌面窗口（图标层），
    /// 否则点击会穿透给 Finder，桌面就会画出框选矩形。
    private func applyCaptureLevel() {
        guard let inputPanel else { return }
        let desired = desiredCaptureLevel()
        if inputPanel.level != desired {
            inputPanel.level = desired
            inputPanel.orderFrontRegardless()
        } else if !inputPanel.isVisible {
            inputPanel.orderFrontRegardless()
        }
    }

    /// 层级守卫。
    ///
    /// SwiftUI 的 App 生命周期在启动过程中会对窗口层级做自己的管理，
    /// 实测会把我们设到桌面层的 panel 拉回 level 0。
    /// 这里用一个轻量定时器持续校验层级，一旦被改动就立刻纠正，
    /// 保证挂件始终稳定待在壁纸层与图标层之间。
    private func startLevelGuard() {
        levelGuardTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            guard self.settings.layerMode != .hidden else { return }
            let desired = self.desiredLevel()
            if panel.level != desired {
                panel.level = desired
                panel.orderFrontRegardless()
                AppLog.write("层级被重置为 \(panel.level.rawValue)，已纠正回 \(desired.rawValue)")
            }
            // 输入捕获面板必须始终压过 Finder 的桌面窗口，否则点击会穿透、桌面会画框选矩形
            self.applyCaptureLevel()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        levelGuardTimer = timer
    }

    /// 同时移动「可视面板」与「输入捕获面板」，保持两者重叠。
    private func setWidgetOrigin(_ origin: NSPoint) {
        guard let panel else { return }
        let clamped = clampToScreen(origin)
        panel.setFrameOrigin(clamped)
        inputPanel?.setFrameOrigin(clamped)
    }

    /// 位置持久化：存归一化坐标，跨分辨率/显示器保持相对位置
    private func savePosition(_ origin: NSPoint) {
        guard let screen = screenContaining(origin) else { return }
        let visible = screen.visibleFrame
        let size = targetSize
        let x = (origin.x - visible.minX) / max(1, visible.width - size.width)
        let y = (origin.y - visible.minY) / max(1, visible.height - size.height)
        settings.widgetX = min(1, max(0, x))
        settings.widgetY = min(1, max(0, y))
    }

    private func restorePosition() {
        guard panel != nil else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = targetSize
        let x = visible.minX + settings.widgetX * max(1, visible.width - size.width)
        let y = visible.minY + settings.widgetY * max(1, visible.height - size.height)
        setWidgetOrigin(clampToScreen(NSPoint(x: x, y: y), size: size))
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? NSScreen.main
    }

    private func clampToScreen(_ origin: NSPoint, size: NSSize? = nil) -> NSPoint {
        let size = size ?? targetSize
        guard let screen = screenContaining(origin) ?? NSScreen.main else { return origin }
        let visible = screen.visibleFrame
        var x = origin.x
        var y = origin.y
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    /// 把挂件移动到指定的屏幕坐标（左下原点）—— **测试辅助用**
    ///
    /// 仅供自动化验证把挂件放到指定的裸桌面区域，
    /// 由 `EyeTimerApp` 在开启诊断开关时调用。
    func moveWidget(to point: NSPoint) {
        setWidgetOrigin(clampToScreen(point))
        savePosition(panel?.frame.origin ?? point)
        AppLog.write("挂件已移动到 \(point)")
    }

    /// 居中到当前屏幕
    func centerOnScreen() {
        guard let panel, let visible = NSScreen.main?.visibleFrame else { return }
        let x = visible.midX - panel.frame.width / 2
        let y = visible.midY - panel.frame.height / 2
        setWidgetOrigin(clampToScreen(NSPoint(x: x, y: y)))
        savePosition(panel.frame.origin)
    }

    // MARK: - 设置联动

    private func observeSettings() {
        settings.$layerMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if mode == .hidden {
                    self.hide()
                } else {
                    if self.panel == nil { self.show() }
                    self.applyLevel()
                }
            }
            .store(in: &cancellables)

        // 样式或缩放变化 → 重新计算挂件尺寸
        Publishers.CombineLatest(settings.$widgetStyle, settings.$widgetScale)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.applyGeometry()
            }
            .store(in: &cancellables)
    }
}

// MARK: - 事件拦截器回调

extension DesktopWidgetController: MouseEventInterceptor.Delegate {

    /// 该点是否由我们接管。
    ///
    /// 只有落在挂件矩形内、**且挂件确实是最上层的窗口**时才接管。
    ///
    /// ## 为什么还要检查层级
    ///
    /// 挂件在**桌面图标层之下**，比所有普通 App 窗口都低。
    /// 当别的 App 窗口盖住挂件时，那次点击**本来就应该属于那个 App**：
    ///   - 若我们照样接管 → 那个 App 的这次点击会被打断（补发的 mouseUp）
    ///   - 若我们照样接管 → 用户在那个 App 上拖动，会意外把挂件拖走
    ///
    /// 所以必须先确认「点下去的时候，最上面的是不是我们」。
    func shouldCapture(at point: NSPoint) -> Bool {
        guard let panel, panel.isVisible, settings.layerMode != .hidden, !isContextMenuOpen else { return false }
        guard panel.frame.contains(point) else { return false }
        return isWidgetTopmost(appKitPoint: point)
    }

    func didRequestContextMenu(at point: NSPoint) {
        scheduleContextMenu(at: point)
    }

    func didPress(at point: NSPoint) {
        guard let panel else { return }
        beginPress(at: point, origin: panel.frame.origin)
        setCursor(.closedHand)
    }

    func didDrag(to point: NSPoint) {
        updateDrag(to: point)
    }

    func didRelease(at point: NSPoint) {
        endPress(at: point)
    }
}

// MARK: - 层级判定

extension DesktopWidgetController {

    /// 该点是否被其它普通 App 窗口覆盖。
    ///
    /// 不能简单取 `CGWindowList` 中 layer 最大的窗口。macOS 会在列表里
    /// 放入 `FgLevel`、Dock 容器等覆盖整屏的系统浮层（通常是透明容器），
    /// 它们的 layer 常常是 18 以上；把这类窗口当成遮挡者会让兜底路径
    /// 跳过 mouseUp 抵消，Finder 就会画出桌面框选矩形。
    ///
    /// 这里只把实际参与普通窗口命中测试的 layer 0~17 视为遮挡者，
    /// 并比较它与可视挂件窗口的层级。输入捕获面板虽然位于 floating 层，
    /// 也不能因为它透明且更高就把其它 App 的点击截走。
    ///
    /// ⚠️ **坐标系**：本方法接收 **AppKit 全局坐标（左下原点）**，
    /// 而 `CGWindowList` 的 bounds 是 **Quartz 坐标（左上原点）**，
    /// 两者必须转换后才能比较 —— 直接比较会误判成「被覆盖」。
    ///
    /// - Parameter appKitPoint: AppKit 全局坐标（左下原点）
    func isWidgetTopmost(appKitPoint: NSPoint, maximumAge: TimeInterval = 0) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let widgetLevel = panel?.level.rawValue ?? 0
        let quartz = MouseEventInterceptor.quartzPoint(fromAppKit: appKitPoint)
        if maximumAge > 0, let cache = occlusionCache,
           cache.level == widgetLevel, now - cache.time < maximumAge {
            return !cache.rects.contains { $0.contains(quartz) }
        }
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else {
            // 拿不到窗口列表时保守处理：仍然接管（维持原有行为）
            return true
        }

        let myPID = ProcessInfo.processInfo.processIdentifier

        // 普通 App 窗口的层级范围。更高层通常是系统浮层容器（例如 FgLevel），
        // 它们不代表鼠标实际会落到一个可交互的遮挡窗口。
        let ordinaryAppLayerRange = 0..<18
        var rects: [CGRect] = []

        for w in list {
            let pid = w[kCGWindowOwnerPID as String] as? Int ?? -1
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            guard ordinaryAppLayerRange.contains(layer), pid != myPID else { continue }
            // 低于可视挂件的普通窗口不会挡住挂件；高于或同层则优先交给它。
            guard layer >= widgetLevel else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
            let rect = CGRect(x: b["X"] as? Double ?? 0,
                              y: b["Y"] as? Double ?? 0,
                              width: b["Width"] as? Double ?? 0,
                              height: b["Height"] as? Double ?? 0)
            rects.append(rect)
        }

        occlusionCache = (now, widgetLevel, rects)

        // 裸桌面、Finder 桌面和系统浮层都不阻止挂件接管。
        return !rects.contains { $0.contains(quartz) }
    }
}
