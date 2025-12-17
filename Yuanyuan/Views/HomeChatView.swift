import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import UIKit
import PhotosUI

// MARK: - 布局常量
private let agentAvatarSize: CGFloat = 30
/// 底部输入区域的基础高度（不含安全区），用于计算聊天内容可视区域
private let bottomInputBaseHeight: CGFloat = 64

struct HomeChatView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Binding var showModuleContainer: Bool
    
    // UI State
    @State private var inputText: String = ""
    @State private var showContent: Bool = false
    /// 输入框是否聚焦（现在输入控件是 UITextView，不走 SwiftUI FocusState，避免状态被系统回滚）
    @State private var isInputFocused: Bool = false
    @State private var contentHeight: CGFloat = 0
    /// 卡片横向翻页时，临时禁用外层聊天上下滚动，避免手势冲突
    @State private var isCardHorizontalPaging: Bool = false
    /// 日程卡片菜单是否显示，用于显示全屏背景层
    @State private var isScheduleMenuShowing: Bool = false
    /// 胶囊菜单（含下拉）在全屏坐标系下的 frame，用于判断点击是否落在菜单内
    @State private var scheduleMenuFrame: CGRect = .zero
    /// 防抖：菜单刚打开时，忽略一次“抬手点击”导致的立刻关闭
    @State private var scheduleMenuOpenedAt: CFTimeInterval = 0
    /// 可靠防抖：菜单刚打开后的“抬手那一下”可能被识别成 tap，这里直接忽略一次
    @State private var ignoreNextScheduleMenuTapClose: Bool = false
    
    // 删除确认弹窗状态
    @State private var showDeleteConfirmation: Bool = false
    @State private var eventToDelete: ScheduleEvent? = nil
    @State private var messageIdToDeleteFrom: UUID? = nil
    
    // 录音动画状态
    enum RecordingAnimationState {
        case idle
        case morphing    // 融合渐变阶段：输入框变长 + 变浅蓝 + 文字淡出
        case shrinking   // 收缩阶段：变成深蓝圆形
    }
    @State private var recordingState: RecordingAnimationState = .idle
    
    // 图片输入状态
    @State private var selectedImage: UIImage?
    @State private var showAttachmentPanel: Bool = false
    @State private var isPickerPresented: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    @State private var inputBoxSize: CGSize = .zero   // 输入框尺寸（不含右边按钮）
    @State private var currentInputSize: CGSize = .init(width: 0, height: 48) // 当前输入框内容的实际尺寸
    /// 多行输入的文本内容高度（不含外层 padding），用于驱动白底胶囊动态高度
    @State private var textInputContentHeight: CGFloat = 0
    @State private var fullAreaSize: CGSize = .zero   // 整个底部区域尺寸（含按钮）
    @State private var bottomInputAreaHeight: CGFloat = 64   // 底部输入区域的实际高度（含安全区域）
    
    // 动画驱动
    @State private var blobTime: Double = 0
    @State private var blobTimer: Timer?
    @State private var rotationAngle: Double = 0  // 小内切圆旋转角度
    @State private var colorSpread: CGFloat = 0  // 颜色扩散比例 (0.0 -> 1.5)
    
    /// 静音球 → 动态Blob 的过渡量（0 = 稳定球，1 = 无规则动态球）
    @State private var blobMorphAmount: CGFloat = 0
    /// 录音圆球的当前缩放（用于“稳定球变大 → 再进化成动态球”的分段过渡）
    @State private var recordingBallScale: CGFloat = 1.0
    @State private var ballTransitionToken: UUID = UUID()
    
    // 说话状态（带滞回，避免 audioPower 临界抖动导致频繁切换）
    @State private var isSpeakingLatched: Bool = false
    @State private var speakingOffTimer: Timer?
    
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
    @State private var pressStartLocation: CGPoint?
    @State private var pressToken: UUID = UUID()
    @State private var hasStartedRecording: Bool = false
    @State private var longPressTimer: Timer?
    
    // MARK: - 动画时长（输入框 -> 球）
    /// 输入框与按钮“融合阶段”时长（越小越快）
    private let recordMorphDuration: Double = 0.18
    /// 融合后“收缩成球”时长（越小越快）
    private let recordShrinkDuration: Double = 0.22
    /// 长按确认阈值：超过该时长才开始“变球+录音”，避免短点触发动画
    private let voicePressLongPressThreshold: Double = 0.12
    
    // MARK: - 静音 -> 说话（稳定球 -> 动态球）过渡参数
    // 更灵敏：降低触发阈值，同时保持滞回避免抖动
    private let speakOnThreshold: CGFloat = 0.035
    private let speakOffThreshold: CGFloat = 0.02
    /// 停止说话的“静音确认”时长（越小越快回落）
    private let speakSilenceConfirmDelay: Double = 0.18
    /// 转文字结束后回落到静音态的等待（越小越快）
    private let textOutputCooldown: Double = 0.45
    private let activeBallScale: CGFloat = 1.22
    private let overshootStableScale: CGFloat = 1.28
    
    /// 统一活跃状态：说话/转文字任一成立即进入动态球逻辑
    private var isActiveBlob: Bool {
        isSpeakingLatched || isOutputtingText
    }
    
    // 主题色
    private let primaryGray = Color(hex: "333333")
    private let secondaryGray = Color(hex: "666666")
    private let backgroundGray = Color(hex: "F7F8FA")
    private let bubbleWhite = Color.white
    private let userBubbleColor = Color(hex: "222222") // 深黑色用户气泡
    private let inputBorderColor = Color.black.opacity(0.12) // 输入框边框颜色
    
    var body: some View {
        GeometryReader { geometry in
            // 根据屏幕高度和底部输入区域高度，计算聊天内容可见高度
            let bottomSafeArea = geometry.safeAreaInsets.bottom
            // 聊天记录与输入栏之间预留的间距（负值会让遮罩更贴近输入框）
            let clipGap: CGFloat = -20
            // 历史记录在触碰这个高度之前完全清晰，之后进入虚化淡出区域
            let visibleChatHeight = max(
                0,
                geometry.size.height - (bottomSafeArea + bottomInputBaseHeight + clipGap)
            )
            
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
                                Color.clear.frame(height: 20)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .scrollDisabled(isCardHorizontalPaging)
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively) // 滑动时渐进收回键盘
                        .safeAreaInset(edge: .bottom) {
                            // 为底部输入区域预留空间，确保滚动内容不被遮挡
                            Color.clear
                                .frame(height: bottomInputAreaHeight)
                        }
                        .onTapGesture {
                            // 点击空白处收回键盘和面板
                            // 1. 先收键盘（系统动画，不加 withAnimation）
                            if isInputFocused {
                                isInputFocused = false
                            }
                            
                            // 2. 再收面板（UI动画）
                            if showAttachmentPanel {
                                withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                    showAttachmentPanel = false
                                }
                            }
                        }
                        .onChange(of: appState.chatMessages.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                // 裁剪 + 虚化聊天内容区域：
                // - 上方区域完全清晰
                // - 接近底部的一段做渐变虚化（始终对齐到输入框顶部）
                // - 输入栏及以下不再显示聊天记录
                .mask(
                    VStack(spacing: 0) {
                        let fadeHeight: CGFloat = 20
                        // 让遮罩略微“越过”输入框上边界，提前一点把聊天内容淡出/隐藏
                        let maskLift: CGFloat = 10
                        
                        // 完全清晰区域 - 自动填充剩余空间
                        Color.white
                        
                        // 虚化淡出区域（从不透明到完全透明）
                        // 始终对齐到输入框顶部，无论附件面板是否展开
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white,
                                Color.white.opacity(0.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeHeight)
                        
                        // 底部透明区域 = 输入区域高度 - 上提高度
                        // maskLift 向上提升，让虚化区域提前开始，所以透明区域要更小
                        Color.clear
                            .frame(height: max(0, bottomInputAreaHeight - maskLift))
                    }
                )
                
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
            // 接收日程卡片菜单状态
            .onPreferenceChange(ScheduleMenuStateKey.self) { newValue in
                isScheduleMenuShowing = newValue
                if !newValue {
                    scheduleMenuFrame = .zero
                    ignoreNextScheduleMenuTapClose = false
                } else {
                    scheduleMenuOpenedAt = CACurrentMediaTime()
                }
            }
            .onPreferenceChange(ScheduleMenuFrameKey.self) { newFrame in
                scheduleMenuFrame = newFrame
            }
            // 菜单打开防抖：用通知确保比 Preference 更早更新 openedAt
            .onReceive(NotificationCenter.default.publisher(for: .scheduleMenuDidOpen)) { _ in
                scheduleMenuOpenedAt = CACurrentMediaTime()
                ignoreNextScheduleMenuTapClose = true
            }
            // 全屏点击关闭：不靠盖一层透明 view（会抢按钮点击），而是用带坐标的 tap 手势判断
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                    // 菜单未展示：不处理
                    guard isScheduleMenuShowing else { return }
                    // 忽略“刚打开菜单的抬手那一下”（比纯时间防抖更稳定）
                    if ignoreNextScheduleMenuTapClose {
                        ignoreNextScheduleMenuTapClose = false
                        return
                    }
                    // 刚打开菜单时（通常来自长按抬手的那一下），不要立刻关闭
                    if CACurrentMediaTime() - scheduleMenuOpenedAt < 0.35 { return }
                    // 菜单刚出现的前几帧，frame 可能还是 .zero（尚未完成测量）。
                    // 这时不要做“点外部关闭”的判定，否则会出现前几次长按抬手就被立刻关闭的现象。
                    guard scheduleMenuFrame != .zero else { return }
                    // 点在胶囊/下拉内：不关闭，让按钮正常响应
                    guard !scheduleMenuFrame.contains(value.location) else { return }
                    NotificationCenter.default.post(name: .dismissScheduleMenu, object: nil)
                }
            )
            
            // 删除确认弹窗
            if showDeleteConfirmation, let event = eventToDelete {
                DeleteConfirmationView(
                    event: event,
                    onCancel: {
                        withAnimation {
                            showDeleteConfirmation = false
                            eventToDelete = nil
                            messageIdToDeleteFrom = nil
                        }
                    },
                    onConfirm: {
                        if let messageId = messageIdToDeleteFrom, let eventId = eventToDelete?.id {
                            // 执行删除逻辑
                            if let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                                withAnimation {
                                    appState.chatMessages[index].scheduleEvents?.removeAll(where: { $0.id == eventId })
                                    appState.saveMessageToStorage(appState.chatMessages[index], modelContext: modelContext)
                                }
                            }
                        }
                        
                        withAnimation {
                            showDeleteConfirmation = false
                            eventToDelete = nil
                            messageIdToDeleteFrom = nil
                        }
                    }
                )
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
            
            // 请求语音识别权限
            speechRecognizer.requestAuthorization()
            
            // DEMO: 如果没有消息，添加示例日程消息
            if appState.chatMessages.isEmpty {
                appState.addSampleScheduleMessage()
                
                // 延迟一点添加人脉示例，模拟对话流
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appState.addSampleContactMessage()
                    
                    // 再延迟一点添加发票示例
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        appState.addSampleInvoiceMessage()
                    }
                }
            }
        }
        .onChange(of: speechRecognizer.isRecording) { _, newValue in
            // 真机偶发：音频会话/引擎启动失败，isRecording 会很快变回 false，
            // 这时必须回滚 UI，否则会卡在 morphing（如你截图）。
            if !newValue {
                if recordingState != .idle && pressStartTime != nil {
                    handleRecordingFailureReset()
                }
            }
        }
        .onChange(of: audioPower) { _, newValue in
            // 仅在录音球存在时更新说话锁存，避免无意义的抖动
            if speechRecognizer.isRecording {
                updateSpeakingLatch(with: newValue)
            } else if isSpeakingLatched {
                isSpeakingLatched = false
            }
        }
        .onChange(of: recordingState) { _, newValue in
            // 进入/退出“球”态时，初始化视觉状态，避免残留
            if newValue == .shrinking {
                applyBallVisualDefaultsForCurrentState()
            } else {
                ballTransitionToken = UUID()
                blobMorphAmount = 0
                recordingBallScale = 1.0
            }
        }
        .onChange(of: isActiveBlob) { _, newValue in
            // 只在“球态”下做静音 <-> 说话的分段过渡
            guard recordingState == .shrinking else { return }
            animateBallTransition(toActive: newValue)
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
                textOutputTimer = Timer.scheduledTimer(withTimeInterval: textOutputCooldown, repeats: false) { _ in
                    // 短等待后如果没有新文字，恢复到初始状态 - 使用与形状切换一致的动画
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
    
    /// 手指按下时立刻启动“融合(morphing)”动画，提供 0 延迟视觉反馈。
    /// 注意：这里只做 UI，不启动录音；真正录音在长按确认后开始。
    private func beginVoicePressAnimationIfNeeded() {
        // 已经在球态/融合态就不重复触发
        guard recordingState == .idle else { return }
        withAnimation(.easeInOut(duration: recordMorphDuration)) {
            recordingState = .morphing
            colorSpread = 1.2
        }
    }
    
    /// 长按确认后，立即推进到“球态(shrinking)”并开始波纹。
    private func commitVoiceRecordingVisuals() {
        // 允许从 idle/morphing 直接进入 shrinking；如果已 shrinking 则忽略
        guard recordingState != .shrinking else { return }
        withAnimation(.easeInOut(duration: recordShrinkDuration)) {
            recordingState = .shrinking
        }
        startBlobAnimation()
    }
    
    private func startRecording() {
        // 重置状态
        recordingTranscript = ""
        isCanceling = false
        audioPower = 0.0
        isSpeakingLatched = false
        speakingOffTimer?.invalidate()
        speakingOffTimer = nil

        // 开始真实的语音识别
        speechRecognizer.startRecording { text in
            recordingTranscript = text
        }
    }
    
    private func endRecording() {
        // 停止语音识别
        speechRecognizer.stopRecording()
        isSpeakingLatched = false
        speakingOffTimer?.invalidate()
        speakingOffTimer = nil
        
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
    
    private func handleVoicePressBegan(globalLocation: CGPoint) {
        // 只在“初始空态&未聚焦&无面板/无图片/非打字”时接管触摸（保持原有语义，避免与编辑/发送冲突）
        guard inputText.isEmpty,
              selectedImage == nil,
              !isInputFocused,
              !appState.isAgentTyping,
              !showAttachmentPanel
        else { return }
        
        // 首次按下
        if pressStartTime == nil {
            pressStartTime = Date()
            pressStartLocation = globalLocation
            pressToken = UUID()
            isCanceling = false

            // 超过阈值后仍在按住才开始“变球+录音”（避免短点误触时出现动画）
            longPressTimer?.invalidate()
            let token = pressToken
            let timer = Timer(timeInterval: voicePressLongPressThreshold, repeats: false) { _ in
                Task { @MainActor in
                    guard self.pressStartTime != nil else { return } // 已松手
                    guard self.pressToken == token else { return } // 已开始新的按压
                    self.hasStartedRecording = true
                    HapticFeedback.medium()
                    
                    // 长按确认后才开始“变球”动画：先进入 morphing，再在 morphing 完成后收缩成球
                    self.beginVoicePressAnimationIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.recordMorphDuration) {
                        guard self.pressStartTime != nil, self.pressToken == token, self.hasStartedRecording else { return }
                        self.commitVoiceRecordingVisuals()
                    }
                    self.startRecording()
                }
            }
            longPressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func handleVoicePressChanged(globalLocation: CGPoint) {
        guard hasStartedRecording, speechRecognizer.isRecording else { return }
        guard let start = pressStartLocation else { return }
        
        let translationY = globalLocation.y - start.y
        let previousCanceling = isCanceling
        dragOffset = translationY
        
        let shouldCancel = translationY < -80
        withAnimation(.easeOut(duration: 0.15)) {
            isCanceling = shouldCancel
        }
        if shouldCancel != previousCanceling {
            HapticFeedback.selection()
        }
    }
    
    private func handleVoicePressEnded() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        
        let wasRecording = hasStartedRecording
        
        pressStartTime = nil
        pressStartLocation = nil
        hasStartedRecording = false
        
        if wasRecording {
            endRecording()
        } else {
            // 短按：回滚融合动画，恢复输入框，再聚焦
            if recordingState != .idle {
                resetRecordingAnimation()
            }
            HapticFeedback.light()
            isInputFocused = true
        }
    }
    
    // runRecordingAnimation 已被拆分为：
    // - beginVoicePressAnimationIfNeeded(): 手指按下立刻进入 morphing
    // - commitVoiceRecordingVisuals(): 长按确认后立刻进入 shrinking

    private func handleRecordingFailureReset() {
        // 录音引擎/会话启动失败时，避免 UI 停在 morphing/球态
        longPressTimer?.invalidate()
        longPressTimer = nil
        pressStartTime = nil
        hasStartedRecording = false
        
        speakingOffTimer?.invalidate()
        speakingOffTimer = nil
        
        textOutputTimer?.invalidate()
        textOutputTimer = nil
        
        // 让视觉状态快速回落
        resetRecordingAnimation()
        isSpeakingLatched = false
        isOutputtingText = false
        recordingTranscript = ""
        withAnimation(.easeOut(duration: 0.12)) {
            audioPower = 0
        }
    }
    
    private func resetRecordingAnimation() {
        stopBlobAnimation()
        
        // 1. 从圆变回长条 (Reverse of shrinking)
        // 对应 runRecordingAnimation 第2步的时长
        withAnimation(.easeInOut(duration: recordShrinkDuration)) {
            recordingState = .morphing
        }
        
        // 2. 恢复初始状态 (Reverse of morphing)
        // 对应 runRecordingAnimation 第1步的时长
        DispatchQueue.main.asyncAfter(deadline: .now() + recordMorphDuration) {
            // 确保没有开始新的录音
            if !self.speechRecognizer.isRecording && self.recordingState == .morphing {
                withAnimation(.easeInOut(duration: recordMorphDuration)) {
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
            // 动态球过渡期间，先慢后快：让“进化”更自然
            let t = max(0, min(1, Double(blobMorphAmount)))
            blobTime += (0.018 + 0.045 * t)
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
    
    // MARK: - 静音/说话状态更新与过渡
    
    private func updateSpeakingLatch(with power: CGFloat) {
        // 1) 进入说话态：高于 on 阈值立即触发
        if power > speakOnThreshold {
            speakingOffTimer?.invalidate()
            speakingOffTimer = nil
            if !isSpeakingLatched {
                isSpeakingLatched = true
            }
            return
        }
        
        // 2) 退出说话态：低于 off 阈值时，启动一个很短的“静音确认计时器”
        //    避免 audioPower 由于平滑衰减导致回落慢、体感“不灵敏”
        guard isSpeakingLatched else { return }
        
        if power < speakOffThreshold {
            if speakingOffTimer == nil {
                speakingOffTimer = Timer.scheduledTimer(withTimeInterval: speakSilenceConfirmDelay, repeats: false) { _ in
                    Task { @MainActor in
                        // 确保计时器期间没有被新的声音取消
                        self.isSpeakingLatched = false
                        self.speakingOffTimer?.invalidate()
                        self.speakingOffTimer = nil
                    }
                }
            }
        } else {
            // 介于阈值之间：视为仍在说话，取消退出计时
            speakingOffTimer?.invalidate()
            speakingOffTimer = nil
        }
    }
    
    private func applyBallVisualDefaultsForCurrentState() {
        ballTransitionToken = UUID()
        blobMorphAmount = isActiveBlob ? 1 : 0
        recordingBallScale = isActiveBlob ? activeBallScale : 1.0
    }
    
    private func animateBallTransition(toActive: Bool) {
        guard recordingState == .shrinking else { return }
        
        let token = UUID()
        ballTransitionToken = token
        
        if toActive {
            // 过渡帧节奏：
            // 1) 稳定球变大到“动态球”的目标尺寸
            // 2) 再变大到一个更大的稳定球（短暂停留的过渡帧）
            // 3) 回落到目标尺寸，同时逐渐进化成当前的无规则运动球体
            blobMorphAmount = 0
            
            withAnimation(.easeOut(duration: 0.12)) {
                recordingBallScale = activeBallScale
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard self.ballTransitionToken == token, self.recordingState == .shrinking else { return }
                withAnimation(.easeInOut(duration: 0.10)) {
                    self.recordingBallScale = self.overshootStableScale
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                guard self.ballTransitionToken == token, self.recordingState == .shrinking else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    self.recordingBallScale = self.activeBallScale
                    self.blobMorphAmount = 1
                }
            }
        } else {
            // 反向：先收回不规则形态，再回到稳定球尺寸
            withAnimation(.easeOut(duration: 0.12)) {
                blobMorphAmount = 0
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                recordingBallScale = 1.0
            }
        }
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
                    VStack(alignment: .leading, spacing: 12) {
                        // 文字部分：如果有卡片，不显示操作按钮；如果没有卡片，显示操作按钮
                        AIBubble(
                            text: message.content.isEmpty && appState.isAgentTyping ? "正在思考..." : message.content,
                            messageId: message.id,
                            showActionButtons: (message.scheduleEvents == nil || message.scheduleEvents?.isEmpty == true) && 
                                             (message.contacts == nil || message.contacts?.isEmpty == true) &&
                                             (message.invoices == nil || message.invoices?.isEmpty == true),
                            isInterrupted: message.isInterrupted
                        )
                        
                        // 卡片部分
                        if let _ = message.scheduleEvents, 
                           let index = appState.chatMessages.firstIndex(where: { $0.id == message.id }) {
                            ScheduleCardStackView(events: Binding(
                                get: { appState.chatMessages[index].scheduleEvents ?? [] },
                                set: { appState.chatMessages[index].scheduleEvents = $0 }
                            ), isParentScrollDisabled: $isCardHorizontalPaging, onDeleteRequest: { event in
                                self.eventToDelete = event
                                self.messageIdToDeleteFrom = message.id
                                withAnimation {
                                    self.showDeleteConfirmation = true
                                }
                            })
                            .frame(maxWidth: .infinity)
                            .padding(.top, -10) // Slight adjustment to bring it closer to text
                            
                            // 操作按钮：当有卡片时，显示在卡片下方，与文字左对齐
                            HStack(alignment: .center, spacing: 0) {
                                // 与头像宽度对齐的占位，使按钮和文字左对齐
                                Spacer()
                                    .frame(width: agentAvatarSize + 12) // 头像宽度 + spacing
                                
                                // 操作按钮
                                MessageActionButtons(messageId: message.id)
                            }
                            .padding(.top, 4)
                        }
                        
                        // 人脉卡片部分
                        if let _ = message.contacts,
                           let index = appState.chatMessages.firstIndex(where: { $0.id == message.id }) {
                            ContactCardStackView(contacts: Binding(
                                get: { appState.chatMessages[index].contacts ?? [] },
                                set: { appState.chatMessages[index].contacts = $0 }
                            ), isParentScrollDisabled: $isCardHorizontalPaging)
                            .frame(maxWidth: .infinity)
                            .padding(.top, -10)
                            
                            // 操作按钮
                            HStack(alignment: .center, spacing: 0) {
                                Spacer()
                                    .frame(width: agentAvatarSize + 12)
                                MessageActionButtons(messageId: message.id)
                            }
                            .padding(.top, 4)
                        }
                        
                        // 发票卡片部分
                        if let _ = message.invoices,
                           let index = appState.chatMessages.firstIndex(where: { $0.id == message.id }) {
                            InvoiceCardStackView(invoices: Binding(
                                get: { appState.chatMessages[index].invoices ?? [] },
                                set: { appState.chatMessages[index].invoices = $0 }
                            ))
                            .frame(maxWidth: .infinity)
                            .padding(.top, -10)
                            
                            // 操作按钮
                            HStack(alignment: .center, spacing: 0) {
                                Spacer()
                                    .frame(width: agentAvatarSize + 12)
                                MessageActionButtons(messageId: message.id)
                            }
                            .padding(.top, 4)
                        }
                    }
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
            let buttonSize: CGFloat = 48 // 按钮尺寸，与输入框高度一致
            let spacing: CGFloat = 10
            // 让遮罩和背景向上延伸的高度，和聊天内容遮罩的 maskLift 保持一致
            let maskLift: CGFloat = 10
            
            // 判断是否处于布局展开状态（有文字、有图片、或焦点在输入框、或附件面板打开）
            // 只要满足这些条件，输入框就撑满全宽，ShippingBox按钮隐藏
            let isLayoutExpanded = !inputText.isEmpty || selectedImage != nil || isInputFocused || showAttachmentPanel
            
            // 判断是否显示发送按钮：有内容，或者焦点在输入框时显示
            let showSendButton = !inputText.isEmpty || selectedImage != nil || isInputFocused
            
            // 计算输入框宽度: 可用宽度 - 按钮宽 - 按钮间距 (如果布局展开则全宽)
            let inputContainerWidth = isLayoutExpanded ? areaWidth : (areaWidth - buttonSize - spacing)
            
            let baseCircleSize: CGFloat = 92  // 基础圆形尺寸（调大球体）
            // 圆球尺寸由“分段过渡”驱动（静音稳定球 -> 目标尺寸 -> 过渡大稳定球 -> 进化成动态球）
            let circleSize: CGFloat = baseCircleSize * recordingBallScale
            
            // 声音跟随：不改变布局尺寸，只做轻微渲染脉冲（更灵敏、更“跟手”）
            let audioNormalized = max(0, min(1, audioPower))
            let audioPulseScale: CGFloat = {
                guard recordingState == .shrinking, isSpeakingLatched else { return 1.0 }
                // 小幅脉冲：软声也能有反馈
                return 1.0 + 0.045 * pow(audioNormalized, 0.55)
            }()
            
            // Blob 振幅：直接跟随音量（解决“检测不够灵敏/不跟手”的体感）
            let blobAmplitude: CGFloat = {
                // 说话时更强，静音转文字时保持较小但持续的动感
                let base: CGFloat = isSpeakingLatched ? 0.10 : 0.07
                let reactive: CGFloat = isSpeakingLatched ? (0.38 * pow(audioNormalized, 0.6)) : 0.10
                return (base + reactive) * blobMorphAmount
            }()
            
            // === 输入框白底胶囊动态高度（最多 3.5 行，超过则内部滚动）===
            let inputUIFont = UIFont.systemFont(ofSize: 17)
            // 文本区外的固定“镶边高度”：内层(4*2) + 外层(10*2) = 28
            let chromeVertical: CGFloat = 28
            // 白底胶囊最大高度 = 3.5 行文本 + 固定镶边高度
            let maxPillHeight: CGFloat = ceil(inputUIFont.lineHeight * 3.5) + chromeVertical
            let maxTextHeight: CGFloat = max(24, maxPillHeight - chromeVertical)
            // UITextView 测得的内容高度（至少一行）
            let measuredTextHeight: CGFloat = max(inputUIFont.lineHeight, min(textInputContentHeight, maxTextHeight))
            // 没有图片时，用“文本高度 + 镶边”驱动整体高度；有图片时，仍沿用原有测量（包含图片预览区）
            let pillHeightFromText: CGFloat = min(max(48, measuredTextHeight + chromeVertical), maxPillHeight)
            let inputHeight: CGFloat = (selectedImage == nil) ? pillHeightFromText : max(48, currentInputSize.height)
            
            // 球本身高度为 circleSize，这里上下各预留 20pt，让动态球完全不贴边
            let recordingContainerHeight: CGFloat = circleSize + 40
            
            // 动态调整高度
            let containerHeight: CGFloat = (recordingState == .shrinking ? recordingContainerHeight : inputHeight) + (showAttachmentPanel ? 250 : 0)
            
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
                case .idle: return 24
                case .morphing: return 24
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

            // 把巨大视图拆分成几个 AnyView，避免编译器 type-check 超时
            let gooeyBackground: AnyView = makeGooeyBackground(
                activeColor: activeColor,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                targetCornerRadius: targetCornerRadius,
                currentInputOffset: currentInputOffset,
                inputContainerWidth: inputContainerWidth,
                inputIdleOffset: inputIdleOffset,
                buttonIdleOffset: buttonIdleOffset,
                buttonSize: buttonSize,
                circleSize: circleSize,
                blobAmplitude: blobAmplitude,
                audioPulseScale: audioPulseScale,
                orbitRadius: orbitRadius,
                smallCircleRadius: smallCircleRadius,
                isInputActive: isLayoutExpanded
            )

            let inputOverlay: AnyView = makeInputOverlay(
                areaWidth: areaWidth,
                spacing: spacing,
                inputContainerWidth: inputContainerWidth,
                buttonSize: buttonSize,
                isLayoutExpanded: isLayoutExpanded,
                showSendButton: showSendButton
            )

            let attachmentPanel: AnyView? = showAttachmentPanel ? makeAttachmentPanel(totalWidth: areaWidth) : nil

            let root: AnyView = AnyView(
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 0) {
                        ZStack {
                            gooeyBackground
                            inputOverlay
                        }
                        // 关键：这里必须约束高度，否则 gooeyBackground 会在 GeometryReader 下铺满全屏
                        // idle/morphing：由“可测量文本高度”驱动动态高度；shrinking：固定球态高度
                        .frame(height: (recordingState == .shrinking ? circleSize + 40 : inputHeight))
                        .animation(.easeInOut(duration: 0.2), value: isCanceling)
                        
                        if let attachmentPanel {
                            attachmentPanel
                        }
                    }
                    // 让“输入栏整体上移”和“按钮旋转/淡入淡出”处于同一动画事务，避免观感不同步产生残影/领先
                    .animation(.spring(response: 0.3, dampingFraction: 1.0), value: showAttachmentPanel)
                    .padding(.horizontal, horizontalMargin)
                    .padding(.bottom, bottomMargin)
                    .background(
                        // 录音相关的所有过渡态（morphing / shrinking 以及 isRecording）底部背景必须透明，
                        // 避免“录音球回到输入框转化”过程中出现白/浅灰蒙版。
                        ((recordingState == .idle && !speechRecognizer.isRecording) ? backgroundGray : Color.clear)
                            .padding(.top, -maskLift)
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
                .background(
                    GeometryReader { innerGeometry in
                        Color.clear
                            .preference(
                                key: BottomInputAreaHeightKey.self,
                                value: containerHeight + bottomMargin
                            )
                    }
                )
                .onPreferenceChange(BottomInputAreaHeightKey.self) { newHeight in
                    withAnimation(.easeOut(duration: 0.2)) {
                        bottomInputAreaHeight = newHeight
                    }
                }
                .onChange(of: recordingState) { _, _ in }
                .photosPicker(isPresented: $isPickerPresented, selection: $selectedPhotoItem, matching: .images)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                                    self.selectedImage = image
                                    self.showAttachmentPanel = false
                                }
                            }
                        }
                    }
                }
            )

            root
        }
        .opacity(showContent ? 1 : 0)
    }

    // MARK: - bottomInputArea helpers (type-erased to speed up type-check)
    private func makeGooeyBackground(
        activeColor: Color,
        targetWidth: CGFloat,
        targetHeight: CGFloat,
        targetCornerRadius: CGFloat,
        currentInputOffset: CGFloat,
        inputContainerWidth: CGFloat,
        inputIdleOffset: CGFloat,
        buttonIdleOffset: CGFloat,
        buttonSize: CGFloat,
        circleSize: CGFloat,
        blobAmplitude: CGFloat,
        audioPulseScale: CGFloat,
        orbitRadius: CGFloat,
        smallCircleRadius: CGFloat,
        isInputActive: Bool
    ) -> AnyView {
        AnyView(
            ZStack {
                ZStack {
                    ZStack {
                        // 输入框/右侧圆形按钮的底色与页面背景保持一致
                        backgroundGray
                        activeColor
                            .mask(
                                GeometryReader { proxy in
                                    Capsule()
                                        .frame(width: max(0, proxy.size.width * colorSpread))
                                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                                        .blur(radius: 20)
                                }
                            )
                    }
                    .mask {
                        ZStack {
                            Color.black
                            Group {
                                RoundedRectangle(cornerRadius: targetCornerRadius)
                                    .frame(width: targetWidth, height: targetHeight)
                                    .offset(x: currentInputOffset)

                                if recordingState == .shrinking && blobMorphAmount > 0 {
                                    BlobShape(time: blobTime, isAnimating: true, amplitude: blobAmplitude)
                                        .frame(width: circleSize * 1.25, height: circleSize * 1.25)
                                }

                                if recordingState != .shrinking && !isInputActive {
                                    Circle()
                                        .frame(width: buttonSize, height: buttonSize)
                                        .offset(x: buttonIdleOffset)
                                }

                                if recordingState == .morphing && !isInputActive {
                                    let inputRightEdge = inputIdleOffset + inputContainerWidth / 2
                                    let buttonLeftEdge = buttonIdleOffset - buttonSize / 2
                                    let connectorWidth = buttonLeftEdge - inputRightEdge + 30
                                    let connectorX = (inputRightEdge + buttonLeftEdge) / 2

                                    Rectangle()
                                        .frame(width: connectorWidth, height: 20)
                                        .offset(x: connectorX)
                                }

                                if recordingState == .shrinking && blobMorphAmount < 1 {
                                    let t = max(0, min(1, 1 - blobMorphAmount))
                                    Circle()
                                        .frame(width: smallCircleRadius * 2 * t, height: smallCircleRadius * 2 * t)
                                        .offset(x: orbitRadius)
                                        .rotationEffect(.degrees(rotationAngle))
                                }
                            }
                            .foregroundColor(.white)
                            .blur(radius: 10)
                            .scaleEffect(audioPulseScale)
                        }
                        .compositingGroup()
                        .contrast(20)
                        .luminanceToAlpha()
                    }
                }
            }
            .shadow(
                color: recordingState == .idle
                ? Color.black.opacity(0.05)
                : activeColor.opacity(0.2),
                radius: recordingState == .shrinking ? 15 : 2,
                x: 0,
                y: recordingState == .shrinking ? 5 : 0
            )
            // 轻描边增强边界清晰度（仅输入态显示，避免影响录音球效果）
            .overlay {
                if recordingState != .shrinking {
                    ZStack {
                        // 描边必须与底层 mask 形状一致，否则会出现“底边不贴合/重影”的错位
                        RoundedRectangle(cornerRadius: targetCornerRadius, style: .continuous)
                            .strokeBorder(inputBorderColor, lineWidth: 1)
                            .frame(width: targetWidth, height: targetHeight)
                            .offset(x: currentInputOffset)
                        
                        // 右侧按钮（shippingbox）在初始态才存在
                        if !isInputActive {
                            Circle()
                                .stroke(inputBorderColor, lineWidth: 1)
                                .frame(width: buttonSize, height: buttonSize)
                                .offset(x: buttonIdleOffset)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        )
    }

    private func makeInputOverlay(
        areaWidth: CGFloat,
        spacing: CGFloat,
        inputContainerWidth: CGFloat,
        buttonSize: CGFloat,
        isLayoutExpanded: Bool,
        showSendButton: Bool
    ) -> AnyView {
        AnyView(
            ZStack {
                // 关键：避免用 transition 移除右侧按钮导致父视图快照动画（会产生“残影”）
                // 展开态把间距也收为 0，避免多出一截空隙影响对齐
                HStack(spacing: isLayoutExpanded ? 0 : spacing) {
                    VStack(spacing: 0) {
                        if let image = selectedImage {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .cornerRadius(12)
                                    .clipped()
                                    .frame(maxWidth: .infinity)

                                Button {
                                    withAnimation { selectedImage = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .gray)
                                        .font(.system(size: 24))
                                        .padding(8)
                                }
                            }
                            .padding(.bottom, 8)
                            .transition(.scale.combined(with: .opacity))
                        }

                        // 多行输入变高时，左右按钮始终贴底
                        HStack(alignment: .bottom, spacing: 10) {
                            if selectedImage == nil {
                                Button(action: {
                                    if showAttachmentPanel {
                                        // 仅收起面板，不激活键盘，回到初始状态
                                        showAttachmentPanel = false
                                        isInputFocused = false
                                    } else {
                                        // 模式切换：键盘 -> 面板
                                        // 1. 收起键盘（无动画）
                                        isInputFocused = false
                                        // 2. 展开面板动画
                                        showAttachmentPanel = true
                                    }
                                }) {
                                    // 用同一个符号做旋转，避免“旧按钮原地淡出”的残影
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 28, weight: .ultraLight))
                                        .foregroundColor(Color(hex: "333333"))
                                        .rotationEffect(.degrees(showAttachmentPanel ? 45 : 0))
                                        // 与父容器上移使用同一套 spring 参数，确保同步
                                        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: showAttachmentPanel)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Circle())
                                }
                            }

                            // 多行输入：用 UITextView 精确控制“增长到 3.5 行后内部滚动”
                            ZStack(alignment: .leading) {
                                if inputText.isEmpty {
                                    Text("发送消息或按住说话")
                                        .font(.system(size: 17))
                                        .foregroundColor(primaryGray.opacity(0.45))
                                        // 占位文字不应拦截点击，否则点不到 UITextView
                                        .allowsHitTesting(false)
                                }
                                
                                GrowingTextView(
                                    text: $inputText,
                                    isFocused: $isInputFocused,
                                    measuredHeight: $textInputContentHeight,
                                    maxHeight: max(24, ceil(UIFont.systemFont(ofSize: 17).lineHeight * 3.5)),
                                    font: UIFont.systemFont(ofSize: 17),
                                    textColor: UIColor(primaryGray)
                                )
                                .frame(height: max(UIFont.systemFont(ofSize: 17).lineHeight, min(textInputContentHeight, ceil(UIFont.systemFont(ofSize: 17).lineHeight * 3.5))))
                            }
                            .padding(.vertical, 4)
                            // 关键：初始空态时，UITextView 会优先吃掉触摸，导致外层 SwiftUI 手势拿不到事件；
                            // 这里用“透明覆盖层”只在初始空态&未聚焦时接管触摸：短按聚焦、长按录音。
                            .overlay {
                                if inputText.isEmpty,
                                   selectedImage == nil,
                                   !isInputFocused,
                                   !appState.isAgentTyping,
                                   !showAttachmentPanel {
                                    VoicePressCatcherView(
                                        onBegan: { loc in
                                            handleVoicePressBegan(globalLocation: loc)
                                        },
                                        onChanged: { loc in
                                            handleVoicePressChanged(globalLocation: loc)
                                        },
                                        onEnded: {
                                            handleVoicePressEnded()
                                        }
                                    )
                                }
                            }
                            .onChange(of: isInputFocused) { _, isFocused in
                                if isFocused {
                                    // 键盘弹起时，联动收起面板
                                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                        showAttachmentPanel = false
                                    }
                                }
                            }

                            if showSendButton {
                                Button(action: sendMessage) {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Color.blue))
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(width: inputContainerWidth)
                    // 防止在 GeometryReader 场景下被拉伸到全高，导致测量/背景异常
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { p in
                            Color.clear
                                .preference(key: InputSizeKey.self, value: p.size)
                        }
                    )
                    .onPreferenceChange(InputSizeKey.self) { size in
                        if size != .zero { currentInputSize = size }
                    }
                    .contentShape(Rectangle())

                    // 右侧按钮不再“插入/移除”，改为布局 + 透明度动画，避免产生快照残影
                    Button(action: {
                        HapticFeedback.light()
                        showModuleContainer = true
                    }) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "666666"))
                            .frame(width: buttonSize, height: buttonSize)
                            .contentShape(Circle())
                    }
                    .disabled(appState.isAgentTyping || isLayoutExpanded)
                    .allowsHitTesting(!isLayoutExpanded)
                    .opacity(isLayoutExpanded ? 0 : 1)
                    .scaleEffect(isLayoutExpanded ? 0.86 : 1)
                    // 让它在展开态不占位，从而输入框真正撑满
                    .frame(width: isLayoutExpanded ? 0 : buttonSize, height: buttonSize)
                    .clipped()
                }
                .frame(width: areaWidth, alignment: .leading)
                .opacity(recordingState == .idle ? 1 : 0)
                .animation(nil, value: recordingState)
            }
        )
    }

    private func makeAttachmentPanel(totalWidth: CGFloat) -> AnyView {
        let spacing: CGFloat = 10
        let buttonSize = (totalWidth - spacing * 2) / 3
        
        return AnyView(
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    Button {
                        // 拍照片功能
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "camera")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(Color(hex: "333333"))
                            
                            Text("拍照片")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "333333"))
                        }
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                    }

                    Button {
                        isPickerPresented = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(Color(hex: "333333"))
                            
                            Text("传图片")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "333333"))
                        }
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                    }
                    
                    Button {
                        // 扫一扫功能
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(Color(hex: "333333"))
                            
                            Text("扫一扫")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "333333"))
                        }
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                    }
                }
                
                // 第二行（目前为空，仅占位）
                HStack(spacing: spacing) {
                    Spacer()
                }
                .frame(height: buttonSize)
            }
            .padding(.top, 8)
            .padding(.horizontal, 0)
            .frame(height: buttonSize * 2 + spacing + 20, alignment: .top) // 动态调整容器高度
            .background(Color.clear)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        )
    }
    
    // MARK: - PreferenceKey for bottom input area height
    private struct BottomInputAreaHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 64
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    /// 用 UIKit 手势捕获“按下/移动/抬起”，避免 SwiftUI 手势在 UITextView/Tracking 模式下出现 1s 级延迟。
    /// - 使用 UILongPress(minimumPressDuration=0) 来获得 touch-down 即回调。
    private struct VoicePressCatcherView: UIViewRepresentable {
        let onBegan: (CGPoint) -> Void
        let onChanged: (CGPoint) -> Void
        let onEnded: () -> Void
        
        func makeUIView(context: Context) -> UIView {
            let v = UIView()
            v.backgroundColor = .clear
            
            let press = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePress(_:))
            )
            press.minimumPressDuration = 0
            press.cancelsTouchesInView = true
            press.delaysTouchesBegan = false
            press.delaysTouchesEnded = false
            v.addGestureRecognizer(press)
            
            return v
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        final class Coordinator: NSObject {
            let parent: VoicePressCatcherView
            init(_ parent: VoicePressCatcherView) { self.parent = parent }
            
            @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
                // window 坐标系（与旧的 coordinateSpace: .global 对齐）
                let loc = gesture.location(in: nil)
                switch gesture.state {
                case .began:
                    parent.onBegan(loc)
                case .changed:
                    parent.onChanged(loc)
                case .ended, .cancelled, .failed:
                    parent.onEnded()
                default:
                    break
                }
            }
        }
    }
    
    private struct InputSizeKey: PreferenceKey {
        static var defaultValue: CGSize = .init(width: 0, height: 48)
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }

    // MARK: - UIKit 多行输入（增长到 maxHeight 后启用内部滚动）
    private struct GrowingTextView: UIViewRepresentable {
        @Binding var text: String
        @Binding var isFocused: Bool
        @Binding var measuredHeight: CGFloat
        
        let maxHeight: CGFloat
        let font: UIFont
        let textColor: UIColor
        
        func makeUIView(context: Context) -> UITextView {
            let tv = UITextView()
            tv.backgroundColor = .clear
            tv.font = font
            tv.textColor = textColor
            tv.isEditable = true
            tv.isSelectable = true
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 0
            tv.isScrollEnabled = false
            tv.showsVerticalScrollIndicator = false
            tv.showsHorizontalScrollIndicator = false
            tv.delegate = context.coordinator
            tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            tv.setContentCompressionResistancePriority(.required, for: .vertical)
            return tv
        }
        
        func updateUIView(_ uiView: UITextView, context: Context) {
            if uiView.text != text {
                uiView.text = text
            }
            uiView.font = font
            uiView.textColor = textColor
            
            // 焦点同步
            if isFocused {
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
            } else {
                if uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
            }
            
            recalcHeight(for: uiView)
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        private func recalcHeight(for textView: UITextView) {
            // 宽度为 0 时先跳过，等布局稳定后会再次回调
            guard textView.bounds.width > 0 else { return }
            let fitting = textView.sizeThatFits(
                CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
            )
            let oneLine = max(font.lineHeight, 20)
            let content = max(oneLine, fitting.height)
            let clamped = min(content, maxHeight)
            
            // 超过上限后开启滚动（否则继续增长）
            textView.isScrollEnabled = content > maxHeight + 1
            
            if abs(measuredHeight - clamped) > 0.5 {
                DispatchQueue.main.async {
                    measuredHeight = clamped
                }
            }
        }
        
        final class Coordinator: NSObject, UITextViewDelegate {
            var parent: GrowingTextView
            init(_ parent: GrowingTextView) { self.parent = parent }
            
            func textViewDidChange(_ textView: UITextView) {
                parent.text = textView.text ?? ""
                parent.recalcHeight(for: textView)
            }
            
            func textViewDidBeginEditing(_ textView: UITextView) {
                if !parent.isFocused { parent.isFocused = true }
            }
            
            func textViewDidEndEditing(_ textView: UITextView) {
                if parent.isFocused { parent.isFocused = false }
            }
        }
    }
    
    // MARK: - 发送消息
    private func sendMessage() {
        var text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || selectedImage != nil), !appState.isAgentTyping else { return }
        
        if text.isEmpty && selectedImage != nil {
            text = "[图片]"
        }
        
        inputText = ""
        // 发送后收起
        isInputFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
            selectedImage = nil
            showAttachmentPanel = false
        }
        
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
        appState.isAgentTyping = true
        appState.startStreaming(messageId: messageId)
        let generationTask = Task {
            await SmartModelRouter.sendMessageStream(
                messages: appState.chatMessages,
                mode: appState.currentMode,
                onComplete: { finalText in
                    await appState.playResponse(finalText, for: messageId)
                    await MainActor.run {
                        appState.isAgentTyping = false
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
        _ = generationTask
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
    var showActionButtons: Bool = true // 控制是否显示操作按钮
    var isInterrupted: Bool = false // 是否被中断
    
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
                
                // 停止标记
                if isInterrupted {
                    Text("回答已停止")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "999999"))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, -8)
                }
                
                // 操作栏（仅在需要时显示）
                if showActionButtons {
                    HStack(spacing: 12) {
                        // 复制按钮
                        Button(action: {
                            HapticFeedback.light()
                            copyToClipboard()
                        }) {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "999999"))
                        }
                        
                        // 重新生成按钮
                        Button(action: {
                            HapticFeedback.light()
                            regenerateMessage()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "999999"))
                        }
                    }
                    .opacity(isCompleted ? 1 : 0)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
            
            Spacer(minLength: 20)
        }
        .onAppear {
            if isInterrupted {
                isCompleted = true
                displayedText = text
            } else {
            startTypewriter()
            }
        }
        .onChange(of: isInterrupted) { _, newValue in
            if newValue {
                timer?.invalidate()
                timer = nil
                isCompleted = true
                displayedText = text
            }
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
        appState.isAgentTyping = true
        appState.startStreaming(messageId: messageId)
        let generationTask = Task {
            await SmartModelRouter.sendMessageStream(
                messages: Array(appState.chatMessages.prefix(currentIndex)), // 只包含当前消息之前的消息
                mode: appState.currentMode,
                onComplete: { finalText in
                    await appState.playResponse(finalText, for: messageId)
                    await MainActor.run {
                        appState.isAgentTyping = false
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
        _ = generationTask
    }
    
    private func startTypewriter() {
        if isInterrupted {
            isCompleted = true
            displayedText = text
            return
        }
        
        guard !text.isEmpty else { return }
        
        // 如果已经显示完整，直接显示
        if displayedText == text {
            isCompleted = true
            displayedText = text
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
            
            // 先立即显示第一个字符
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

// 消息操作按钮（用于整条消息，包括文字和卡片）
struct MessageActionButtons: View {
    let messageId: UUID
    
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        HStack(spacing: 12) {
            // 复制按钮
            Button(action: {
                HapticFeedback.light()
                copyMessageToClipboard()
            }) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
            
            // 重新生成按钮
            Button(action: {
                HapticFeedback.light()
                regenerateMessage()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
        }
    }
    
    // 复制整条消息到剪贴板（包括文字和卡片信息）
    private func copyMessageToClipboard() {
        guard let message = appState.chatMessages.first(where: { $0.id == messageId }) else {
            return
        }
        
        var textToCopy = message.content
        
        // 如果有日程卡片，添加卡片信息
        if let scheduleEvents = message.scheduleEvents, !scheduleEvents.isEmpty {
            textToCopy += "\n\n日程安排：\n"
            for (index, event) in scheduleEvents.enumerated() {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy年MM月dd日 EEEE"
                let dateStr = dateFormatter.string(from: event.startTime)
                
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                let startTimeStr = timeFormatter.string(from: event.startTime)
                let endTimeStr = timeFormatter.string(from: event.endTime)
                
                textToCopy += "\n\(index + 1). \(event.title)\n"
                textToCopy += "   时间：\(dateStr) \(startTimeStr) - \(endTimeStr)\n"
                textToCopy += "   描述：\(event.description)\n"
            }
        }
        
        // 如果有人脉卡片，添加卡片信息
        if let contacts = message.contacts, !contacts.isEmpty {
            textToCopy += "\n\n人脉信息：\n"
            for (index, contact) in contacts.enumerated() {
                textToCopy += "\n\(index + 1). \(contact.name)"
                if let englishName = contact.englishName {
                    textToCopy += " (\(englishName))"
                }
                textToCopy += "\n"
                
                if let company = contact.company {
                    textToCopy += "   公司：\(company)\n"
                }
                if let title = contact.title {
                    textToCopy += "   职位：\(title)\n"
                }
                if let phone = contact.phone {
                    textToCopy += "   电话：\(phone)\n"
                }
                if let email = contact.email {
                    textToCopy += "   邮箱：\(email)\n"
                }
            }
        }
        
        // 如果有发票卡片，添加卡片信息
        if let invoices = message.invoices, !invoices.isEmpty {
            textToCopy += "\n\n发票信息：\n"
            for (index, invoice) in invoices.enumerated() {
                textToCopy += "\n\(index + 1). \(invoice.merchantName)"
                textToCopy += "\n   金额：¥\(String(format: "%.2f", invoice.amount))"
                textToCopy += "\n   类型：\(invoice.type)"
                textToCopy += "\n   发票号：\(invoice.invoiceNumber)"
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dateStr = dateFormatter.string(from: invoice.date)
                textToCopy += "\n   日期：\(dateStr)"
                
                if let notes = invoice.notes {
                    textToCopy += "\n   备注：\(notes)"
                }
                textToCopy += "\n"
            }
        }
        
        UIPasteboard.general.string = textToCopy
    }
    
    // 重新生成整条消息
    private func regenerateMessage() {
        // 找到当前AI消息在列表中的位置
        guard let currentIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        // 找到这条AI消息对应的用户消息（应该是前一条）
        guard currentIndex > 0 else { return }
        let userMessage = appState.chatMessages[currentIndex - 1]
        guard userMessage.role == .user else { return }
        
        // 清空当前AI消息内容和卡片，准备重新生成
        appState.chatMessages[currentIndex].content = ""
        appState.chatMessages[currentIndex].scheduleEvents = nil
        appState.chatMessages[currentIndex].contacts = nil
        appState.chatMessages[currentIndex].invoices = nil
        appState.chatMessages[currentIndex].streamingState = .idle
        
        // 重新调用API
        appState.isAgentTyping = true
        appState.startStreaming(messageId: messageId)
        let generationTask = Task {
            await SmartModelRouter.sendMessageStream(
                messages: Array(appState.chatMessages.prefix(currentIndex)), // 只包含当前消息之前的消息
                mode: appState.currentMode,
                onComplete: { finalText in
                    await appState.playResponse(finalText, for: messageId)
                    await MainActor.run {
                        appState.isAgentTyping = false
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
        _ = generationTask
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

// MARK: - 删除确认弹窗
struct DeleteConfirmationView: View {
    let event: ScheduleEvent
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    var body: some View {
        ZStack {
            // 全屏灰色遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // 弹窗主体
            VStack(spacing: 0) {
                // 标题 - 左对齐
                Text("确认删除该日程吗？")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "333333"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                
                // 内容
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 0) {
                        Text("时间：")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "666666")) // 灰色标签
                        Text(formatDate(event.startTime))
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "333333")) // 黑色内容
                    }
                    
                    HStack(alignment: .top, spacing: 0) {
                        Text("名称：")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "666666"))
                        Text(event.title)
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "333333"))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                
                // 按钮区域
                HStack(spacing: 15) {
                    Button(action: onCancel) {
                        Text("暂不")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "333333"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                    
                    Button(action: onConfirm) {
                        Text("删除")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "FF3B30"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(width: 300) // 固定宽度
            .background {
                ZStack {
                    // 使用更亮的 Material
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                    // 叠加白色层增加亮度（降低透明度增加灰度）
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                    // 添加灰色调提升灰度
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                }
            }
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .zIndex(2000) // 确保在最上层
        .transition(.opacity)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    HomeChatView(showModuleContainer: .constant(false))
        .environmentObject(AppState())
}
