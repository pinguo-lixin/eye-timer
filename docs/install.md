# 安装与常见问题

## 选择版本

在 [GitHub Releases](https://github.com/pinguo-lixin/eye-timer/releases/latest) 下载最新版本。
苹果菜单 →「关于本机」中，显示 Apple M 系列芯片的选择 `arm64`；显示 Intel 处理器的选择 `x86_64`。
需要 macOS 13 或更高版本。

## 安装

1. 打开下载的 DMG，把 EyeTimer.app 拖入 Applications（应用程序）。
2. 推出安装磁盘，从「应用程序」打开 EyeTimer。
3. 点击菜单栏的眼睛图标，选择「开始」。

ZIP 是备用下载方式：解压后把 EyeTimer.app 拖入「应用程序」，再打开。
更新时先退出正在运行的 EyeTimer，用新版替换「应用程序」中的旧版；设置和统计保存在本机，正常替换应用不会删除它们。

## 首次打开被阻止

当前下载包尚未使用 Apple Developer ID 签名，也未经过 Apple 公证，macOS 可能提示无法验证开发者或无法检查恶意软件。
请先确认安装包来自本仓库的 Releases。如果确定信任该来源，可在尝试打开后进入「系统设置 → 隐私与安全性」，查看「仍要打开」选项，并按系统提示确认。

不需要关闭整个系统的安全检查。如果提示应用已损坏或会损坏电脑，请停止使用该下载包并反馈提示内容。
详细说明见 [Apple：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)。

## 没有出现通知

在「系统设置 → 通知」中允许 EyeTimer 的通知，并检查应用「设置 → 提醒方式」中的开关。
专注模式或系统通知设置也可能影响通知显示。

## 挂件拖动与权限

挂件支持直接拖动，并提供兼容输入方式。如果需要启用辅助功能权限，可在应用设置中的引导入口进入系统设置，找到 EyeTimer 并授权。
授权变化后若未生效，退出并重新打开应用。

## 找不到主窗口

EyeTimer 常驻菜单栏，不显示 Dock 图标。点击菜单栏的眼睛图标打开设置、控制计时或退出应用。

## 卸载

从菜单栏退出 EyeTimer，再将「应用程序」中的 EyeTimer.app 移到废纸篓。

如果问题仍然存在，请在 [Issues](https://github.com/pinguo-lixin/eye-timer/issues) 提供 macOS 版本、Mac 芯片型号、EyeTimer 版本及复现步骤。
