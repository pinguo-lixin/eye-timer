import SwiftUI

/// 休息引导视图：柔和的全屏遮罩 + 呼吸动画 + 注视引导。
struct BreakOverlayView: View {
    @EnvironmentObject private var overlay: BreakOverlayController
    @State private var breathe = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // 半透明遮罩：不刺眼，保留底层的隐约轮廓
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            // 柔和的青绿色光晕，模拟远眺时的自然色
            RadialGradient(
                colors: [
                    Color(red: 0.30, green: 0.72, blue: 0.62).opacity(0.30),
                    Color(red: 0.30, green: 0.72, blue: 0.62).opacity(0.0)
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()
            .scaleEffect(breathe ? 1.12 : 0.9)
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: breathe)

            VStack(spacing: 34) {
                // 呼吸圆 —— 跟着它呼吸，眼睛自然放松
                ZStack {
                    Circle()
                        .stroke(
                            Color(red: 0.45, green: 0.85, blue: 0.72).opacity(0.55),
                            lineWidth: 2
                        )
                        .frame(width: 132, height: 132)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.92, blue: 0.80).opacity(0.30),
                                    Color(red: 0.55, green: 0.92, blue: 0.80).opacity(0.04)
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 66
                            )
                        )
                        .frame(width: 132, height: 132)
                        .scaleEffect(breathe ? 1.0 : 0.82)
                        .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: breathe)

                    VStack(spacing: 1) {
                        Text("\(overlay.remaining)")
                            .font(.system(size: 42, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("秒")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }

                // 提示文案
                VStack(spacing: 12) {
                    Text(overlay.phaseTitle)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("看向 \(overlay.gazeDistance) 米外的远处")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.82))

                    Text("放松眉眼，让瞳孔自然舒展 · 慢慢眨眼")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }

                // 倒计时进度条
                HStack(spacing: 3) {
                    ForEach(0..<20, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(activeDotOpacity(i)))
                            .frame(width: 9, height: 4)
                    }
                }
                .padding(.top, 4)

                // 操作区
                HStack(spacing: 14) {
                    Button {
                        overlay.hide()
                    } label: {
                        Text("跳过休息")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color.white.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        overlay.hide()
                    } label: {
                        Text("立即回到工作")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(60)
        }
        .onAppear {
            breathe = true
            pulse = true
        }
    }

    /// 进度点透明度：随剩余时间递减
    private func activeDotOpacity(_ index: Int) -> Double {
        let total = 20
        let fraction = Double(overlay.remaining) / Double(max(1, overlay.totalDuration))
        let filled = Int(fraction * Double(total))
        return index < filled ? 0.75 : 0.18
    }
}
