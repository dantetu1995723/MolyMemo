import SwiftUI
import SwiftData
import AVKit
import AVFoundation

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
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
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
        withAnimation(.easeOut(duration: 0.25)) {
            recordingState = .morphing
        }
        
        // 2. 缩圆：0.25s后从全宽收缩成圆形，颜色变深
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if self.speechRecognizer.isRecording {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
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
        withAnimation(.easeOut(duration: 0.2)) {
            recordingState = .idle
            showBlob = false
        }
        stopBlobAnimation()
    }
    
    private func startBlobAnimation() {
        stopBlobAnimation()
        // 使用更快的刷新率 (~60fps) 驱动相位变化
        blobTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            blobTime += 0.05
        }
    }
    
    private func stopBlobAnimation() {
        blobTimer?.invalidate()
        blobTimer = nil
        blobTime = 0
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
            // 如果没有聊天历史，显示打招呼
            if appState.chatMessages.isEmpty {
                if appState.isGeneratingGreeting {
                    // 正在生成打招呼
                    HStack(alignment: .top, spacing: 12) {
                        AvatarVideoView(videoName: "Agent", size: agentAvatarSize)
                        
                        HStack(spacing: 6) {
                            Text("正在想说什么")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "999999"))
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Spacer(minLength: 20)
                    }
                } else if !appState.aiGreeting.isEmpty {
                    // 显示已生成的打招呼（用 AIBubble 展示打字机效果）
                    AIBubble(text: appState.aiGreeting)
                }
            }
            
            // 消息列表
            ForEach(appState.chatMessages) { message in
                if message.role == .user {
                    UserBubble(text: message.content)
                        .id(message.id)
                } else {
                    AIBubble(text: message.content.isEmpty && appState.isAgentTyping ? "正在思考..." : message.content)
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
            let areaWidth = geometry.size.width
            let buttonSize: CGFloat = 44
            let spacing: CGFloat = 10
            let horizontalPadding: CGFloat = 32 // 16 * 2
            let innerPadding: CGFloat = 28 // 14 * 2
            
            // 计算输入框宽度: 总宽 - 左右边距 - 按钮宽 - 按钮间距 - 内部左侧加号按钮宽 - 内部间距
            // 这里我们需要的是整个"输入框背景"的宽度，即包含加号按钮和TextField的那个容器
            // InputContainerWidth = AreaWidth - HorizontalPadding - ButtonSize - Spacing
            let inputContainerWidth = areaWidth - horizontalPadding - buttonSize - spacing
            
            let circleSize: CGFloat = 60  // 最终圆形尺寸
            let fullWidth = areaWidth - horizontalPadding
            let inputHeight: CGFloat = 44
            
            // 计算当前状态下的目标 Frame
            var targetWidth: CGFloat {
                switch recordingState {
                case .idle: return inputContainerWidth
                case .morphing: return fullWidth
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
                case .idle: return 22
                case .morphing: return 22
                case .shrinking: return circleSize / 2
                }
            }
            
            // 计算偏移量
            // idle 时，InputContainer 位于左侧。GeometryReader 的原点在左上角。
            // 我们的 ZStack 是居中的。
            // InputContainer 的中心 x: HorizontalPadding/2 + InputContainerWidth/2
            // Area 的中心 x: AreaWidth / 2
            // Offset = InputCenter - AreaCenter
            //        = (16 + InputContainerWidth/2) - (AreaWidth/2)
            var xOffset: CGFloat {
                if recordingState == .idle {
                    let inputCenter = 16 + inputContainerWidth / 2
                    let areaCenter = areaWidth / 2
                    return inputCenter - areaCenter
                }
                return 0
            }
            
            // 颜色逻辑
            let lightBlueGradient = LinearGradient(
                colors: [Color(hex: "E6F0FF"), Color(hex: "CCE0FF")],
                startPoint: .top,
                endPoint: .bottom
            )
            let deepBlue = Color.blue
            let activeColor: Color = isCanceling ? Color.red : deepBlue
            
            // 是否在说话（用于波纹动画）
            let isSpeaking = !recordingTranscript.isEmpty && audioPower > 0.05
            
            ZStack {
                // 1. 统一的变形背景 (The Morphing Shape)
                ZStack {
                    // 背景色层
                    if recordingState == .idle {
                        Color.white
                    } else if recordingState == .morphing {
                        lightBlueGradient
                    } else {
                        activeColor
                    }
                }
                .mask(
                    RoundedRectangle(cornerRadius: targetCornerRadius)
                        .frame(width: targetWidth, height: targetHeight)
                )
                .shadow(color: recordingState == .idle ? Color.black.opacity(0.05) : activeColor.opacity(0.2), radius: recordingState == .shrinking ? 15 : 2, x: 0, y: recordingState == .shrinking ? 5 : 0)
                .overlay(
                    RoundedRectangle(cornerRadius: targetCornerRadius)
                        .stroke(Color(hex: "E5E5EA"), lineWidth: recordingState == .idle ? 0.5 : 0)
                        .frame(width: targetWidth, height: targetHeight)
                )
                .offset(x: xOffset)
                
                // 2. 内容层 (UI Content)
                ZStack {
                    // A. 输入状态 UI
                    HStack(spacing: spacing) {
                        // 左侧输入框内容
                        HStack(spacing: 10) {
                            Button(action: {}) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(Color(hex: "999999"))
                            }
                            
                            TextField("发送消息或按住说话", text: $inputText)
                                .font(.system(size: 16))
                                .foregroundColor(primaryGray)
                                .focused($isInputFocused)
                                .onSubmit { sendMessage() }
                                // 当内容为空时，禁用 TextField 的直接交互，由外层手势接管
                                // 这样可以防止 TextField 抢夺长按手势
                                .disabled(inputText.isEmpty)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(width: inputContainerWidth, height: inputHeight)
                        // 关键：手势绑定在这里，确保整个输入区域都能响应长按
                        .contentShape(Rectangle()) 
                        .gesture(
                            // 仅在文本为空时响应长按
                            inputText.isEmpty ? voiceInputGesture : nil
                        )
                        
                        // 右侧工具箱按钮
                        Button(action: {
                            HapticFeedback.light()
                            showModuleContainer = true
                        }) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "666666"))
                                .frame(width: buttonSize, height: buttonSize)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .overlay(Circle().stroke(Color(hex: "E5E5EA"), lineWidth: 0.5))
                                )
                        }
                        .opacity(recordingState == .idle ? 1 : 0)
                    }
                    .padding(.horizontal, 16) // 对应 geometry 里的 padding
                    // 确保 HStack 占满宽度以便对齐
                    .frame(width: areaWidth, alignment: .leading)
                    
                    // 输入 UI 在 shrinking 时完全隐藏，在 morphing 时淡出
                    .opacity(recordingState == .shrinking ? 0 : (recordingState == .morphing ? 0.5 : 1))
                    
                    // B. 录音状态 UI
                    if recordingState == .shrinking {
                        // 波纹光晕
                        if showBlob {
                            BlobShape(time: blobTime, isAnimating: isSpeaking)
                                .fill(activeColor.opacity(isSpeaking ? 0.2 : 0.1))
                                .frame(width: circleSize + 30, height: circleSize + 30)
                                .scaleEffect(isSpeaking ? 1.08 : 1.0)
                        }
                        
                        // 麦克风图标
                        Image(systemName: isCanceling ? "xmark" : "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(height: 60) // 固定高度容器
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: recordingState)
            .animation(.easeInOut(duration: 0.2), value: isCanceling)
        }
        .frame(height: 60) // GeometryReader 需要明确高度
        .padding(.bottom, 8)
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
                    ActionButton(icon: "doc.on.doc")
                    ActionButton(icon: "hand.thumbsdown")
                    ActionButton(icon: "hand.thumbsup")
                    ActionButton(icon: "speaker.wave.2")
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
        
        // 用户：右下角为小圆角（气泡尾巴在右下）
        // AI：左上角为小圆角（气泡尾巴在左上）
        let topLeftRadius: CGFloat = myRole == .agent ? 4 : 20
        let topRightRadius: CGFloat = 20
        let bottomLeftRadius: CGFloat = 20
        let bottomRightRadius: CGFloat = myRole == .user ? 4 : 20
        
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
