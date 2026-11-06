# EyeTimer 本地测试与分发评估

评估日期：2026-11-06。实测环境：macOS 26.5.2，Apple Silicon，单显示器 3440×1440。

## 发布目标

GitHub 源码 / 独立分发版本默认不启用 App Sandbox。Mac App Store 的强制沙盒要求不是该版本的验收条件。
保留现有桌面挂件、原生右键菜单与拖拽防选框实现。

## 隔离沙盒实验

`Tools/DistributionProbe/main.swift` 与正式应用共用 Core / Views 源码，但使用独立 Bundle ID、UserDefaults 域和容器，不覆盖正式应用设置。
分别构建普通签名与沙盒签名应用：

```bash
bash Tools/build_distribution_probes.sh
: > /tmp/eyetimer-probe-plain.json
: > /tmp/eyetimer-probe-sandbox.json
open -W -n -g .build/distribution-probes/EyeTimerProbe-plain.app \
  --stdout /tmp/eyetimer-probe-plain.json --stderr /tmp/eyetimer-probe-plain.stderr
open -W -n -g .build/distribution-probes/EyeTimerProbe-sandbox.app \
  --stdout /tmp/eyetimer-probe-sandbox.json --stderr /tmp/eyetimer-probe-sandbox.stderr
```

测试会短暂显示独立挂件与一秒休息引导，完成后退出。沙盒版只启用 App Sandbox 和音频输出权限，不申请辅助功能、截屏或通知授权。
除核对签名权限外，还实际尝试在容器外创建无敏感内容的临时文件：普通版允许且随即删除，沙盒版拒绝，以确认沙盒约束生效。

| 检查 | 普通版 | 沙盒版 |
|---|---|---|
| 文件边界、容器路径、容器内读写 | 3 项通过 | 3 项通过 |
| 设置、统计 | 2 项通过 | 2 项通过 |
| 倒计时、暂停、继续 | 3 项通过 | 3 项通过 |
| 三种样式 × 三种主题渲染 | 9 项通过 | 9 项通过 |
| 可视 / 输入窗口层级、对齐、拖动控制器几何 | 4 项通过 | 4 项通过 |
| 右键菜单结构 | 1 项通过 | 1 项通过 |
| 休息引导显示、自动结束、主动关闭 | 3 项通过 | 3 项通过 |
| 系统提示音文件解码 | 1 项通过 | 1 项通过 |
| 通知授权状态查询（不申请授权） | 1 项通过 | 1 项通过 |
| 合计 | **27 项通过** | **27 项通过** |

另外，当前 `/usr/bin/say` 调用在两版中均成功生成音频文件。本次没有发现它因沙盒而失败，不据此改写语音实现；这不等同于人工听音验收。

## 权限相关结果与证据边界

- 两版 `AXIsProcessTrusted()` 均为 false，事件 tap 创建均失败，`CGPreflightPostEventAccess()` 均为 false。普通版同样失败，因此不能把本次事件 tap 失败单独归因为 App Sandbox。
- 测试执行器自身的辅助功能、事件投递、屏幕捕获预检也均为 false，因此未执行真实桌面事件注入或截图。没有把控制器回调测试当成真实鼠标 / 防选框验收。
- 通知设置查询正常返回未决定授权（notDetermined）；没有请求权限，也没有据此宣称通知实际送达通过。
- 登录项状态查询未显示可注册；未注册这个测试应用，也未重启电脑。正式应用的 `SMAppService` 注册 / 取消 / 重启行为仍需独立验证。
- 多显示器、桌面空间切换、全屏应用、用户拒绝 / 允许通知后的实际送达、扬声器实际输出均未在本次测试中覆盖。

上述项目并非“全部通过沙盒”的证明。Apple 技术支持明确表示，沙盒应用不支持 Accessibility API：
[Apple DTS 说明](https://developer.apple.com/forums/thread/794253)。
Mac App Store 沙盒要求见 [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)。
因此不通过声明不存在的权限或绕开系统限制来追求测试全绿。

## GitHub 分发回归

运行 `bash Tools/run_checks.sh`：构建、53 项计时 / 设置检查、84 项菜单 / 事件路由检查、15 项外观 / 缩放渲染、发布构建与严格签名校验、5 项应用包检查。本次 157 项检查与构建 / 签名校验均通过。
这是可重复执行的自动化门槛；它不替代上述系统权限与桌面交互验收。

本次修正了构建脚本吞掉签名 / 校验失败的问题，避免无效应用包仍被报告为“构建完成”；同时明确默认构建仅包含当前机器架构。

项目现采用 MIT 许可证，GitHub 构建与发布配置见 [发布流程](releasing.md)。下载包区分 Apple Silicon 与 Intel，当前仍采用临时签名。
临时签名不等同于 Developer ID 签名或公证，不能据本机运行正常保证下载后可在其他 Mac 上直接打开。
