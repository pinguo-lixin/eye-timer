import SwiftUI

/// 桌面与设置预览共用同一份外观；拖拽仍完全由窗口控制器处理。
struct WidgetRootView: View {
    @EnvironmentObject private var engine: TimerEngine
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appearance: WidgetAppearanceModel

    var body: some View {
        WidgetFace(style: settings.widgetStyle, theme: settings.widgetTheme,
                   time: engine.remainingText, remaining: 1 - engine.progress,
                   status: status, symbol: symbol,
                   showsDetails: settings.showWidgetText,
                   cycle: engine.completedFocusCycles + 1)
            .scaleEffect(settings.widgetScale)
            .frame(width: settings.widgetStyle.intrinsicSize.width * settings.widgetScale,
                   height: settings.widgetStyle.intrinsicSize.height * settings.widgetScale)
            .opacity(appearance.effectiveOpacity(base: settings.widgetOpacity,
                                                 hoverHighlight: settings.widgetHoverHighlight))
            .animation(.easeOut(duration: 0.16), value: appearance.isHovering)
            // Halo 不显示状态文字，仍为辅助技术提供完整语义。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(settings.widgetStyle.title)，\(status)，剩余 \(engine.remainingText)")
    }

    private var status: String {
        switch engine.state {
        case .idle: return "未开始"
        case .paused: return "已暂停"
        case .running, .resting: return engine.phase.title
        }
    }

    private var symbol: String {
        switch engine.state {
        case .idle: return "play.fill"
        case .paused: return "pause.fill"
        case .running, .resting: return engine.phase.symbolName
        }
    }
}

/// 显式配色保证深浅壁纸下文字都有稳定对比度，而不跟随系统文字色反转。
struct WidgetPalette {
    let accent: Color
    let secondaryAccent: Color
    let surface: Color
    let surfaceBottom: Color
    let ink: Color
    let muted: Color
    let paper: Color
    let paperBottom: Color
    let paperInk: Color
    let paperMuted: Color
    let paperAccent: Color

    init(theme: WidgetTheme) {
        switch theme {
        case .mist:
            accent = Color(widgetHex: 0x83D7FF)
            secondaryAccent = Color(widgetHex: 0xABAAEF)
            surface = Color(widgetHex: 0x26374F)
            surfaceBottom = Color(widgetHex: 0x111E30)
            ink = Color(widgetHex: 0xEDF4FF)
            muted = Color(widgetHex: 0xAFBFD2)
            paper = Color(widgetHex: 0xF2F7FA)
            paperBottom = Color(widgetHex: 0xD3E2EB)
            paperInk = Color(widgetHex: 0x213849)
            paperMuted = Color(widgetHex: 0x526F81)
            paperAccent = Color(widgetHex: 0x4A90B0)
        case .sand:
            accent = Color(widgetHex: 0xFFC77B)
            secondaryAccent = Color(widgetHex: 0xEEA28B)
            surface = Color(widgetHex: 0x40303A)
            surfaceBottom = Color(widgetHex: 0x231C26)
            ink = Color(widgetHex: 0xFFF5DF)
            muted = Color(widgetHex: 0xD0BAA2)
            paper = Color(widgetHex: 0xF7EBD6)
            paperBottom = Color(widgetHex: 0xE8D8BC)
            paperInk = Color(widgetHex: 0x493624)
            paperMuted = Color(widgetHex: 0x806647)
            paperAccent = Color(widgetHex: 0xAC7540)
        case .forest:
            accent = Color(widgetHex: 0x7CE0AD)
            secondaryAccent = Color(widgetHex: 0xBEDD8F)
            surface = Color(widgetHex: 0x29463D)
            surfaceBottom = Color(widgetHex: 0x132B26)
            ink = Color(widgetHex: 0xE9FFF3)
            muted = Color(widgetHex: 0xACCABA)
            paper = Color(widgetHex: 0xE7F1E8)
            paperBottom = Color(widgetHex: 0xC9DDCF)
            paperInk = Color(widgetHex: 0x233B30)
            paperMuted = Color(widgetHex: 0x577963)
            paperAccent = Color(widgetHex: 0x528B69)
        }
    }
}

private extension Color {
    init(widgetHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

/// 无状态外观组件，预览与自动化渲染无需启动计时器或申请权限。
struct WidgetFace: View {
    let style: WidgetStyle
    let theme: WidgetTheme
    var time = "13:36"
    var remaining: Double = 0.68
    var status = "专注用眼"
    var symbol = "eye"
    var showsDetails = true
    var cycle = 1

    private var palette: WidgetPalette { WidgetPalette(theme: theme) }
    private var fraction: Double { min(1, max(0, remaining)) }
    private var percentage: String { "\(Int((fraction * 100).rounded()))%" }

    var body: some View {
        Group {
            switch style {
            case .halo: halo
            case .monolith: monolith
            case .paper: paper
            }
        }
        .frame(width: style.intrinsicSize.width, height: style.intrinsicSize.height)
    }

    private var halo: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [palette.surface, palette.surfaceBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.15), .clear],
                                     center: .topLeading, startRadius: 0, endRadius: 135))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            WidgetProgressRing(fraction: fraction, palette: palette, width: 5)
                .padding(11)
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
                Text(time)
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.8)
                    .foregroundStyle(palette.ink)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
            .padding(.horizontal, 21)
        }
        .frame(width: 140, height: 140)
        .shadow(color: palette.accent.opacity(0.12), radius: 9)
        .shadow(color: .black.opacity(0.24), radius: 6, y: 4)
        // 不显示标题、阶段、轮次、总时长；阶段仅用符号表达。
    }

    private var monolith: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 42, height: 42)
                .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(time)
                    .font(.system(size: 29, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.8)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .foregroundStyle(palette.ink)
                if showsDetails {
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                WidgetProgressRing(fraction: fraction, palette: palette, width: 4)
                Text(percentage)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
            }
            .frame(width: 48, height: 48)
        }
        .padding(.horizontal, 16)
        .frame(width: 272, height: 84)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [palette.surface, palette.surfaceBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.24), radius: 7, y: 5)
        }
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if showsDetails {
                    Text("护眼提醒")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.paperMuted)
                }
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.paper)
                    .frame(width: 26, height: 26)
                    .background(palette.paperAccent, in: RoundedRectangle(cornerRadius: 9))
            }
            Spacer(minLength: 10)
            Text(time)
                .font(.system(size: 36, weight: .light, design: .rounded))
                .tracking(-1.3)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(palette.paperInk)
            if showsDetails {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.paperMuted)
                    .padding(.top, 4)
            }
            Spacer(minLength: 10)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.paperAccent.opacity(0.14))
                    Capsule().fill(palette.paperAccent)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
            if showsDetails {
                HStack {
                    Text("第 \(cycle) 轮")
                    Spacer()
                    Text("剩余 \(percentage)").monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.paperMuted)
                .padding(.top, 10)
            }
        }
        .padding(18)
        .frame(width: 204, height: 180)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [palette.paper, palette.paperBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 0.8)
                }
                .shadow(color: palette.surface.opacity(0.18), radius: 0, x: 5, y: 6)
                .shadow(color: .black.opacity(0.19), radius: 6, y: 5)
        }
        .rotationEffect(.degrees(-2))
    }
}

private struct WidgetProgressRing: View {
    let fraction: Double
    let palette: WidgetPalette
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(palette.ink.opacity(0.10), lineWidth: width)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(AngularGradient(colors: [palette.accent.opacity(0.6), palette.accent],
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
