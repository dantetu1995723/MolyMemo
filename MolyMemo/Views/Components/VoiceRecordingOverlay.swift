import SwiftUI

private struct VoiceWaveformView: View {
    let audioPower: CGFloat
    var isCanceling: Bool = false
    
    private let barCount: Int = 40
    private let activeThreshold: CGFloat = 0.01
    private let barWidth: CGFloat = 3.0
    private let barSpacing: CGFloat = 3.0
    private let minHeight: CGFloat = 5
    private let maxContainerHeight: CGFloat = 54
    private let activeAmplitude: CGFloat = 45
    
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
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor.opacity(0.6))
                    .frame(width: barWidth, height: minHeight)
            }
        }
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
        
        let dynamic = CGFloat(mixed) * power * (activeAmplitude * CGFloat(centerWeight))
        return minHeight + dynamic
    }
}

private struct BlueArcView: View {
    let power: CGFloat
    let isCanceling: Bool
    let isExiting: Bool
    
    @State private var breathingAmount: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            
            ZStack {
                // 大圆弧：增加直径到 2.2 倍宽度，使其弧度更平缓
                Circle()
                    .fill(isCanceling ? Color(hex: "FF453A") : Color(hex: "007AFF"))
                    .frame(width: width * 2.2, height: width * 2.2)
                    // 将初始位置下移，增加 offset 使其初始高度降低
                    .offset(y: height * 0.8) 
                    .offset(y: -power * 70 - breathingAmount * 15) // 随音量和呼吸移动
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.7), value: power)
            }
            .frame(width: width, height: height)
            .opacity(isExiting ? 0 : 1)
            .offset(y: isExiting ? height * 0.4 : 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathingAmount = 1.0
            }
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
                        Text(isCanceling ? "松手发送，上滑取消" : "松手发送，上滑取消")
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
        }
        .onChange(of: audioPower) { _, newValue in
            // 进一步平滑音频输入，避免视觉抖动
            smoothedPower = smoothedPower * 0.6 + newValue * 0.4
        }
        .onChange(of: isExiting) { _, exiting in
            guard exiting else { return }
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
}
