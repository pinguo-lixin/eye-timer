import AppKit

// 不显示窗口或申请权限；直接验证原生菜单动作与事件 tap 路由。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let settings = AppSettings.shared
let oldStyle = settings.widgetStyle
let oldTheme = settings.widgetTheme
let oldOpacity = settings.widgetOpacity
let engine = TimerEngine(settings: settings)
let provider = WidgetContextMenu(engine: engine, settings: settings)
var checks = 0
func check(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checks += 1
}
func activate(_ item: NSMenuItem) {
    check(app.sendAction(item.action!, to: item.target, from: item), "菜单动作可执行")
}

var menu = provider.makeMenu()
check(menu.items[0].title == "开始" && menu.items[0].isEnabled, "空闲时允许开始")
check(!menu.items[1].isEnabled, "空闲时禁止暂停")
activate(menu.items[0])
check(engine.state == .running, "菜单开始计时")
menu = provider.makeMenu()
check(!menu.items[0].isEnabled && menu.items[1].isEnabled, "运行时只允许暂停")
activate(menu.items[1])
check(engine.state == .paused, "菜单暂停计时")
let remaining = engine.remainingSeconds
menu = provider.makeMenu()
check(menu.items[0].title == "继续" && menu.items[0].isEnabled, "暂停时显示继续")
activate(menu.items[0])
check(engine.state == .running && engine.remainingSeconds == remaining, "继续保留剩余时间")
engine.skip()
check(engine.state == .resting, "进入休息")
menu = provider.makeMenu()
check(!menu.items[0].isEnabled && menu.items[1].isEnabled, "休息时可暂停")
activate(menu.items[1])
activate(provider.makeMenu().items[0])
check(engine.state == .resting, "继续休息不会重置为专注")
engine.stopAll()

for (index, style) in WidgetStyle.allCases.enumerated() {
    activate(provider.makeMenu().items[3].submenu!.items[index])
    check(settings.widgetStyle == style, "菜单切换样式")
    let choices = provider.makeMenu().items[3].submenu!.items
    check(choices.filter { $0.state == .on }.count == 1 && choices[index].state == .on,
          "仅当前样式勾选")
}
for (index, theme) in WidgetTheme.allCases.enumerated() {
    activate(provider.makeMenu().items[4].submenu!.items[index])
    check(settings.widgetTheme == theme, "菜单切换主题")
    let choices = provider.makeMenu().items[4].submenu!.items
    check(choices.filter { $0.state == .on }.count == 1 && choices[index].state == .on,
          "仅当前主题勾选")
}
let appearance = WidgetAppearanceModel()
appearance.updateHover(true)
provider.onOpacitySelected = { appearance.previewOpacity() }
for (index, preset) in WidgetContextMenu.opacityPresets.enumerated() {
    activate(provider.makeMenu().items[5].submenu!.items[index])
    check(settings.widgetOpacity == preset.0, "透明度档位立即生效")
    let choices = provider.makeMenu().items[5].submenu!.items
    check(choices.filter { $0.state == .on }.count == 1 && choices[index].state == .on,
          "仅当前透明度档位勾选")
    check(appearance.effectiveOpacity(base: settings.widgetOpacity, hoverHighlight: true) == preset.0,
          "悬停中选择透明度也能立即预览")
    let saved = UserDefaults.standard.data(forKey: "com.eyetimer.settings.v1")!
    let snapshot = try! JSONDecoder().decode(AppSettings.Snapshot.self, from: saved)
    check(snapshot.widgetOpacity == preset.0, "透明度选择已持久化")
}
settings.widgetOpacity = 0.57
let customMenu = provider.makeMenu().items[5].submenu!
check(customMenu.items.filter { $0.state == .on }.count == 1, "自定义透明度仅勾选一项")
check(customMenu.items[5].title.contains("57%") && !customMenu.items[5].isEnabled,
      "连续滑杆值在右键菜单显示为自定义")
settings.widgetOpacity = 0.1
check(provider.makeMenu().items[5].submenu!.items[5].title.contains("10%"), "保留现有滑杆最低10%")

