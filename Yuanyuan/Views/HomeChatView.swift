import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import UIKit

// MARK: - 布局常量
private let agentAvatarSize: CGFloat = 30

struct HomeChatView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Binding var showModuleContainer: Bool
    
    // UI State
    @State private var inputText: String = ""
    @State private var showContent: Bool = false
    @FocusState private var isInputFocused: Bool
    @State private var contentHeight: CGFloat = 0
    
    // 录音动画状态
    enum RecordingAnimationState {
        case idle
        case morphing    // 融合渐变阶段：输入框变长 + 变浅蓝 + 文字淡出
        case shrinking   // 收缩阶段：变成深蓝圆形
    }
    @State private var recordingState: RecordingAnimationState = .idle
    @State private var inputBoxSize: CGSize = .zero   // 输入框尺寸（不含右边按钮）
    @State private var fullAreaSize: CGSize = .zero   // 整个底部区域尺寸（含按钮）
    
    // 动画驱动
    @State private var blobTime: Double = 0
    @State private var blobTimer: Timer?
    @State private var showBlob: Bool = false
    @State private var rotationAngle: Double = 0  // 小内切圆旋转角度
    @State private var colorSpread: CGFloat = 0  // 颜色扩散比例 (0.0 -> 1.5)
    
    // 录音文字输出状态
    @State private var isOutputtingText: Bool = false
    @State private var textOutputTimer: Timer?
    
    // 语音输入状态
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isCanceling: Bool = false
    @State private var audioPower: CGFloat = 0.0
    @State private var recordingTranscript: String = ""
    @Namespace private var animationNamespace
    @State private var dragOffset: CGFloat = 0
    @State private var inputFrame: CGRect = .zero
    @State private var pressStartTime: Date?
    @State private var hasStartedRecording: Bool = false
    @State private var longPressTimer: Timer?
    
    // 主题色
    private let primaryGray = Color(hex: "333333")
    private let secondaryGray = Color(hex: "666666")
    private let backgroundGray = Color(hex: "F7F8FA")
    private let bubbleWhite = Color.white
    private let userBubbleColor = Color(hex: "222222") // 深黑色用户气泡
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 背景
                backgroundView
                
                // 聊天内容层
                VStack(spacing: 0) {
                    // 顶部导航
                    headerView
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    
                    // 提醒卡片
                    reminderCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    // 聊天内容区域
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 24) {
                                // 顶部垫高（缩小与通知栏的间距）
                                Color.clear.frame(height: 4)
                                
                                // 聊天内容
                                normalChatContent
                                
                                // 底部垫高 (确保最后一条消息不被输入框遮挡)
                                Color.clear.frame(height: max(20, fullAreaSize.height + 20))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively) // 滑动时渐进收回键盘
                        .onTapGesture {
                            // 点击空白处收回键盘
                            isInputFocused = false
                        }
                        .onChange(of: appState.chatMessages.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                
                // 语音录制全屏层 (在内容层之上，但在输入框之下)
                if speechRecognizer.isRecording {
                    VoiceRecordingOverlay(
                        isRecording: Binding(
                            get: { speechRecognizer.isRecording },
                            set: { _ in }
                        ),
                        isCanceling: $isCanceling,
                        audioPower: audioPower,
                        transcript: recordingTranscript,
                        namespace: animationNamespace,
                        startFrame: inputFrame
                    )
                    .onChange(of: speechRecognizer.audioLevel) { _, newValue in
                        // 直接赋值，不加动画延迟，最大化响应速度
                        self.audioPower = CGFloat(newValue)
                    }
                    .zIndex(100)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    ))
                    }
                    
                // 底部输入区域 (浮动在最上层)
                bottomInputArea
                    .zIndex(101) // 确保在录音层之上
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
            
            // 请求语音识别权限
            speechRecognizer.requestAuthorization()
        }
        .onChange(of: recordingTranscript) { oldValue, newValue in
            // 当识别到文字变化时
            if !newValue.isEmpty {
                // 如果文字不为空，且有新内容（通常newValue会比oldValue长，或者是全新的内容）
                // 激活波纹状态 - 使用与形状切换一致的动画
                if !isOutputtingText {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isOutputtingText = true
                    }
                }
                
                // 重置倒计时（语音转文字结束 1 秒后退回绕圈状态）
                textOutputTimer?.invalidate()
                textOutputTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                    // 1 秒后如果没有新文字，恢复到初始状态 - 使用与形状切换一致的动画
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isOutputtingText = false
                    }
                }
            } else {
                // 如果文字被清空（比如重新开始录音），平滑重置
                if isOutputtingText {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isOutputtingText = false
                    }
                }
                textOutputTimer?.invalidate()
            }
        }
    }
    
    // MARK: - 语音输入逻辑
    
    private func startRecording() {
        // 重置状态
        recordingTranscript = ""
        isCanceling = false
        audioPower = 0.0
        
        // 启动动画
        runRecordingAnimation()
        
        // 开始真实的语音识别
        speechRecognizer.startRecording { text in
            recordingTranscript = text
        }
    }
    
    private func endRecording() {
        // 停止语音识别
        speechRecognizer.stopRecording()
        
        // 重置动画
        resetRecordingAnimation()
        
        // 平滑过渡动画
        withAnimation(.easeOut(duration: 0.2)) {
            audioPower = 0.0
        }
        
        // 处理录音结果
        if !isCanceling {
            let textToSend = recordingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !textToSend.isEmpty {
                // 发送成功反馈
                HapticFeedback.success()
                sendChatMessage(text: textToSend)
            }
        } else {
            // 取消反馈
            HapticFeedback.light()
        }
        
        // 重置状态
        isCanceling = false
        recordingTranscript = ""
        dragOffset = 0
    }
    
    private var voiceInputGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                // 首次按下，启动长按计时器
                if pressStartTime == nil {
                    pressStartTime = Date()
                    isCanceling = false
                    
                    // 启动计时器：如果 200ms 后还在按着，则视为长按启动录音
                    longPressTimer?.invalidate()
                    longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                        Task { @MainActor in
                            if self.pressStartTime != nil { // 确保还没松手
                                self.hasStartedRecording = true
                                HapticFeedback.medium()
                                self.startRecording()
                            }
                        }
                    }
                }
                
                // 如果已经在录音，处理拖动取消逻辑
                if hasStartedRecording && speechRecognizer.isRecording {
                    let translation = value.translation.height
                    let previousCanceling = isCanceling
                    dragOffset = translation
                    
                    // 向上滑动超过阈值进入取消状态
                    let shouldCancel = translation < -80
                    
                    withAnimation(.easeOut(duration: 0.15)) {
                        isCanceling = shouldCancel
                    }
                    
                    // 进入/退出取消状态时触发反馈
                    if shouldCancel != previousCanceling {
                        HapticFeedback.selection()
                    }
                }
            }
            .onEnded { _ in
                // 清理计时器
                longPressTimer?.invalidate()
                longPressTimer = nil
                
                let wasRecording = hasStartedRecording
                
                // 重置按下状态
                pressStartTime = nil
                hasStartedRecording = false
                
                if wasRecording {
                    // 如果已经触发了录音，则结束录音
                    endRecording()
                } else {
                    // 如果还没触发录音（即短按），则视为点击，聚焦输入框
                    HapticFeedback.light()
                    isInputFocused = true
                }
            }
    }
    
    private func runRecordingAnimation() {
        // 1. 融合渐变：输入框背景变宽、变色，同时文字开始淡出
        // 加快整体速度：0.6s -> 0.3s
        withAnimation(.easeInOut(duration: 0.3)) {
            recordingState = .morphing
            colorSpread = 1.2 // 触发颜色扩散动画
        }
        
        // 2. 缩圆：0.3s后从全宽收缩成圆形，颜色变深
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.speechRecognizer.isRecording {
                // 收缩阶段也加快：0.5s -> 0.3s
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.recordingState = .shrinking
                }
                // 启动波纹动画
                self.startBlobAnimation()
                withAnimation(.easeIn(duration: 0.2)) {
                    self.showBlob = true
                }
            }
        }
    }
    
    private func resetRecordingAnimation() {
        stopBlobAnimation()
        
        // 1. 从圆变回长条 (Reverse of shrinking)
        // 对应 runRecordingAnimation 第2步的时长 0.3s
        withAnimation(.easeInOut(duration: 0.3)) {
            recordingState = .morphing
            showBlob = false
        }
        
        // 2. 恢复初始状态 (Reverse of morphing)
        // 对应 runRecordingAnimation 第1步的时长 0.3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 确保没有开始新的录音
            if !self.speechRecognizer.isRecording && self.recordingState == .morphing {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.recordingState = .idle
                    self.colorSpread = 0 // 颜色收回
                }
            }
        }
    }
    
    private func startBlobAnimation() {
        stopBlobAnimation()
        // 使用更快的刷新率 (~60fps) 驱动相位变化
        blobTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            blobTime += 0.05
            // 小内切圆旋转动画（每帧旋转约1度，约6秒转一圈）
            rotationAngle += 1.0
            if rotationAngle >= 360 {
                rotationAngle = 0
            }
        }
    }
    
    private func stopBlobAnimation() {
        blobTimer?.invalidate()
        blobTimer = nil
        blobTime = 0
        rotationAngle = 0
    }
    
    // MARK: - Components
    
    private var backgroundView: some View {
        backgroundGray
            .ignoresSafeArea()
    }
    
    // MARK: - 顶部导航
    private var headerView: some View {
        HStack {
            // 左侧菜单
            Button(action: {
                HapticFeedback.light()
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(primaryGray)
            }
            
            Spacer()
            
            // 中间标题
            Text("圆圆")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(primaryGray)
            
            Spacer()
            
            // 右侧搜索
            Button(action: {
                HapticFeedback.light()
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(primaryGray)
            }
        }
        .opacity(showContent ? 1 : 0)
    }
    
    // MARK: - 提醒卡片
    private var reminderCard: some View {
        HStack(spacing: 10) {
            // 日历图标
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundColor(secondaryGray)
            
            // 时间
            Text("14:00")
                .font(.system(size: 15))
                .foregroundColor(secondaryGray)
            
            // 内容
            Text("和张总开会")
                .font(.system(size: 15))
                .foregroundColor(primaryGray)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - 聊天内容
    private var normalChatContent: some View {
        Group {
            // 消息列表
            ForEach(appState.chatMessages) { message in
                if message.role == .user {
                    UserBubble(text: message.content)
                        .id(message.id)
                } else {
                    AIBubble(text: message.content.isEmpty && appState.isAgentTyping ? "正在思考..." : message.content, messageId: message.id)
                        .id(message.id)
                }
            }
            
            // 锚点
            Color.clear
                .frame(height: 1)
                .id("bottomID")
        }
    }
    
    // MARK: - 底部输入区域
    private var bottomInputArea: some View {
        GeometryReader { geometry in
            let horizontalMargin: CGFloat = 20 // 与顶部导航栏对齐
            let bottomMargin: CGFloat = 4 // 减小底部边距
            let areaWidth = geometry.size.width - horizontalMargin * 2 // 减去左右边距后的可用宽度
            let inputHeight: CGFloat = 48 // 输入框高度
            let buttonSize: CGFloat = 48 // 按钮尺寸，与输入框高度一致
            let spacing: CGFloat = 10
            
            // 计算输入框宽度: 可用宽度 - 按钮宽 - 按钮间距
            let inputContainerWidth = areaWidth - buttonSize - spacing
            
            // 是否在说话（用于波纹动画和状态判断）
            let isSpeaking = !recordingTranscript.isEmpty && audioPower > 0.05
            
            // 统一活跃状态：只要在说话或正在转文字，都视为活跃态，使用统一的大圆动画
            let isActiveBlob = isSpeaking || isOutputtingText
            
            let baseCircleSize: CGFloat = 80  // 基础圆形尺寸
            // 活跃状态下圆变大
            let circleSize: CGFloat = isActiveBlob ? baseCircleSize * 1.15 : baseCircleSize
            // 容器高度：录音时需要更高的空间避免上下被裁剪
            let baseContainerHeight: CGFloat = 64
            // 球本身高度为 circleSize，这里上下各预留 20pt，让动态球完全不贴边
            let recordingContainerHeight: CGFloat = circleSize + 40
            let containerHeight: CGFloat = recordingState == .shrinking ? recordingContainerHeight : baseContainerHeight
            
            // 计算当前状态下的目标 Frame
            var targetWidth: CGFloat {
                switch recordingState {
                case .idle: return inputContainerWidth
                case .morphing: return inputContainerWidth // 保持输入框宽度不变，使用中间连接体来融合
                case .shrinking: return circleSize
                }
            }
            
            var targetHeight: CGFloat {
                switch recordingState {
                case .idle: return inputHeight
                case .morphing: return inputHeight
                case .shrinking: return circleSize
                }
            }
            
            var targetCornerRadius: CGFloat {
                switch recordingState {
                case .idle: return 15
                case .morphing: return 15
                case .shrinking: return circleSize / 2
                }
            }
            
            // 计算位置偏移（相对于可用区域中心）
            // 1. 输入框中心的偏移
            let inputIdleOffset = inputContainerWidth / 2 - areaWidth / 2
            
            // 2. 按钮中心的偏移
            let buttonIdleOffset = (areaWidth - buttonSize / 2) - areaWidth / 2
            
            // 当前输入框的偏移
            var currentInputOffset: CGFloat {
                if recordingState == .idle || recordingState == .morphing {
                    return inputIdleOffset
                }
                return 0 // Shrinking 时居中
            }
            
            // 颜色逻辑
            // 移除渐变色，使用纯色过渡
            let deepBlue = Color.blue
            let activeColor: Color = isCanceling ? Color.red : deepBlue
            
            // 小内切圆参数
            let mainCircleRadius = circleSize / 2  // 主圆半径
            let smallCircleRadius: CGFloat = mainCircleRadius * 0.7  // 小圆半径为主圆半径的70%
            let orbitRadius = mainCircleRadius - smallCircleRadius  // 轨道半径：让小圆紧贴主圆内部
            
            VStack {
                Spacer(minLength: 0)
                
                ZStack {
                    // 1. 粘滞融合背景 (Sticky/Gooey Background)
                    ZStack {
                        // 统一的颜色层 (The Ink) - 使用遮罩扩散技术实现 "由蓝到白色渐变"
                        ZStack {
                            Color.white // 默认底色是白色
                            
                            // 蓝色扩散层：通过 colorSpread 变量控制宽度，从中心向两边扩散
                            activeColor
                                .mask(
                                    GeometryReader { proxy in
                                        // 使用胶囊体作为扩散遮罩
                                        Capsule()
                                            .frame(width: max(0, proxy.size.width * colorSpread))
                                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                                            .blur(radius: 20) // 模糊边缘，形成渐变效果
                                    }
                                )
                        }
                        .mask {
                            // 遮罩层：生成粘滞效果的形状 (The Mask)
                            // 原理：绘制白色形状 -> 模糊 -> 提高对比度阈值 -> 亮度转Alpha
                            ZStack {
                                // 底色必须是黑色（Alpha 0）
                                Color.black
                                
                                // 白色形状组
                                Group {
                                    // 形状1: 输入框基础形状
                                    // 注意：它在 idle / morphing / shrinking 三个状态中始终存在，
                                    //       通过 targetWidth / targetHeight / targetCornerRadius 的变化
                                    //       实现从“粘滞长条”向中间圆球收缩的过渡。
                                    RoundedRectangle(cornerRadius: targetCornerRadius)
                                        .frame(width: targetWidth, height: targetHeight)
                                        .offset(x: currentInputOffset)
                                    
                                    // 形状1b: 活跃状态时的 Blob 轮廓（仅在收缩阶段叠加在主圆之上）
                                    if recordingState == .shrinking && isActiveBlob {
                                        BlobShape(time: blobTime, isAnimating: true, amplitude: 0.35)
                                            .frame(width: circleSize * 1.25, height: circleSize * 1.25)
                                            .offset(x: 0)
                                    }
                                    
                                    // 形状2: 右侧按钮 (只在非收缩阶段显示，参与融合)
                                    if recordingState != .shrinking {
                                        Circle()
                                            .frame(width: buttonSize, height: buttonSize)
                                            .offset(x: buttonIdleOffset)
                                    }
                                    
                                    // 形状3: 连接体 (Connector) - 仅在 morphing 阶段出现，连接两者
                                    if recordingState == .morphing {
                                        // 计算连接位置
                                        let inputRightEdge = inputIdleOffset + inputContainerWidth / 2
                                        let buttonLeftEdge = buttonIdleOffset - buttonSize / 2
                                        let connectorWidth = buttonLeftEdge - inputRightEdge + 30 // +30 确保重叠
                                        let connectorX = (inputRightEdge + buttonLeftEdge) / 2
                                        
                                        Rectangle()
                                            .frame(width: connectorWidth, height: 20)
                                            .offset(x: connectorX)
                                    }
                                    
                                    // 形状4: 旋转小圆 - 仅在 shrinking 且“当前没有文字输出动画”时出现
                                    // 当 isOutputtingText = true 时，用 Blob 表达状态，不再显示小圆。
                                    // 旋转小圆：仅在静音且非活跃状态时显示
                                    // 当处于活跃状态（说话或转文字）时，用 Blob 表达状态，不再显示小圆。
                                    if recordingState == .shrinking && !isActiveBlob {
                                        Circle()
                                            .frame(width: smallCircleRadius * 2, height: smallCircleRadius * 2)
                                            // 注意：这里的 offset 是相对于 ZStack 中心的，而 shrinking 状态下主圆也是居中的
                                            .offset(x: orbitRadius) 
                                            .rotationEffect(.degrees(rotationAngle))
                                    }
                                }
                                .foregroundColor(.white)
                                .blur(radius: 10) // 粘滞半径
                            }
                            .compositingGroup() // 必须组合后处理
                            .contrast(20)      // 阈值化：将模糊边缘锐化
                            .luminanceToAlpha() // 黑透白显
                        }
                    }
                    .shadow(color: recordingState == .idle ? Color.black.opacity(0.05) : activeColor.opacity(0.2), radius: recordingState == .shrinking ? 15 : 2, x: 0, y: recordingState == .shrinking ? 5 : 0)
                
                    // 2. 内容层 (UI Content)
                    ZStack {
                        // A. 输入状态 UI
                        HStack(spacing: spacing) {
                            // 左侧输入框内容
                            HStack(spacing: 10) {
                                Button(action: {}) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 20, weight: .medium)) // 调整图标大小
                                        .foregroundColor(Color(hex: "999999"))
                                }
                                
                                TextField("发送消息或按住说话", text: $inputText)
                                    .font(.system(size: 17)) // 调整字体大小
                                    .foregroundColor(primaryGray)
                                    .focused($isInputFocused)
                                    .onSubmit { sendMessage() }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(width: inputContainerWidth, height: inputHeight)
                            // 关键：手势绑定在这里，确保整个输入区域都能响应长按
                            .contentShape(Rectangle()) 
                            .highPriorityGesture(
                                // 仅在文本为空且当前没有键盘焦点时响应长按，
                                // 避免与正常点按唤起键盘冲突
                                (inputText.isEmpty && !isInputFocused) ? voiceInputGesture : nil
                            )
                            
                            // 右侧工具箱按钮
                            Button(action: {
                                HapticFeedback.light()
                                showModuleContainer = true
                            }) {
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 22)) // 调整图标大小以匹配按钮高度
                                    .foregroundColor(Color(hex: "666666"))
                                    .frame(width: buttonSize, height: buttonSize)
                                    .contentShape(Circle())
                            }
                            .opacity(recordingState == .idle ? 1 : 0)
                        }
                        .frame(width: areaWidth, alignment: .leading)
                        
                        // 输入 UI 在 shrinking 和 morphing 时都完全隐藏 (只在 idle 显示)
                        .opacity(recordingState == .idle ? 1 : 0)
                        .animation(nil, value: recordingState) // 立即隐藏，无动画，防止残影
                        
                        // B. 录音状态 UI（原本有外层波纹光晕，这里去掉虚影）
                        if recordingState == .shrinking {
                            // 如需恢复波纹光晕，可在这里重新添加 BlobShape
                        }
                    }
                }
                .frame(height: containerHeight) // 根据状态动态调整高度，避免录音圆被裁剪
                // 移除 recordingState 的隐式动画，完全由 runRecordingAnimation 中的 withAnimation 精确控制
                .animation(.easeInOut(duration: 0.2), value: isCanceling)
                // 添加 isOutputtingText 变化的平滑动画，确保圆的大小和波动幅度变化流畅
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isOutputtingText)
            }
            .padding(.horizontal, horizontalMargin)
            .padding(.bottom, bottomMargin)
        }
        .opacity(showContent ? 1 : 0)
    }
    
    // MARK: - 发送消息
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isAgentTyping else { return }
        
        inputText = ""
        sendChatMessage(text: text)
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = appState.chatMessages.last?.id {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    /// 封装发送单条聊天消息（可被引导完成后复用）
    private func sendChatMessage(text: String, isGreeting: Bool = false) {
        guard !text.isEmpty else { return }
        
        // 添加用户消息
        let userMsg = ChatMessage(role: .user, content: text, isGreeting: isGreeting)
        withAnimation {
            appState.chatMessages.append(userMsg)
        }
        appState.saveMessageToStorage(userMsg, modelContext: modelContext)
        
        // 创建 AI 占位消息
        let agentMsg = ChatMessage(role: .agent, content: "")
        withAnimation {
            appState.chatMessages.append(agentMsg)
        }
        let messageId = agentMsg.id
        
        // 调用 AI
        Task {
            appState.isAgentTyping = true
            appState.startStreaming(messageId: messageId)
            
            await SmartModelRouter.sendMessageStream(
                messages: appState.chatMessages,
                mode: appState.currentMode,
                onComplete: { finalText in
                    await appState.playResponse(finalText, for: messageId)
                    await MainActor.run {
                        if let completedMessage = appState.chatMessages.first(where: { $0.id == messageId }) {
                            appState.saveMessageToStorage(completedMessage, modelContext: modelContext)
                        }
                    }
                },
                onError: { error in
                    appState.handleStreamingError(error, for: messageId)
                    appState.isAgentTyping = false
                }
            )
        }
    }
}

