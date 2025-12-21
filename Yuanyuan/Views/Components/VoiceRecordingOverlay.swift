import SwiftUI

private struct VoiceWaveformView: View {
    let audioPower: CGFloat
    var isCanceling: Bool = false
    
    private let barCount: Int = 20
    private let activeThreshold: CGFloat = 0.12
    private let barWidth: CGFloat = 1.5
    private let barSpacing: CGFloat = 1.5
    private let minHeight: CGFloat = 5
    private let maxContainerHeight: CGFloat = 24
    private let activeAmplitude: CGFloat = 12
    
    private var barColor: Color {
        isCanceling ? Color(hex: "FF453A") : Color(hex: "007AFF")
    }
    
    var body: some View {
        if audioPower > activeThreshold {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                activeBars(time: time)
            }
            .frame(height: maxContainerHeight)
        } else {
            idleBars()
                .frame(height: maxContainerHeight)
        }
    }
    
    private func idleBars() -> some View {
        return HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                // 静止时所有条等高
                RoundedRectangle(cornerRadius: 0.75)
                    .fill(barColor.opacity(0.7))
                    .frame(width: barWidth, height: minHeight)
            }
        }
    }
    
    private func activeBars(time: TimeInterval) -> some View {
        let mid = (Double(barCount) - 1) / 2
        return HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                let height = activeHeight(index: i, time: time, power: audioPower, mid: mid)
                RoundedRectangle(cornerRadius: 0.75)
                    .fill(barColor.opacity(0.8))
                    .frame(width: barWidth, height: height)
            }
        }
    }
    
    private func activeHeight(index i: Int, time: TimeInterval, power: CGFloat, mid: Double) -> CGFloat {
        // 中间更强，边缘更弱
        let dist = abs(Double(i) - mid) / mid
        let centerWeight = max(0.15, 1.0 - dist)
        
        // 多频正弦叠加，打散周期性（无序感更强）
        let n1 = sin(time * 13.7 + Double(i) * 0.9)
        let n2 = sin(time * 21.3 + Double(i) * 1.7)
        let n3 = sin(time * 29.1 + Double(i) * 0.35)
        let mixed = (n1 * 0.45 + n2 * 0.35 + n3 * 0.20 + 1.0) / 2.0 // 约 0..1
        
        let dynamic = CGFloat(max(0, mixed)) * power * (activeAmplitude * CGFloat(centerWeight))
        return minHeight + dynamic
    }
}

struct VoiceRecordingOverlay: View {
    @Binding var isRecording: Bool
    @Binding var isCanceling: Bool
    var audioPower: CGFloat
    var transcript: String
    var inputFrame: CGRect
    var toolboxFrame: CGRect
    
    @State private var isAnimatingEntry = true
    @State private var showMainUI = false
    @State private var backgroundOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // 1. 背景蒙版：独立图层，在录音开始时自然淡入
            Color.black.opacity(isCanceling ? 0.5 : backgroundOpacity)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.2), value: isCanceling)
            
            // 2. 粘滞流体球：负责全生命周期（融合、内缩、循环旋转）
            StickyBallAnimationView(
                inputFrame: inputFrame,
                toolboxFrame: toolboxFrame,
                isAnimating: .constant(true),
                isCanceling: isCanceling,
                audioPower: audioPower,
                onComplete: {
                    // 动画到达成球状态瞬间，显示文字框
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showMainUI = true
                    }
                }
            )
            
            // 3. 录音主界面层（文字框、音浪）
            if showMainUI {
                // 文字识别结果 + 提示文字
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 文字区域
                        Text(transcript.isEmpty ? "正在聆听..." : transcript)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.black.opacity(0.8))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                        
                        // 右下角音浪
                        HStack {
                            Spacer()
                            VoiceWaveformView(audioPower: audioPower, isCanceling: isCanceling)
                            .padding(.trailing, 24)
                            .padding(.bottom, 16)
                            .padding(.top, 8)
                        }
                    }
                    .frame(width: UIScreen.main.bounds.width - 60)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
                    )
                    
                    // 提示文字
                    Text(isCanceling ? "放开手指取消" : "放开手指传送，向上滑动取消")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isCanceling ? Color(hex: "FF453A") : .white.opacity(0.9))
                }
                .padding(.bottom, 120)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .onAppear {
            // 融合开始时启动背景淡入，0.4s 后达到预定透明度，此时正好完成粘滞融合
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundOpacity = 0.35
            }
        }
    }
}