var fineAdjustmentOpened = false
provider.onFineAdjustment = { fineAdjustmentOpened = true }
activate(customMenu.item(withTitle: "精细调节…")!)
check(!fineAdjustmentOpened, "精细调节等待菜单退出跟踪")
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(fineAdjustmentOpened, "精细调节触发设置导航回调")

check(appearance.isPreviewingOpacity, "选择后保持预览状态")
appearance.updateHover(true)
check(appearance.effectiveOpacity(base: 0.2, hoverHighlight: true) == 0.2,
      "未离开挂件时不会重新提亮")
appearance.updateHover(false)
check(!appearance.isPreviewingOpacity, "离开挂件后解除预览")
check(appearance.effectiveOpacity(base: 0.2, hoverHighlight: true) == 0.2, "鼠标离开时使用设定透明度")
appearance.updateHover(true)
check(appearance.effectiveOpacity(base: 0.2, hoverHighlight: true) == 1, "重新进入恢复悬停高亮")
check(appearance.effectiveOpacity(base: 0.2, hoverHighlight: false) == 0.2, "关闭高亮后始终使用设定值")
settings.widgetOpacity = oldOpacity
settings.widgetStyle = oldStyle
settings.widgetTheme = oldTheme

final class Receiver: MouseEventInterceptor.Delegate {
    var accepts = true
    var presses = 0
    var drags = 0
    var releases = 0
    var menus = 0
    func shouldCapture(at point: NSPoint) -> Bool { accepts }
    func didPress(at point: NSPoint) { presses += 1 }
    func didDrag(to point: NSPoint) { drags += 1 }
    func didRelease(at point: NSPoint) { releases += 1 }
    func didRequestContextMenu(at point: NSPoint) { menus += 1 }
}
let receiver = Receiver()
let tap = MouseEventInterceptor()
tap.delegate = receiver
func event(_ type: CGEventType, x: Double = 100) -> Unmanaged<CGEvent>? {
    let button: CGMouseButton = [.rightMouseDown, .rightMouseUp, .rightMouseDragged].contains(type) ? .right : .left
    let e = CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: CGPoint(x: x, y: 100), mouseButton: button)!
    return tap.handle(type: type, event: e)
}
check(event(.rightMouseDown) == nil, "右键按下被吞掉")
check(receiver.menus == 0, "按下不阻塞 tap 打开菜单")
check(event(.rightMouseDragged) == nil, "右键拖动不传给 Finder")
check(event(.rightMouseUp) == nil && receiver.menus == 1, "右键释放只请求一次菜单")
check(receiver.presses == 0 && receiver.drags == 0 && receiver.releases == 0, "右键不触发拖拽")
check(event(.rightMouseUp) != nil && receiver.menus == 1, "孤立的抬起不打开菜单")
receiver.accepts = false
check(event(.rightMouseDown) != nil && event(.rightMouseUp) != nil, "挂件外或菜单打开时放行右键")
receiver.accepts = true
check(event(.leftMouseDown) == nil, "左键仍可捕获")
check(event(.leftMouseDragged, x: 120) == nil, "左键仍可拖动")
check(event(.leftMouseUp, x: 120) == nil, "左键仍可释放")
check(receiver.presses == 1 && receiver.drags == 1 && receiver.releases == 1 && receiver.menus == 1,
      "左键拖动不会打开右键菜单")
check(event(.rightMouseDown) == nil, "捕获下一次右键")
tap.stop()
check(event(.rightMouseUp) != nil && receiver.menus == 1, "卸载清理右键捕获状态")

let view = WidgetInputView(frame: .zero)
var viewMenus = 0
view.onContextMenu = { _ in viewMenus += 1 }
view.onDown = { _ in preconditionFailure("右键不能触发左键处理") }
let down = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                             timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1,
                             clickCount: 1, pressure: 1)!
let up = NSEvent.mouseEvent(with: .rightMouseUp, location: .zero, modifierFlags: [],
                           timestamp: 0, windowNumber: 0, context: nil, eventNumber: 2,
                           clickCount: 1, pressure: 0)!
view.rightMouseDown(with: down)
view.rightMouseUp(with: up)
check(viewMenus == 1, "无事件 tap 时捕获面板也能打开菜单")
print("右键菜单验证通过：\(checks) 项检查")