// MARK: - Subviews

// MARK: - 自定义视频播放视图（不拦截点击）
struct LoopingVideoView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.playerLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}

// MARK: - AI视频头像组件
struct AvatarVideoView: View {
    let videoName: String
    let size: CGFloat
    
    @State private var player: AVPlayer?
    @State private var showFullScreen = false
    
    var body: some View {
        ZStack {
            if let player = player {
                // 使用自定义视频视图
                LoopingVideoView(player: player)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 1))
                
                // 透明的可点击层
                Circle()
                    .fill(Color.clear)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .onTapGesture {
                        HapticFeedback.light()
                        showFullScreen = true
                    }
            } else {
                // 加载失败时的占位图
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: size, height: size)
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if let player = player {
                FullScreenVideoPlayer(player: player)
            }
        }
    }
    
    private func setupPlayer() {
        guard let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") else {
            print("视频文件未找到: \(videoName).mp4")
            return
        }
        
        let playerItem = AVPlayerItem(url: videoURL)
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        // 静音播放（头像区域）
        newPlayer.isMuted = true
        
        // 设置循环播放
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }
        
        self.player = newPlayer
        newPlayer.play()
    }
}

// MARK: - 全屏视频播放器（直接使用同一个player）
struct FullScreenVideoPlayer: View {
    let player: AVPlayer
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VideoPlayer(player: player)
                .ignoresSafeArea()
            
