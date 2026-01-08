import SwiftUI

private struct VoiceWaveformView: View {
    let audioPower: CGFloat
    var isCanceling: Bool = false
    
    private let barCount: Int = 40
    // 更小声也进入“动态音浪”，视觉更灵敏
    private let barWidth: CGFloat = 3.0
    private let barSpacing: CGFloat = 3.0
    private let minHeight: CGFloat = 5
    private let maxContainerHeight: CGFloat = 80
    private let activeAmplitude: CGFloat = 75
    
    private var barColor: Color {
        isCanceling ? Color(hex: "FF453A") : Color(hex: "007AFF")
    }
    
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            activeBars(time: time)
        }
        .frame(height: maxContainerHeight)
    }
    
    private func activeBars(time: TimeInterval) -> some View {
        let mid = (Double(barCount) - 1) / 2
        return HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                let height = activeHeight(index: i, time: time, power: audioPower, mid: mid)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor.opacity(0.8))
                    .frame(width: barWidth, height: height)
            }
        }
    }
    
    private func activeHeight(index i: Int, time: TimeInterval, power: CGFloat, mid: Double) -> CGFloat {
        let dist = abs(Double(i) - mid) / mid
        let centerWeight = max(0.2, 1.0 - pow(dist, 1.2))
        
        let n1 = sin(time * 10.0 + Double(i) * 0.7)
        let n2 = sin(time * 15.0 + Double(i) * 1.3)
        let mixed = (n1 * 0.5 + n2 * 0.5 + 1.0) / 2.0
        
        // 叠加基础呼吸电平，确保静音时也有持续的动态感
        let breathingBase = 0.05 + 0.03 * CGFloat(sin(time * 2.5))
        let effectivePower = max(power, breathingBase)
        
        let dynamic = CGFloat(mixed) * effectivePower * (activeAmplitude * CGFloat(centerWeight))
        return minHeight + dynamic
    }
}

private struct BlueArcView: View {
    let power: CGFloat
    let isCanceling: Bool
    let isExiting: Bool
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                
                // 基础呼吸量：正弦波驱动，范围在 0 ~ 1 之间
                // 提高频率（2.0 -> 3.5）以跟上音浪的节奏
                let breathingBase = (sin(time * 3.5) + 1.0) / 2.0
                // 减小幅度（25 -> 12），使静态起伏更细腻
                let breathingOffset = breathingBase * 12
                // 音量反馈高度：随音量跳动（降低系数，避免说话时抬得过高）
                let powerOffset = power * 90
                
                ZStack {
                    Circle()
                        .fill(isCanceling ? Color(hex: "FF453A") : Color(hex: "007AFF"))
                        .frame(width: width * 2.2, height: width * 2.2)
                        // 抬高初始高度（0.82 -> 0.76）
                        .offset(y: height * 0.76) 
                        .offset(y: -powerOffset - breathingOffset)
                }
                .frame(width: width, height: height)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.7), value: power)
            }
            .opacity(isExiting ? 0 : 1)
            .offset(y: isExiting ? height * 0.4 : 0)
        }
    }
}

struct VoiceRecordingOverlay: View {
    @Binding var isRecording: Bool
    @Binding var isCanceling: Bool
    var isExiting: Bool = false
    var onExitComplete: (() -> Void)? = nil
    var audioPower: CGFloat
    var transcript: String
    var inputFrame: CGRect
    var toolboxFrame: CGRect
    
    @State private var showMainUI = false
    @State private var smoothedPower: CGFloat = 0
    @State private var backgroundOpacity: Double = 0
    @State private var didTriggerExit = false
    
    var body: some View {
        ZStack(alignment: .center) {
            // 1. 背景蒙版
            Color.black.opacity(backgroundOpacity)
                .ignoresSafeArea()
            
            // 2. 底部蓝色弧
            BlueArcView(power: smoothedPower, isCanceling: isCanceling, isExiting: isExiting)
            
            // 3. 录音主界面
            if showMainUI {
                VStack(spacing: 0) {
                    VStack(alignment: .center, spacing: 24) {
                        // 音浪
                        VoiceWaveformView(audioPower: smoothedPower, isCanceling: isCanceling)
                        
                        // 提示文字
                        Text(isCanceling ? "松手发送，上滑取消" : (transcript.isEmpty ? "松手发送，上滑取消" : transcript))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(isCanceling ? Color(hex: "FF453A") : Color(hex: "333333").opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(width: 279, alignment: .center)
                    .background(.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    
                    // 占位，让卡片稍微靠上一点
                    Spacer()
                        .frame(height: ScreenMetrics.height * 0.12)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.25)) {
                backgroundOpacity = 0.35
                showMainUI = true
            }
            // 兜底：如果 overlay 被“重新插入”时已经处于退出态，onChange 可能不会触发
            if isExiting {
                triggerExitIfNeeded()
            }
        }
        .onChange(of: audioPower) { _, newValue in
            // 进一步平滑音频输入，避免视觉抖动
            smoothedPower = smoothedPower * 0.6 + newValue * 0.4
        }
        .onChange(of: isExiting) { _, exiting in
            guard exiting else { return }
            triggerExitIfNeeded()
        }
    }

    private func triggerExitIfNeeded() {
        guard !didTriggerExit else { return }
        didTriggerExit = true
        // 提速：缩短退场动画时长，增强敏捷感
        withAnimation(.easeInOut(duration: 0.15)) {
            showMainUI = false
            backgroundOpacity = 0
        }
        // 延迟触发完成回调，匹配动画时长
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            onExitComplete?()
        }
    }
}
