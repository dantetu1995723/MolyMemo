import SwiftUI

// MARK: - 波纹团块形状
struct BlobShape: Shape {
    var time: Double  // 时间驱动相位变化
    var isAnimating: Bool // 是否播放动画
    
    // 使形状可动画化
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadiusX = rect.width / 2 * 0.85
        let baseRadiusY = rect.height / 2 * 0.85
        
        let pointsCount = 48
        let angleStep = .pi * 2 / Double(pointsCount)
        
        var points: [CGPoint] = []
        
        // 预计算幅度，减少循环内计算
        // 固定幅度：说话时 0.08，不说话时 0
        let distortionScale: CGFloat = isAnimating ? 0.08 : 0
        
        for i in 0..<pointsCount {
            let angle = Double(i) * angleStep
            
            // 固定的波形叠加
            // 使用多个不同频率的正弦波，确保波形看起来有机且不重复
            let wave1 = sin(angle * 3 + time * 1.5)
            let wave2 = cos(angle * 5 - time * 2.0)
            let wave3 = sin(angle * 7 + time * 2.5)
            
            let waveAmplitude = (wave1 * 0.4 + wave2 * 0.35 + wave3 * 0.25)
            
            let distortionX = waveAmplitude * baseRadiusX * distortionScale
            let distortionY = waveAmplitude * baseRadiusY * distortionScale
            
            let x = center.x + (baseRadiusX + distortionX) * cos(angle)
            let y = center.y + (baseRadiusY + distortionY) * sin(angle)
            points.append(CGPoint(x: x, y: y))
        }
        
        if let firstPoint = points.first {
            path.move(to: midPoint(points[pointsCount-1], firstPoint))
            
            for i in 0..<pointsCount {
                let p1 = points[i]
                let p2 = points[(i + 1) % pointsCount]
                let mid = midPoint(p1, p2)
                path.addQuadCurve(to: mid, control: p1)
            }
        }
        
        return path
    }
    
    private func midPoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }
}

struct VoiceRecordingOverlay: View {
    @Binding var isRecording: Bool
    @Binding var isCanceling: Bool
    var audioPower: CGFloat
    var transcript: String
    var namespace: Namespace.ID
    var startFrame: CGRect = CGRect(x: 0, y: UIScreen.main.bounds.height - 100, width: UIScreen.main.bounds.width - 32, height: 50)
    
    // 动画驱动
    @State private var time: Double = 0
    @State private var timer: Timer?
    @State private var showContent: Bool = false
    @State private var isExpanded: Bool = false
    @State private var showBlob: Bool = false
    
    var body: some View {
        ZStack {
            // 1. 背景层：深色遮罩
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { } // 拦截点击
            
            VStack(spacing: 0) {
                // 上方留白 - 让内容居中
                Spacer()
                
                // 转写气泡和提示文案组合 - 居中显示
                VStack(spacing: 16) {
                    // 2. 转写气泡 (模仿截图样式)
                    if showContent {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(transcript.isEmpty ? "正在聆听..." : transcript)
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "333333"))
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // 右下角声波条
                            HStack {
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(0..<8, id: \.self) { index in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color.blue)
                                            .frame(width: 3, height: waveBarHeight(for: index))
                                    }
                                }
                                .frame(height: 30, alignment: .bottom) // 固定高度，底部对齐，防止撑开气泡导致抖动
                            }
                        }
                        .padding(24)
                        .frame(minHeight: 120) // 给个最小高度，避免刚开始时高度突变
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white)
                        )
                        .padding(.horizontal, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // 3. 提示文案
                    if showContent {
                        Text(isCanceling ? "松开手指，取消发送" : "放开手指传送， 向上滑动取消")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .transition(.opacity)
                            .animation(.easeInOut, value: isCanceling)
                    }
                }
                
                // 下方留白 - 让内容居中
                Spacer()
            }
            .frame(maxWidth: .infinity) // 确保 VStack 宽度充满，以便居中
            
            // 4. 变形动画层 (Morphing Layer)
            // 已移至 HomeChatView 的 bottomInputArea 中统一处理，此处不再渲染
            // 避免图层叠加导致的双重圆问题