            // 透明的可点击层覆盖整个屏幕
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    HapticFeedback.light()
                    dismiss()
                }
        }
        .onAppear {
            // 全屏时开启声音
            player.isMuted = false
        }
        .onDisappear {
            // 返回时静音
            player.isMuted = true
        }
    }
}

// 打字机效果气泡 (用于引导)
struct TypewriterBubble: View {
    let text: String
    let isAI: Bool
    var delay: Double = 0
    
    @State private var displayedText: String = ""
    @State private var isCompleted: Bool = false
    @State private var timer: Timer?
    
    var body: some View {
        Group {
            if isAI {
                HStack(alignment: .top, spacing: 12) {
                    AvatarVideoView(videoName: "Agent", size: agentAvatarSize)
                    
                    Text(displayedText)
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "333333"))
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75)
            } else {
                UserBubble(text: displayedText)
            }
        }
        .onAppear {
            startTypewriter()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func startTypewriter() {
        guard !isCompleted, !text.isEmpty else { return }
        
        // 延迟开始
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            var charIndex = 0
            let chars = Array(self.text)
            
            self.timer?.invalidate()
            
            // 先立即显示第一个字符，再启动定时器，避免先短暂空白
            if !chars.isEmpty {
                self.displayedText = String(chars[0])
                charIndex = 1
            }
            
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                if charIndex < chars.count {
                    self.displayedText.append(chars[charIndex])
                    charIndex += 1
                    if charIndex % 2 == 0 {
                        HapticFeedback.soft()
                    }
                } else {
                    timer.invalidate()
                    self.isCompleted = true
                    self.timer = nil
                }
            }
        }
    }
}

