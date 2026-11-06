import AppKit
import SwiftUI

/// 原生 SwiftUI 渲染验收：九种外观、长时间、隐藏文字、暂停/休息与缩放。
/// 与应用源码一起编译（排除 App/EyeTimerApp.swift），不启动应用或读写用户设置。
struct ThemeSheet: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(WidgetStyle.allCases, id: \.self) { style in
                    Text(style.title).frame(width: 320)
                }
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            ForEach(WidgetTheme.allCases, id: \.self) { theme in
                VStack(alignment: .leading, spacing: 0) {
                    Text(theme.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 0) {
                        ForEach(WidgetStyle.allCases, id: \.self) { style in
                            WidgetFace(style: style, theme: theme)
                                .frame(width: 320, height: 238)
                        }
                    }
                }
            }
        }
        .padding(28)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.17, blue: 0.24),
                                            Color(red: 0.05, green: 0.09, blue: 0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

@MainActor
func render<V: View>(_ view: V) -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage else { fatalError("原生外观渲染失败") }
    return NSBitmapImageRep(cgImage: image)
}

@MainActor
func run() throws {
    let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/widget-previews")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sheet = render(ThemeSheet())
    try sheet.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("themes.png"))
    var checks = 0
    for style in WidgetStyle.allCases {
        for theme in WidgetTheme.allCases {
            let image = render(WidgetFace(style: style, theme: theme))
            precondition(image.pixelsWide == Int(style.intrinsicSize.width * 2))
            precondition(image.pixelsHigh == Int(style.intrinsicSize.height * 2))
            checks += 1
        }
        for scale in [0.6, 1.8] {
            let size = style.intrinsicSize
            // 与 WidgetRootView 使用相同的缩放及外框顺序。
            let image = render(WidgetFace(style: style, theme: .sand, time: "120:00",
                                          remaining: 0, status: "已暂停", symbol: "pause.fill",
                                          showsDetails: false)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale))
            precondition(abs(image.pixelsWide - Int(size.width * scale * 2)) <= 1)
            precondition(abs(image.pixelsHigh - Int(size.height * scale * 2)) <= 1)
            checks += 1
        }
    }
    let states = VStack {
        ForEach(WidgetStyle.allCases, id: \.self) { style in
            HStack {
                WidgetFace(style: style, theme: .mist, time: "120:00", remaining: 1,
                           status: "未开始", symbol: "play.fill")
                WidgetFace(style: style, theme: .sand, time: "120:00", remaining: 0.4,
                           status: "已暂停", symbol: "pause.fill", showsDetails: false)
                WidgetFace(style: style, theme: .forest, time: "00:20", remaining: 0,
                           status: "远眺放松", symbol: "sparkles")
            }
        }
    }.padding(24).background(Color.gray.opacity(0.12))
    let image = render(states)
    try image.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("states.png"))
    print("原生渲染通过：\(checks) 项主题与缩放检查；输出 \(directory.path)")
}

try MainActor.assumeIsolated { try run() }
