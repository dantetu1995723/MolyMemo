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

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var allContacts: [Contact]
    @Binding var showModuleContainer: Bool
    
    // MARK: - Input ViewModel
    @StateObject private var inputViewModel = ChatInputViewModel()
    @Namespace private var inputNamespace
    
    // UI State
    @State private var showContent: Bool = false
    @State private var contentHeight: CGFloat = 0
    /// 卡片横向翻页时，临时禁用外层聊天上下滚动，避免手势冲突
    @State private var isCardHorizontalPaging: Bool = false
    
    // 删除确认弹窗状态
    @State private var showDeleteConfirmation: Bool = false
    @State private var eventToDelete: ScheduleEvent? = nil
    @State private var messageIdToDeleteFrom: UUID? = nil

    // 日程详情弹窗（点击卡片打开）
    private struct ScheduleDetailSelection: Identifiable, Equatable {
        let messageId: UUID
        let eventId: UUID
        var id: String { "\(messageId.uuidString)-\(eventId.uuidString)" }
    }
    @State private var scheduleDetailSelection: ScheduleDetailSelection? = nil

    // 人脉详情（从 ContactCard 转换/创建 SwiftData Contact 后打开 ContactDetailView）
    @State private var selectedContact: Contact? = nil

    // 发票/报销详情（点击卡片打开）
    private struct InvoiceDetailSelection: Identifiable, Equatable {
        let messageId: UUID
        let invoiceId: UUID
        var id: String { "\(messageId.uuidString)-\(invoiceId.uuidString)" }
    }
    @State private var invoiceDetailSelection: InvoiceDetailSelection? = nil
    
    // 主题色
    private let primaryGray = Color(hex: "333333")
    private let secondaryGray = Color(hex: "666666")
    private let backgroundGray = Color(hex: "F7F8FA")
    private let bubbleWhite = Color.white
    private let userBubbleColor = Color(hex: "222222") // 深黑色用户气泡

    // MARK: - Helpers (Chat Card -> SwiftData Model)
    private func findOrCreateContact(from card: ContactCard) -> Contact {
        // 先尝试根据 id 查找（如果之前创建时同步了 id，可命中）
        if let existing = allContacts.first(where: { $0.id == card.id }) {
            return existing
        }
        // 再尝试根据名字 + 电话查找
        if let phone = card.phone, !phone.isEmpty,
           let existing = allContacts.first(where: { $0.name == card.name && $0.phoneNumber == phone }) {
            return existing
        }
        // 创建新的 SwiftData Contact（保持 UI 不变，只是为了复用现有详情页）
        let newContact = Contact(
            name: card.name,
            phoneNumber: card.phone,
            company: card.company,
            identity: card.title,
            avatarData: card.avatarData
        )
        // 关键：让 id 跟卡片 id 对齐，后续能稳定复用同一联系人
        newContact.id = card.id
        modelContext.insert(newContact)
        try? modelContext.save()
        return newContact
    }
    
    var body: some View {
        GeometryReader { geometry in
            // 根据屏幕高度和底部输入区域高度，计算聊天内容可见高度
            let bottomSafeArea = geometry.safeAreaInsets.bottom
            // 聊天记录与输入栏之间预留的间距
            let clipGap: CGFloat = 0
            
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
                                .frame(height: bottomInputBaseHeight) // Use a rough estimate or bind to actual height
                        }
                        .onTapGesture {
                            // 点击空白处收回键盘
                            if inputViewModel.isInputFocused {
                                inputViewModel.isInputFocused = false
                            }
                            if inputViewModel.showMenu {
                                withAnimation {
                                    inputViewModel.showMenu = false
                                }
                            }
                            // 点击聊天空白处同时取消日程卡片选中（关闭胶囊菜单）
                            NotificationCenter.default.post(name: .dismissScheduleMenu, object: nil)
                        }
                        .onChange(of: appState.chatMessages.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                // 裁剪 + 虚化聊天内容区域：
                .mask(
                    VStack(spacing: 0) {
                        let fadeHeight: CGFloat = 20
                        
                        // 完全清晰区域
                        Color.white
                        
                        // 虚化淡出区域
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white,
                                Color.white.opacity(0.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeHeight)
                        
                        // 底部透明区域
                        Color.clear
                            .frame(height: bottomInputBaseHeight)
                    }
                )
                
                // 底部输入区域 (浮动在最上层)
                ChatInputView(viewModel: inputViewModel, namespace: inputNamespace)
                    .zIndex(101)
                
                // 录音动画覆盖层（松手后保持一小段时间跑逆向动画）
                if inputViewModel.isRecording || inputViewModel.isAnimatingRecordingExit {
                    VoiceRecordingOverlay(
                        isRecording: $inputViewModel.isRecording,
                        isCanceling: $inputViewModel.isCanceling,
                        isExiting: inputViewModel.isAnimatingRecordingExit,
                        onExitComplete: {
                            inputViewModel.finishRecordingOverlayDismissal()
                        },
                        audioPower: inputViewModel.audioPower,
                        transcript: inputViewModel.recordingTranscript,
                        inputFrame: inputViewModel.inputFrame,
                        toolboxFrame: inputViewModel.toolboxFrame
                    )
                    .zIndex(102)
                }
            }
            .sheet(item: $scheduleDetailSelection, onDismiss: {
                scheduleDetailSelection = nil
            }) { selection in
                if
                    let msgIndex = appState.chatMessages.firstIndex(where: { $0.id == selection.messageId }),
                    let eventIndex = appState.chatMessages[msgIndex].scheduleEvents?.firstIndex(where: { $0.id == selection.eventId })
                {
                    ScheduleDetailSheet(
                        event: Binding(
                            get: {
                                appState.chatMessages[msgIndex].scheduleEvents?[eventIndex]
                                ?? ScheduleEvent(title: "", description: "", startTime: Date(), endTime: Date())
                            },
                            set: { appState.chatMessages[msgIndex].scheduleEvents?[eventIndex] = $0 }
                        ),
                        onDelete: {
                            withAnimation {
                                appState.chatMessages[msgIndex].scheduleEvents?.removeAll(where: { $0.id == selection.eventId })
                            }
                            appState.saveMessageToStorage(appState.chatMessages[msgIndex], modelContext: modelContext)
                        },
                        onSave: { updated in
                            withAnimation {
                                appState.chatMessages[msgIndex].scheduleEvents?[eventIndex] = updated
                            }
                            appState.saveMessageToStorage(appState.chatMessages[msgIndex], modelContext: modelContext)
                        }
                    )
                } else {
                    VStack {
                        Text("日程不存在或已删除")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "666666"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
                }
            }
            .sheet(item: $invoiceDetailSelection, onDismiss: {
                invoiceDetailSelection = nil
            }) { selection in
                if
                    let msgIndex = appState.chatMessages.firstIndex(where: { $0.id == selection.messageId }),
                    let invoiceIndex = appState.chatMessages[msgIndex].invoices?.firstIndex(where: { $0.id == selection.invoiceId })
                {
                    InvoiceDetailSheet(
                        invoice: Binding(
                            get: {
                                appState.chatMessages[msgIndex].invoices?[invoiceIndex]
                                ?? InvoiceCard(invoiceNumber: "", merchantName: "", amount: 0, date: Date(), type: "", notes: nil)
                            },
                            set: { appState.chatMessages[msgIndex].invoices?[invoiceIndex] = $0 }
                        ),
                        onDelete: {
                            withAnimation {
                                appState.chatMessages[msgIndex].invoices?.removeAll(where: { $0.id == selection.invoiceId })
                            }
                            appState.saveMessageToStorage(appState.chatMessages[msgIndex], modelContext: modelContext)
                        }
                    )
                } else {
                    VStack {
                        Text("记录不存在或已删除")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "666666"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                }
            }
            .sheet(item: $selectedContact) { contact in
                ContactDetailView(contact: contact)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            
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
            
            // 同步初始状态
            inputViewModel.isAgentTyping = appState.isAgentTyping
            
            // 配置 ViewModel Actions
            inputViewModel.onSend = { text, image in
                // 这里必须把图片真正写入 ChatMessage，否则后续模型路由/渲染都拿不到图片
                let images = image.map { [$0] } ?? []
                sendChatMessage(text: text, images: images)
            }
            
            inputViewModel.onBoxTap = {
                showModuleContainer = true
            }
            
            inputViewModel.onStopGenerator = {
                appState.stopGeneration()
            }
            
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
        .onChange(of: appState.isAgentTyping) { _, newValue in
            inputViewModel.isAgentTyping = newValue
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
            Text("MolyMemo")
                .font(.custom("SourceHanSerifSC-Bold", size: 17))
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
                    UserBubble(text: message.content, images: message.images)
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
                            }, onOpenDetail: { event in
                                scheduleDetailSelection = ScheduleDetailSelection(messageId: message.id, eventId: event.id)
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
                            ), isParentScrollDisabled: $isCardHorizontalPaging,
                            onOpenDetail: { card in
                                selectedContact = findOrCreateContact(from: card)
                            }, onDeleteRequest: { card in
                                withAnimation {
                                    appState.chatMessages[index].contacts?.removeAll(where: { $0.id == card.id })
                                    appState.saveMessageToStorage(appState.chatMessages[index], modelContext: modelContext)
                                }
                            })
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
                            ), onOpenDetail: { invoice in
                                invoiceDetailSelection = InvoiceDetailSelection(messageId: message.id, invoiceId: invoice.id)
                            }, onDeleteRequest: { invoice in
                                withAnimation {
                                    appState.chatMessages[index].invoices?.removeAll(where: { $0.id == invoice.id })
                                    appState.saveMessageToStorage(appState.chatMessages[index], modelContext: modelContext)
                                }
                            })
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
    
    // MARK: - Helper Methods
    
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
    private func sendChatMessage(text: String, images: [UIImage] = [], isGreeting: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        
        // 添加用户消息（支持：纯文字 / 纯图片 / 图文混合）
        let userMsg: ChatMessage = {
            if images.isEmpty {
                return ChatMessage(role: .user, content: trimmed, isGreeting: isGreeting)
            } else {
                return ChatMessage(role: .user, images: images, content: trimmed)
            }
        }()
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
        appState.currentGenerationTask = Task {
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
                
                // 操作栏（仅在需要时显示）
                if showActionButtons || isInterrupted {
                    HStack(alignment: .center, spacing: 12) {
                        if showActionButtons {
                            // 复制按钮
                            Button(action: {
                                HapticFeedback.light()
                                copyToClipboard()
                            }) {
                                Image(systemName: "square.on.square")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: "999999"))
                                    .frame(height: 18)
                            }
                            
                            // 重新生成按钮
                            Button(action: {
                                HapticFeedback.light()
                                regenerateMessage()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: "999999"))
                                    .frame(height: 18)
                            }
                        }
                        
                        if isInterrupted {
                            if showActionButtons { Spacer() }
                            Text("回答已停止")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "999999"))
                                .frame(height: 18)
                                .frame(maxWidth: showActionButtons ? .none : .infinity, alignment: .trailing)
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
        appState.currentGenerationTask = Task {
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
    var images: [UIImage] = []
    
    private let messageImageSize: CGFloat = 120
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Spacer(minLength: agentAvatarSize + 12) // 对齐到AI文本左侧起点（头像30 + spacing12）
            
            VStack(alignment: .trailing, spacing: 8) {
                if !images.isEmpty {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: messageImageSize, height: messageImageSize) // 圆角正方形缩略图（大于下方指令胶囊）
                            .cornerRadius(12)
                            .clipped()
                    }
                }
                
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                }
            }
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
        HStack(alignment: .center, spacing: 12) {
            // 复制按钮
            Button(action: {
                HapticFeedback.light()
                copyMessageToClipboard()
            }) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .frame(height: 18)
            }
            
            // 重新生成按钮
            Button(action: {
                HapticFeedback.light()
                regenerateMessage()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .frame(height: 18)
            }
            
            if let message = appState.chatMessages.first(where: { $0.id == messageId }), message.isInterrupted {
                Spacer()
                Text("回答已停止")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "999999"))
                    .frame(height: 18)
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
        appState.currentGenerationTask = Task {
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
    ChatView(showModuleContainer: .constant(false))
        .environmentObject(AppState())
}