// 标准 AI 气泡（带打字机效果）
struct AIBubble: View {
    let text: String
    let messageId: UUID?
    
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    @State private var displayedText: String = ""
    @State private var isCompleted: Bool = false
    @State private var timer: Timer?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 头像
            AvatarVideoView(videoName: "Agent", size: agentAvatarSize)
            
            VStack(alignment: .leading, spacing: 12) {
                // 内容文字（打字机效果）
                Text(displayedText)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "333333"))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 操作栏
                HStack(spacing: 16) {
                    // 复制按钮
                    Button(action: {
                        HapticFeedback.light()
                        copyToClipboard()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "999999"))
                    }
                    
                    // 重新生成按钮
                    Button(action: {
                        HapticFeedback.light()
                        regenerateMessage()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "999999"))
                    }
                }
                .opacity(isCompleted ? 1 : 0)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
            
            Spacer(minLength: 20)
        }
        .onAppear {
            startTypewriter()
        }
        .onChange(of: text) { oldValue, newValue in
            if oldValue != newValue {
                resetAndStartTypewriter()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    // 复制到剪贴板
    private func copyToClipboard() {
        UIPasteboard.general.string = text
    }
    
    // 重新生成消息
    private func regenerateMessage() {
        guard let messageId = messageId else { return }
        
        // 找到当前AI消息在列表中的位置
        guard let currentIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        // 找到这条AI消息对应的用户消息（应该是前一条）
        guard currentIndex > 0 else { return }
        let userMessage = appState.chatMessages[currentIndex - 1]
        guard userMessage.role == .user else { return }
        
        // 清空当前AI消息内容，准备重新生成
        appState.chatMessages[currentIndex].content = ""
        appState.chatMessages[currentIndex].streamingState = .idle
        
        // 重新调用API
        Task {
            appState.isAgentTyping = true
            appState.startStreaming(messageId: messageId)
            
            await SmartModelRouter.sendMessageStream(
                messages: Array(appState.chatMessages.prefix(currentIndex)), // 只包含当前消息之前的消息
                mode: appState.currentMode,
                onComplete: { finalText in
                    await appState.playResponse(finalText, for: messageId)
                    await MainActor.run {
                        if let completedMessage = appState.chatMessages.first(where: { $0.id == messageId }) {
                            appState.saveMessageToStorage(completedMessage, modelContext: modelContext)
                        }
                    }
                },
                onError: { error in
                    appState.handleStreamingError(error, for: messageId)
                    appState.isAgentTyping = false
                }
            )
        }
    }
    
    private func startTypewriter() {
        guard !text.isEmpty else { return }
        
        // 如果已经显示完整，直接显示
        if displayedText == text {
            isCompleted = true
            return
        }
        
        // 重置状态
        displayedText = ""
        isCompleted = false
        
        // 在主线程上开始打字机效果
        DispatchQueue.main.async {
            var charIndex = 0
            let chars = Array(self.text)
            
            self.timer?.invalidate()
            
            // 先立即显示第一个字符，再启动定时器，减少从「正在思考」到首字出现的空档
            if !chars.isEmpty {
                self.displayedText = String(chars[0])
                charIndex = 1
            }
            
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                if charIndex < chars.count {
                    self.displayedText.append(chars[charIndex])
                    charIndex += 1
                    if charIndex % 2 == 0 {
                        HapticFeedback.soft()
                    }
                } else {
                    timer.invalidate()
                    self.isCompleted = true
                    self.timer = nil
                }
            }
        }
    }
    
    private func resetAndStartTypewriter() {
        timer?.invalidate()
        timer = nil
        displayedText = ""
        isCompleted = false
        startTypewriter()
    }
}