//            ZStack {
//                let safeWidth = startFrame.width > 0 ? startFrame.width : UIScreen.main.bounds.width - 32
//                let safeHeight = startFrame.height > 0 ? startFrame.height : 50
//                // 只有当语音转文字成功（transcript不为空）时才启动波动动画
//                let isSpeaking = !transcript.isEmpty && audioPower > 0.05
//                
//                // 外层光晕
//                if showBlob {
//                    BlobShape(time: time, isAnimating: isSpeaking)
//                        .fill(Color.blue.opacity(isSpeaking ? 0.2 : 0.08))
//                        .frame(width: 140, height: 140)
//                        .scaleEffect(isSpeaking ? 1.06 : 1.02)
//                        .transition(.opacity)
//                }
//                
//                // 主体团块
//                BlobShape(time: time, isAnimating: isSpeaking)
//                    .fill(isExpanded ? (isCanceling ? Color.red : Color(hex: "007AFF")) : Color.white)
//                    .frame(width: isExpanded ? 140 : safeWidth,
//                           height: isExpanded ? 140 : safeHeight)
//                    .shadow(color: isExpanded ? (isCanceling ? Color.red : Color.blue).opacity(0.4) : Color.clear, radius: 20, x: 0, y: 5)
//                    .overlay(
//                        // 模拟输入框的描边 (仅在未展开时)
//                        BlobShape(time: time, isAnimating: isSpeaking)
//                            .stroke(Color(hex: "E5E5EA"), lineWidth: isExpanded ? 0 : 0.5)
//                    )
//                    .overlay(
//                        // 图标 (展开后显示)
//                        Image(systemName: isCanceling ? "xmark" : "mic.fill")
//                            .font(.system(size: 32, weight: .bold))
//                            .foregroundColor(.white)
//                            .opacity(isExpanded ? 0.9 : 0)
//                            .animation(.easeIn(duration: 0.2).delay(0.1), value: isExpanded)
//                    )
//            }
//            // 使用 position 绝对定位来匹配输入框位置
//            // 声纹小圆的中心稍微向上偏移
//            .position(
//                x: UIScreen.main.bounds.midX, // 始终水平居中
//                y: startFrame.midY > 0 ? startFrame.midY - 30 : UIScreen.main.bounds.maxY - 110 // 向上移动30像素
//            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                showContent = true
            }
            
            // 立即开始波纹计算，确保过渡时已经是动态的
            startTimeLoop()
            
            // 启动变形动画
            // 稍微延迟一点点，确保视图已经渲染
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded = true
                }
                
                // 同时显示外层光晕
                withAnimation(.easeIn(duration: 0.3)) {
                    showBlob = true
                }
            }
        }
        .onDisappear {
            stopTimeLoop()
        }
    }
    
    // MARK: - 动画逻辑
    
    private func startTimeLoop() {
        // 使用更快的刷新率 (~60fps) 驱动相位变化
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            // 让时间持续增加，相位一直变化
            // 波动是否可见由 BlobShape 内部的 isAnimating 控制
            time += 0.05
        }
        // 确保 Timer 在滚动时也能运行
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    private func stopTimeLoop() {
        timer?.invalidate()
        timer = nil
    }
    
    // 声波条高度计算
    private func waveBarHeight(for index: Int) -> CGFloat {
        // 只有当语音转文字成功（transcript不为空）时才启动波动动画
        let isSpeaking = !transcript.isEmpty && audioPower > 0.05
        let baseHeight: CGFloat = 8
        
        // 没声音时保持静止高度
        guard isSpeaking else { return baseHeight }
        
        // 有声音时固定幅度规律波动
        // 让 time 持续变化产生动画
        let wave = sin(Double(index) * 0.8 + time * 6) * 0.5 + 0.5 // 0...1
        let height = baseHeight + 8 * CGFloat(wave)
        return max(6, min(height, 22))
    }
}

// MARK: - 预览
struct VoiceRecordingOverlay_Previews: PreviewProvider {
    @Namespace static var namespace
    
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            // 模拟背景图片
            
            VoiceRecordingOverlay(
                isRecording: .constant(true),
                isCanceling: .constant(false),
                audioPower: 0.6,
                transcript: "我上周说明天要和谁约饭来着？请你帮我查一下",
                namespace: namespace
            )
        }
    }
}