// 标准用户气泡
struct UserBubble: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Spacer(minLength: agentAvatarSize + 12) // 对齐到AI文本左侧起点（头像30 + spacing12）
            
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "333333")) // 黑色文字
                .lineSpacing(5)
                .padding(14)
                .background(
                    BubbleShape(myRole: .user)
                        .fill(Color.white) // 纯白色背景
                        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                )
                .frame(maxWidth: UIScreen.main.bounds.width * 0.80 + 28, alignment: .trailing) // +28补偿padding，使文本宽度与AI一致
            
            Spacer(minLength: 4) // 额外4点间距，使总侧向padding达到20（父容器16 + 4）
        }
    }
}

// 操作按钮组件
struct ActionButton: View {
    let icon: String
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
        }) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "999999"))
        }
    }
}

// 气泡形状
struct BubbleShape: Shape {
    enum Role {
        case user
        case agent
    }
    
    let myRole: Role
    
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        
        // 用户：所有角都是圆角
        // AI：左上角为小圆角（气泡尾巴在左上）
        let topLeftRadius: CGFloat = myRole == .agent ? 4 : 20
        let topRightRadius: CGFloat = 20
        let bottomLeftRadius: CGFloat = 20
        let bottomRightRadius: CGFloat = 20
        
        return Path { path in
            path.move(to: CGPoint(x: topLeftRadius, y: 0))
            path.addLine(to: CGPoint(x: width - topRightRadius, y: 0))
            path.addArc(center: CGPoint(x: width - topRightRadius, y: topRightRadius), radius: topRightRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
            path.addLine(to: CGPoint(x: width, y: height - bottomRightRadius))
            path.addArc(center: CGPoint(x: width - bottomRightRadius, y: height - bottomRightRadius), radius: bottomRightRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
            path.addLine(to: CGPoint(x: bottomLeftRadius, y: height))
            path.addArc(center: CGPoint(x: bottomLeftRadius, y: height - bottomLeftRadius), radius: bottomLeftRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: topLeftRadius))
            path.addArc(center: CGPoint(x: topLeftRadius, y: topLeftRadius), radius: topLeftRadius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        }
    }
}

// 模糊效果组件
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

#Preview {
    HomeChatView(showModuleContainer: .constant(false))
        .environmentObject(AppState())
}
