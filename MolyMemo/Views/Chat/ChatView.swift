import SwiftUI
import SwiftData
import UIKit
import PhotosUI

// MARK: - 布局常量
/// 底部输入区域的基础高度（不含安全区），用于计算聊天内容可视区域
private let bottomInputBaseHeight: CGFloat = 64
/// 聊天卡片带阴影，视觉上会“显得更靠右”；这里做一个极小的左移补偿，让卡片边缘与上方文字更齐
private let chatCardVisualLeadingCompensation: CGFloat = 4

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var allContacts: [Contact]
    @Binding var showModuleContainer: Bool
    @Binding var imageHeroPreview: ImageHeroPreviewState?
    
    // MARK: - Input ViewModel
    @StateObject private var inputViewModel = ChatInputViewModel()
    @Namespace private var inputNamespace

    // 快捷指令/会议纪要录音：复用 LiveRecordingManager 的同一套通路
    @ObservedObject private var meetingRecordingManager = LiveRecordingManager.shared
    
    // UI State
    @State private var showContent: Bool = false
    @State private var contentHeight: CGFloat = 0
    /// 卡片横向翻页时，临时禁用外层聊天上下滚动，避免手势冲突
    @State private var isCardHorizontalPaging: Bool = false

    // 分段渲染后不再需要“先上方文字完成再放出卡片”的顺序控制（后端 JSON chunk 自带顺序）
    
    // 删除确认弹窗状态
    @State private var showDeleteConfirmation: Bool = false
    @State private var eventToDelete: ScheduleEvent? = nil
    @State private var messageIdToDeleteFrom: UUID? = nil
    
    // 聊天搜索
    @State private var showSearch: Bool = false
    @State private var pendingScrollToMessageId: UUID? = nil

    // 聊天滚动（用于：首次进入自动滚到最新；回到前台刷新后也能滚动）
    @State private var chatScrollProxy: ScrollViewProxy? = nil
    @State private var didAutoScrollOnFirstAppear: Bool = false

    // 底部避让：输入区（含附件面板）真实高度
    @State private var inputTotalHeight: CGFloat = bottomInputBaseHeight

    // AppIntent/快捷指令后台写入的 AI 回复：一次性打字机动画目标由 AppState.pendingAnimatedAgentMessageId 统一管理

    // 日程详情弹窗（点击卡片打开）
    // 统一走 RemoteScheduleDetailLoaderSheet：先拉后端详情，再进入详情编辑/保存/删除
    @State private var scheduleDetailEvent: ScheduleEvent? = nil
    @State private var scheduleDetailMessageId: UUID? = nil
    @State private var scheduleDetailEventId: UUID? = nil

    // 人脉详情（从 ContactCard 转换/创建 SwiftData Contact 后打开 ContactDetailView）
    @State private var selectedContact: Contact? = nil

    // 发票/报销：已移除详情界面（仅保留卡片展示）
    
    // 会议纪要详情（点击卡片打开）
    private struct MeetingDetailSelection: Identifiable, Equatable {
        let messageId: UUID
        let meetingId: UUID
        var id: String { "\(messageId.uuidString)-\(meetingId.uuidString)" }
    }
    @State private var meetingDetailSelection: MeetingDetailSelection? = nil
    
    // 主题色
    private let primaryGray = Color(hex: "333333")
    private let secondaryGray = Color(hex: "666666")
    private let backgroundGray = Color(hex: "F7F8FA")
    private let bubbleWhite = Color.white
    private let userBubbleColor = Color(hex: "222222") // 深黑色用户气泡

    // MARK: - 首页通知栏（今日日程）
    @State private var todayScheduleEvents: [ScheduleEvent] = []
    @State private var todayScheduleIsLoading: Bool = false
    @State private var todayScheduleErrorText: String? = nil
    @State private var isTodayScheduleExpanded: Bool = false

    init(
        showModuleContainer: Binding<Bool>,
        imageHeroPreview: Binding<ImageHeroPreviewState?> = .constant(nil)
    ) {
        self._showModuleContainer = showModuleContainer
        self._imageHeroPreview = imageHeroPreview
    }

    // MARK: - Helpers (Segment aggregation)
    /// 当用户在卡片里删除/编辑时，同步把 segments 展平回写到 message 的聚合字段（用于复制/详情页逻辑复用）
    private func rebuildAggregatesFromSegments(_ segments: [ChatSegment], into message: inout ChatMessage) {
        var schedules: [ScheduleEvent] = []
        var contacts: [ContactCard] = []
        var invoices: [InvoiceCard] = []
        var meetings: [MeetingCard] = []

        for seg in segments {
            if let s = seg.scheduleEvents, !s.isEmpty { schedules.append(contentsOf: s) }
            if let c = seg.contacts, !c.isEmpty { contacts.append(contentsOf: c) }
            if let i = seg.invoices, !i.isEmpty { invoices.append(contentsOf: i) }
            if let m = seg.meetings, !m.isEmpty { meetings.append(contentsOf: m) }
        }

        message.scheduleEvents = schedules.isEmpty ? nil : schedules
        message.contacts = contacts.isEmpty ? nil : contacts
        message.invoices = invoices.isEmpty ? nil : invoices
        message.meetings = meetings.isEmpty ? nil : meetings
    }

    // 联系人创建 loading 由结构化输出的 tool 中间态驱动，不再依赖把 raw JSON 当文本刷出来

    // MARK: - Helpers (Chat Card -> SwiftData Model)
    private func findOrCreateContact(from card: ContactCard) -> Contact {
        ContactCardLocalSync.findOrCreateContact(from: card, allContacts: allContacts, modelContext: modelContext)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let bottomAvoidHeight = max(bottomInputBaseHeight, inputTotalHeight)
            ZStack(alignment: .bottom) {
                // 背景
                backgroundView
                
                // 1. 聊天内容层
                VStack(spacing: 0) {
                    // 聊天内容区域
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 24) {
                                // 聊天内容
                                normalChatContent
                                
                                // 底部垫高 (确保最后一条消息不被输入框遮挡)
                                Color.clear.frame(height: 20)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                        }
                        .scrollDisabled(isCardHorizontalPaging)
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .onAppear {
                            // 缓存 proxy，便于外层（如回到前台刷新）也能触发滚动
                            chatScrollProxy = proxy
                            if !didAutoScrollOnFirstAppear {
                                didAutoScrollOnFirstAppear = true
                                scrollToLatestMessageOnOpen(proxy: proxy)
                            }
                        }
                        .safeAreaInset(edge: .top) {
                            // 动态计算占位高度：顶部安全区域 + 导航栏与提醒卡片的高度
                            // 修正：此处不应重复叠加 safeAreaInsets.top，除非外层已忽略安全区。
                            // 调整：由于外层现在忽略安全区，这里需要完整包含安全区 + 头部内容高度。
                            // 减小该高度可以缩短顶部间距。
                            Color.clear.frame(height: geometry.safeAreaInsets.top + 96)
                        }
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: bottomAvoidHeight)
                        }
                        .onTapGesture {
                            #if DEBUG
                            DebugProbe.log("chat scroll tap -> dismiss keyboard/menu")
                            #endif
                            // 根治：不要通过 ViewModel 回写焦点（会与 @FocusState 打架形成抖动循环）
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            if inputViewModel.showMenu {
                                withAnimation {
                                    inputViewModel.showMenu = false
                                }
                            }
                            NotificationCenter.default.post(name: .dismissScheduleMenu, object: nil)
                        }
                        .onChange(of: appState.chatMessages.count) { _, _ in
                            scrollToLatestMessageOnOpen(proxy: proxy)
                        }
                        .onChange(of: pendingScrollToMessageId) { _, newValue in
                            guard let id = newValue else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                                pendingScrollToMessageId = nil
                            }
                        }
                        .onChange(of: inputTotalHeight) { _, _ in
                            // 附件面板/建议条等高度变化时，让最新消息保持可见
                            scrollToLatestMessageOnOpen(proxy: proxy)
                        }
                    }
                }
                .zIndex(0)
                .ignoresSafeArea(edges: .top) // 让聊天区域延伸到顶部，通过 safeAreaInset 统一控制间距
                // 裁剪 + 虚化聊天内容区域：
                .mask(
                    VStack(spacing: 0) {
                        let fadeHeight: CGFloat = 20
                        Color.white
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white,
                                Color.white.opacity(0.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeHeight)
                        Color.clear.frame(height: bottomAvoidHeight)
                    }
                )
                
                // 2. 底部输入区域
                ChatInputView(viewModel: inputViewModel, namespace: inputNamespace)
                    .zIndex(101)
                    .onPreferenceChange(ChatInputTotalHeightPreferenceKey.self) { h in
                        // 避免 0/异常值导致抖动；最少保持 baseHeight
                        let clamped = max(bottomInputBaseHeight, h)
                        if abs(inputTotalHeight - clamped) > 0.5 {
                            inputTotalHeight = clamped
                        }
                    }
                
                // 3. 首页通知栏展开时的全局蒙层
                if isTodayScheduleExpanded {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .zIndex(105) 
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isTodayScheduleExpanded = false
                            }
                        }
                }

                // 4. 顶部固定区域 (常驻顶部，不受蒙层影响)
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // 手动避让顶部安全区域（灵动岛/刘海）
                        Color.clear.frame(height: geometry.safeAreaInsets.top)
                        
                        headerView
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        
                        reminderCard
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    }
                    .background(backgroundGray)
                    .clipShape(RoundedCorner(radius: 24, corners: [.bottomLeft, .bottomRight]))
                    
                    Spacer() // 撑开
                }
                .ignoresSafeArea(edges: .top) // 关键：让背景忽略顶部安全区域
                .zIndex(110) // 最高层级
                
                // 录音动画覆盖层
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
                    .zIndex(200)
                }
            }
            .sheet(item: $scheduleDetailEvent, onDismiss: {
                scheduleDetailEvent = nil
                scheduleDetailMessageId = nil
                scheduleDetailEventId = nil
            }) { _ in
                RemoteScheduleDetailLoaderSheet(
                    event: $scheduleDetailEvent,
                    onCommittedSave: { updated in
                        appState.commitScheduleCardRevision(updated: updated, modelContext: modelContext, reasonText: "已更新日程")
                    },
                    onCommittedDelete: { deleted in
                        Task { @MainActor in
                            await appState.softDeleteSchedule(deleted, modelContext: modelContext)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $meetingDetailSelection, onDismiss: {
                meetingDetailSelection = nil
            }) { selection in
                if
                    let msgIndex = appState.chatMessages.firstIndex(where: { $0.id == selection.messageId }),
                    let meetingIndex = appState.chatMessages[msgIndex].meetings?.firstIndex(where: { $0.id == selection.meetingId })
                {
                    MeetingDetailSheet(
                        meeting: Binding(
                            get: {
                                appState.chatMessages[msgIndex].meetings?[meetingIndex]
                                ?? MeetingCard(remoteId: nil, title: "", date: Date(), summary: "")
                            },
                            set: { appState.chatMessages[msgIndex].meetings?[meetingIndex] = $0 }
                        )
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
            .sheet(isPresented: $showSearch) {
                ChatSearchView(
                    messages: appState.chatMessages,
                    onSelect: { id in
                        showSearch = false
                        pendingScrollToMessageId = id
                    }
                )
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
                        if let event = eventToDelete {
                            Task { @MainActor in
                                await appState.softDeleteSchedule(event, modelContext: modelContext)
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
        // DEBUG：定位“点输入框卡死”——观察键盘通知是否在短时间内疯狂触发
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            DebugProbe.throttled("keyboard.willShow", interval: 0.4) {
                DebugProbe.log("keyboardWillShow")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            DebugProbe.throttled("keyboard.willHide", interval: 0.4) {
                DebugProbe.log("keyboardWillHide")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            DebugProbe.throttled("keyboard.willChangeFrame", interval: 0.2) {
                if let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) {
                    DebugProbe.log("keyboardWillChangeFrame end=\(end)")
                } else {
                    DebugProbe.log("keyboardWillChangeFrame (no frame)")
                }
            }
        }
        #endif
        // 键盘弹起/收起：只触发滚动，不手动改变布局（避免与系统键盘避让“双重计算”导致顶飞）
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            if let proxy = chatScrollProxy {
                scrollToLatestMessageOnOpen(proxy: proxy)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            if let proxy = chatScrollProxy {
                scrollToLatestMessageOnOpen(proxy: proxy)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }

            // 仅首次进入且内存为空时加载最近历史，避免每次进入聊天室都重载导致混乱
            if appState.chatMessages.isEmpty {
                appState.refreshChatMessagesFromStorageIfNeeded(modelContext: modelContext, limit: 80)
            }

            // ✅ 快捷指令/URL scheme 截图：进入聊天室后立即自动发送（不需要任何“转发截图”按钮）
            appState.consumeClipboardScreenshotAndAutoSendIfNeeded(modelContext: modelContext)
            
            // 同步初始状态
            inputViewModel.isAgentTyping = appState.isAgentTyping
            
            // 配置 ViewModel Actions
            inputViewModel.onSend = { text, image in
                // 这里必须把图片真正写入 ChatMessage，否则后续模型路由/渲染都拿不到图片
                let images = image.map { [$0] } ?? []
                sendChatMessage(text: text, images: images)
            }
            
            inputViewModel.onSendImmediate = {
                // 立即发送占位消息，返回消息ID用于后续更新
                return ChatSendFlow.sendPlaceholder(
                    appState: appState,
                    modelContext: modelContext,
                    placeholderText: "识别中..."
                )
            }
            
            inputViewModel.onUpdateAndSend = { messageId, text in
                // 更新消息内容并触发AI对话
                ChatSendFlow.updateAndSend(
                    appState: appState,
                    modelContext: modelContext,
                    messageId: messageId,
                    text: text
                )
            }
            
            inputViewModel.onRemovePlaceholder = { messageId in
                // 删除占位消息（用于转录失败或结果为空）
                ChatSendFlow.removePlaceholder(
                    appState: appState,
                    modelContext: modelContext,
                    messageId: messageId
                )
            }
            
            inputViewModel.onBoxTap = {
                showModuleContainer = true
            }
            
            inputViewModel.onStopGenerator = {
                appState.stopGeneration()
            }

            // 首页通知栏：初始化今日日程
            bootstrapTodayScheduleNotice()
        }
        .onChange(of: appState.isAgentTyping) { _, newValue in
            inputViewModel.isAgentTyping = newValue
        }
        .onChange(of: meetingRecordingManager.isRecording) { _, _ in
            // 录音开始/结束时，尽量保持最新内容可见
            if let proxy = chatScrollProxy {
                scrollToLatestMessageOnOpen(proxy: proxy)
            }
        }
        // 远端日程变更（创建/更新/删除）后强刷，确保通知栏及时更新
        .onReceive(NotificationCenter.default.publisher(for: .remoteScheduleDidChange).receive(on: RunLoop.main)) { _ in
            // 统一以“后端列表”为准：收到变更通知后直接强刷
            refreshTodaySchedules(force: true)
        }
        // App 回到前台时强刷，确保“今天”切换或后台被改动后能及时同步
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // 前台恢复时同步一次聊天记录，确保快捷指令后台发送的消息能出现在 UI
            appState.refreshChatMessagesFromStorageIfNeeded(modelContext: modelContext, limit: 80)
            refreshTodaySchedules(force: true)
            // 若此时 ScrollView 仍在内存中，补一次滚动到最新（避免刷新后停在中间）
            if let proxy = chatScrollProxy {
                scrollToLatestMessageOnOpen(proxy: proxy)
            }
        }
        // 系统显著时间变化（含跨天/时区变化）时强刷
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            bootstrapTodayScheduleNotice(forceRefresh: true)
        }
        // 轻量自动刷新：每分钟触发一次（不强刷，依赖 ScheduleService 缓存 TTL，避免频繁请求）
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshTodaySchedules(force: false)
        }
    }

    // MARK: - 首页通知栏：数据同步

    private func bootstrapTodayScheduleNotice(forceRefresh: Bool = false) {
        refreshTodaySchedules(force: forceRefresh)
    }

    private func refreshTodaySchedules(force: Bool) {
        // 不设置日期范围，获取所有日程
        let base = ScheduleService.ListParams(
            page: nil,
            pageSize: nil,
            startDate: nil,
            endDate: nil,
            search: nil,
            category: nil,
            relatedMeetingId: nil
        )
        
        Task {
            // 1) 非强刷：先用缓存秒开（与 TodoListView 一致），避免"看起来没请求/一直空"
            // 注意：peekAllSchedules 的 maxPages 参数只用于缓存 key，实际获取时会循环直到没有更多数据
            if !force, let cached = await ScheduleService.peekAllSchedules(maxPages: 10000, pageSize: 100, baseParams: base) {
                let cal = Calendar.current
                let sorted = cached.value
                    .filter { cal.isDate($0.startTime, inSameDayAs: Date()) }
                    .sorted(by: { $0.startTime < $1.startTime })
                
                await MainActor.run {
                    // ✅ 今日日程通知栏以后端为准：不补回“已删快照”，也不做前端置灰覆盖
                    todayScheduleEvents = sorted
                    todayScheduleIsLoading = false
                    todayScheduleErrorText = nil
                }
                
                // 即使缓存新鲜，也后台静默刷新，确保数据及时更新
                await refreshTodaySchedulesFromNetwork(base: base, forceRefresh: true, showError: false)
                return
            }
            
            // 2) 首次/强刷：走网络
            await refreshTodaySchedulesFromNetwork(base: base, forceRefresh: force, showError: true)
        }
    }

    @MainActor
    private func refreshTodaySchedulesFromNetwork(
        base: ScheduleService.ListParams,
        forceRefresh: Bool,
        showError: Bool
    ) async {
        todayScheduleIsLoading = true
        if showError { todayScheduleErrorText = nil }
        defer { todayScheduleIsLoading = false }
        
        do {
            // 与 TodoListView 完全一致：分页拉全量，再本地按日期过滤
            // 不限制页数，循环获取直到没有更多数据
            let all = try await ScheduleService.fetchScheduleListAllPages(
                maxPages: Int.max,
                pageSize: 100,
                baseParams: base,
                forceRefresh: forceRefresh
            )
            let cal = Calendar.current
            let list = all
                .filter { cal.isDate($0.startTime, inSameDayAs: Date()) }
                .sorted(by: { $0.startTime < $1.startTime })
            // ✅ 今日日程通知栏以后端为准：不补回“已删快照”，也不做前端置灰覆盖
            todayScheduleEvents = list
        } catch {
            todayScheduleEvents = []
            if showError {
                todayScheduleErrorText = error.localizedDescription
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
            // 左侧：打开设置
            Button(action: {
                HapticFeedback.light()
                appState.showSettings = true
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(primaryGray)
            }
            
            Spacer()
            
            // 中间标题
            Image("molymemo")
                .resizable()
                .scaledToFit()
                .frame(height: 30)
            
            Spacer()
            
            // 右侧：搜索聊天记录
            Button(action: {
                HapticFeedback.light()
                showSearch = true
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
        TodayScheduleNotificationBar(
            events: todayScheduleEvents,
            isLoading: todayScheduleIsLoading,
            errorText: todayScheduleErrorText,
            isExpanded: $isTodayScheduleExpanded
        )
    }
    
    // MARK: - 聊天内容
    private var normalChatContent: some View {
        Group {
            // 消息列表
            ForEach(appState.chatMessages) { message in
                if message.role == .user {
                    UserBubble(
                        message: message,
                        onOpenImage: { image, rect in
                            HapticFeedback.light()
                            imageHeroPreview = ImageHeroPreviewState(image: image, sourceRect: rect)
                        }
                    )
                    .id(message.id)
                } else {
                    let latestAgentId = appState.chatMessages.last(where: { $0.role == .agent })?.id
                    let isLatestAgentMessage = (latestAgentId != nil && message.id == latestAgentId)
                    VStack(alignment: .leading, spacing: 12) {
                        // ✅ 按后端 JSON chunk 的顺序分段渲染：发什么就按什么展示，一条流程走完
                        if let msgIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }),
                           let segments = appState.chatMessages[msgIndex].segments,
                           !segments.isEmpty {
                            
                            let lastTextSegmentId = segments.last(where: { $0.kind == .text })?.id
                            
                            ForEach(segments) { seg in
                                switch seg.kind {
                                case .text:
                                    let shouldAnimate = (
                                        (isLatestAgentMessage
                                         && appState.chatMessages[msgIndex].streamingState.isActive
                                         && (seg.id == lastTextSegmentId))
                                        ||
                                        (appState.pendingAnimatedAgentMessageId == message.id
                                         && (seg.id == lastTextSegmentId))
                                    )
                                    AIBubble(
                                        text: seg.text ?? "",
                                        messageId: message.id,
                                        shouldAnimate: shouldAnimate,
                                        showActionButtons: false,
                                        isInterrupted: message.isInterrupted,
                                        onTypingCompleted: {
                                            // ✅ 仅对“后台插入的那条消息”在打字完成后收尾：把 streamingState 置为 completed，避免反复打字
                                            guard appState.pendingAnimatedAgentMessageId == message.id else { return }
                                            guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                            appState.chatMessages[idx].streamingState = .completed
                                            appState.pendingAnimatedAgentMessageId = nil
                                            appState.saveMessageToStorage(appState.chatMessages[idx], modelContext: modelContext)
                                        }
                                    )
                                    
                                case .scheduleCards:
                                    ScheduleCardStackView(events: Binding(
                                        get: {
                                            guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }),
                                                  let sIndex = appState.chatMessages[mIndex].segments?.firstIndex(where: { $0.id == seg.id })
                                            else { return [] }
                                            return appState.chatMessages[mIndex].segments?[sIndex].scheduleEvents ?? []
                                        },
                                        set: { newValue in
                                            guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                            var m = appState.chatMessages[mIndex]
                                            guard var segs = m.segments,
                                                  let sIndex = segs.firstIndex(where: { $0.id == seg.id })
                                            else { return }
                                            segs[sIndex].scheduleEvents = newValue
                                            m.segments = segs
                                            rebuildAggregatesFromSegments(segs, into: &m)
                                            appState.chatMessages[mIndex] = m
                                        }
                                    ), isParentScrollDisabled: $isCardHorizontalPaging, onDeleteRequest: { event in
                                        self.eventToDelete = event
                                        self.messageIdToDeleteFrom = message.id
                                        withAnimation { self.showDeleteConfirmation = true }
                                    }, onOpenDetail: { event in
                                        Task {
                                            let localEventId = event.id
                                            let msgId = message.id
                                            guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == msgId }),
                                                  let sIndex = appState.chatMessages[mIndex].segments?.firstIndex(where: { $0.id == seg.id }),
                                                  let eIndex = appState.chatMessages[mIndex].segments?[sIndex].scheduleEvents?.firstIndex(where: { $0.id == localEventId })
                                            else {
                                                await MainActor.run {
                                                    scheduleDetailMessageId = msgId
                                                    scheduleDetailEventId = localEventId
                                                    scheduleDetailEvent = event
                                                }
                                                return
                                            }
                                            let rid = appState.chatMessages[mIndex].segments?[sIndex].scheduleEvents?[eIndex].remoteId
                                            if let rid, !rid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                do {
                                                    let detail = try await ScheduleService.fetchScheduleDetail(remoteId: rid, keepLocalId: localEventId)
                                                    await MainActor.run {
                                                        appState.chatMessages[mIndex].segments?[sIndex].scheduleEvents?[eIndex] = detail
                                                        if let segs = appState.chatMessages[mIndex].segments {
                                                            var mm = appState.chatMessages[mIndex]
                                                            rebuildAggregatesFromSegments(segs, into: &mm)
                                                            appState.chatMessages[mIndex] = mm
                                                        }
                                                        appState.saveMessageToStorage(appState.chatMessages[mIndex], modelContext: modelContext)
                                                        scheduleDetailMessageId = msgId
                                                        scheduleDetailEventId = localEventId
                                                        scheduleDetailEvent = detail
                                                    }
                                                } catch {
                                                    await MainActor.run {
                                                        scheduleDetailMessageId = msgId
                                                        scheduleDetailEventId = localEventId
                                                        scheduleDetailEvent = event
                                                    }
                                                }
                                            } else {
                                                await MainActor.run {
                                                    scheduleDetailMessageId = msgId
                                                    scheduleDetailEventId = localEventId
                                                    scheduleDetailEvent = event
                                                }
                                            }
                                        }
                                    })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: -chatCardVisualLeadingCompensation)
                                    
                                case .contactCards:
                                    ContactCardStackView(contacts: Binding(
                                        get: {
                                            guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }),
                                                  let sIndex = appState.chatMessages[mIndex].segments?.firstIndex(where: { $0.id == seg.id })
                                            else { return [] }
                                            return appState.chatMessages[mIndex].segments?[sIndex].contacts ?? []
                                        },
                                        set: { newValue in
                                            guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                            var m = appState.chatMessages[mIndex]
                                            guard var segs = m.segments,
                                                  let sIndex = segs.firstIndex(where: { $0.id == seg.id })
                                            else { return }
                                            segs[sIndex].contacts = newValue
                                            m.segments = segs
                                            rebuildAggregatesFromSegments(segs, into: &m)
                                            appState.chatMessages[mIndex] = m
                                        }
                                    ), isParentScrollDisabled: $isCardHorizontalPaging,
                                    onOpenDetail: { card in
                                        selectedContact = findOrCreateContact(from: card)
                                    }, onDeleteRequest: { card in
                                        Task { @MainActor in
                                            await appState.softDeleteContactCard(card, modelContext: modelContext)
                                        }
                                    })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: -chatCardVisualLeadingCompensation)
                                    
                                case .invoiceCards:
                                    EmptyView()
                                    
                                case .meetingCards:
                                    MeetingSummaryCardStackView(meetings: Binding(
                                        get: {
                                            guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }),
                                                  let sIndex = appState.chatMessages[mIndex].segments?.firstIndex(where: { $0.id == seg.id })
                                            else { return [] }
                                            return appState.chatMessages[mIndex].segments?[sIndex].meetings ?? []
                                        },
                                        set: { newValue in
                                            guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                            var m = appState.chatMessages[mIndex]
                                            guard var segs = m.segments,
                                                  let sIndex = segs.firstIndex(where: { $0.id == seg.id })
                                            else { return }
                                            segs[sIndex].meetings = newValue
                                            m.segments = segs
                                            rebuildAggregatesFromSegments(segs, into: &m)
                                            appState.chatMessages[mIndex] = m
                                        }
                                    ), isParentScrollDisabled: $isCardHorizontalPaging,
                                    onDeleteRequest: { meeting in
                                        guard let mIndex = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                        withAnimation {
                                            var m = appState.chatMessages[mIndex]
                                            guard var segs = m.segments,
                                                  let sIndex = segs.firstIndex(where: { $0.id == seg.id })
                                            else { return }
                                            segs[sIndex].meetings?.removeAll(where: { $0.id == meeting.id })
                                            m.segments = segs
                                            rebuildAggregatesFromSegments(segs, into: &m)
                                            appState.chatMessages[mIndex] = m
                                            appState.saveMessageToStorage(m, modelContext: modelContext)
                                        }
                                    }, onOpenDetail: { meeting in
                                        meetingDetailSelection = MeetingDetailSelection(messageId: message.id, meetingId: meeting.id)
                                    })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: -chatCardVisualLeadingCompensation)
                                }
                            }
                            
                            let m = appState.chatMessages[msgIndex]
                            let isFinished: Bool = {
                                if m.streamingState.isActive { return false }
                                switch m.streamingState {
                                case .completed, .error:
                                    return true
                                case .idle:
                                    return m.isInterrupted
                                case .streaming:
                                    return false
                                }
                            }()
                            let shouldShowMessageActions = isFinished && !(m.isScheduleToolRunning || m.isContactToolRunning)
                            if shouldShowMessageActions {
                                MessageActionButtons(messageId: message.id)
                                    .padding(.top, 4)
                            }
                        } else {
                            // 没有分段：展示文本（或思考中占位）
                            // 注意：后端可能会先返回 task_id / tool start，但还没有 markdown/card 段。
                            // 这时 content 仍为空，直接显示“正在思考...”会让用户误以为没在干活。
                            // 这里优先用 tool 中间态展示“骨架卡片”，把等待可视化。
                            if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && appState.isAgentTyping
                                && (message.isScheduleToolRunning || message.isContactToolRunning) {
                                
                                VStack(alignment: .leading, spacing: 14) {
                                    if message.isScheduleToolRunning {
                                        ScheduleCardLoadingStackView(isParentScrollDisabled: $isCardHorizontalPaging)
                                            .offset(x: -chatCardVisualLeadingCompensation)
                                    }
                                    if message.isContactToolRunning {
                                        ContactCardLoadingStackView(isParentScrollDisabled: $isCardHorizontalPaging)
                                            .offset(x: -chatCardVisualLeadingCompensation)
                                    }
                                }
                            } else {
                                let text = (message.content.isEmpty && appState.isAgentTyping) ? "正在思考..." : message.content
                                let shouldAnimate = (
                                    (isLatestAgentMessage
                                     && message.streamingState.isActive
                                     && (text != "正在思考..."))
                                    ||
                                    (appState.pendingAnimatedAgentMessageId == message.id
                                     && (text != "正在思考..."))
                                )
                                AIBubble(
                                    text: text,
                                    messageId: message.id,
                                    shouldAnimate: shouldAnimate,
                                    showActionButtons: false,
                                    isInterrupted: message.isInterrupted,
                                    onTypingCompleted: {
                                        guard appState.pendingAnimatedAgentMessageId == message.id else { return }
                                        guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                        appState.chatMessages[idx].streamingState = .completed
                                        appState.pendingAnimatedAgentMessageId = nil
                                        appState.saveMessageToStorage(appState.chatMessages[idx], modelContext: modelContext)
                                    }
                                )

                                // ✅ 兼容历史记录：当 segments=nil 时，仍然渲染聚合卡片字段（这些字段会从 SwiftData 的 card batch 回填）
                                if let scheduleEvents = message.scheduleEvents, !scheduleEvents.isEmpty {
                                    ScheduleCardStackView(events: Binding(
                                        get: {
                                            guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return [] }
                                            return appState.chatMessages[idx].scheduleEvents ?? []
                                        },
                                        set: { newValue in
                                            guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                            appState.chatMessages[idx].scheduleEvents = newValue.isEmpty ? nil : newValue
                                            appState.saveMessageToStorage(appState.chatMessages[idx], modelContext: modelContext)
                                        }
                                    ), isParentScrollDisabled: $isCardHorizontalPaging, onDeleteRequest: { event in
                                        self.eventToDelete = event
                                        self.messageIdToDeleteFrom = message.id
                                        withAnimation { self.showDeleteConfirmation = true }
                                    }, onOpenDetail: { event in
                                        // 历史回填的卡片可能没有分段定位，直接走 selection；详情页会按 event.id / remoteId 拉取
                                        scheduleDetailMessageId = message.id
                                        scheduleDetailEventId = event.id
                                        scheduleDetailEvent = event
                                    })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: -chatCardVisualLeadingCompensation)
                                }

                                if let contacts = message.contacts, !contacts.isEmpty {
                                    ContactCardStackView(contacts: Binding(
                                        get: {
                                            guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return [] }
                                            return appState.chatMessages[idx].contacts ?? []
                                        },
                                        set: { newValue in
                                            guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                            appState.chatMessages[idx].contacts = newValue.isEmpty ? nil : newValue
                                            appState.saveMessageToStorage(appState.chatMessages[idx], modelContext: modelContext)
                                        }
                                    ), isParentScrollDisabled: $isCardHorizontalPaging,
                                    onOpenDetail: { card in
                                        selectedContact = findOrCreateContact(from: card)
                                    }, onDeleteRequest: { card in
                                        Task { @MainActor in
                                            await appState.softDeleteContactCard(card, modelContext: modelContext)
                                        }
                                    })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: -chatCardVisualLeadingCompensation)
                                }

                                if let meetings = message.meetings, !meetings.isEmpty {
                                    MeetingSummaryCardStackView(meetings: Binding(
                                        get: {
                                            guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return [] }
                                            return appState.chatMessages[idx].meetings ?? []
                                        },
                                        set: { newValue in
                                            guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                            appState.chatMessages[idx].meetings = newValue.isEmpty ? nil : newValue
                                            appState.saveMessageToStorage(appState.chatMessages[idx], modelContext: modelContext)
                                        }
                                    ), isParentScrollDisabled: $isCardHorizontalPaging,
                                    onDeleteRequest: { meeting in
                                        guard let idx = appState.chatMessages.firstIndex(where: { $0.id == message.id }) else { return }
                                        withAnimation {
                                            appState.chatMessages[idx].meetings?.removeAll(where: { $0.id == meeting.id })
                                            if (appState.chatMessages[idx].meetings ?? []).isEmpty { appState.chatMessages[idx].meetings = nil }
                                            appState.saveMessageToStorage(appState.chatMessages[idx], modelContext: modelContext)
                                        }
                                    }, onOpenDetail: { meeting in
                                        meetingDetailSelection = MeetingDetailSelection(messageId: message.id, meetingId: meeting.id)
                                    })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: -chatCardVisualLeadingCompensation)
                                }
                                
                                let isFinished: Bool = {
                                    if message.streamingState.isActive { return false }
                                    switch message.streamingState {
                                    case .completed, .error:
                                        return true
                                    case .idle:
                                        return message.isInterrupted
                                    case .streaming:
                                        return false
                                    }
                                }()
                                let shouldShowMessageActions = isFinished && !(message.isScheduleToolRunning || message.isContactToolRunning)
                                if shouldShowMessageActions {
                                    MessageActionButtons(messageId: message.id)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .id(message.id)
                }
            }

            // ✅ 快捷指令录音：聊天室内显示“录音中卡片”（与会议纪要页同一录音通路）
            if meetingRecordingManager.isRecording {
                ChatMeetingRecordingCardView(recordingManager: meetingRecordingManager) {
                    appState.stopRecordingAndShowGenerating(modelContext: modelContext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: -chatCardVisualLeadingCompensation)
                .id("liveRecordingCard")
            }
            
            // 锚点
            Color.clear
                .frame(height: 1)
                .id("bottomID")
        }
    }
    
    // MARK: - Helper Methods
    
    /// 自动滚动到“最新位置”（统一滚到底部锚点，确保最后一条是用户消息时也能到最底）
    private func scrollToLatestMessageOnOpen(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo("bottomID", anchor: .bottom)
            }
        }
    }

    /// 封装发送单条聊天消息（可被引导完成后复用）
    private func sendChatMessage(text: String, images: [UIImage] = [], isGreeting: Bool = false) {
        ChatSendFlow.send(
            appState: appState,
            modelContext: modelContext,
            text: text,
            images: images,
            isGreeting: isGreeting
        )
    }
}

#if DEBUG
@MainActor
private enum DebugProbe {
    private static var lastPrintAt: [String: Date] = [:]
    
    static func log(_ message: String) {
    }
    
    static func throttled(_ key: String, interval: TimeInterval, _ block: () -> Void) {
        let now = Date()
        if let last = lastPrintAt[key], now.timeIntervalSince(last) < interval {
            return
        }
        lastPrintAt[key] = now
        block()
    }
}
#endif

// MARK: - Subviews

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
                Text(displayedText)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "333333"))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: ScreenMetrics.width * 0.85, alignment: .leading)
            } else {
                UserBubble(
                    message: ChatMessage(role: .user, content: displayedText),
                    onOpenImage: { _, _ in }
                )
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
    /// 是否启用打字机效果（必须由上层保证：仅最新 AI 气泡为 true）
    var shouldAnimate: Bool = false
    var showActionButtons: Bool = true // 控制是否显示操作按钮
    var isInterrupted: Bool = false // 是否被中断
    var onTypingCompleted: (() -> Void)? = nil
    
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    @State private var displayedText: String = ""
    @State private var isCompleted: Bool = false
    @State private var timer: Timer?
    
    var body: some View {
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
            if showActionButtons {
                HStack(alignment: .center, spacing: 12) {
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
                .opacity(isCompleted ? 1 : 0)
            }
        }
        .frame(maxWidth: ScreenMetrics.width * 0.85, alignment: .leading)
        .onAppear {
            // 历史消息：永远不触发打字机（避免 ScrollView 复用导致“滑到哪里打到哪里”）
            guard shouldAnimate else {
                renderImmediately(with: text, notify: false)
                return
            }
            // 最新消息：根据当前状态继续/补齐
            if isInterrupted {
                renderImmediately(with: text, notify: true)
            } else {
                applyAnimatedTextChange(text)
            }
        }
        .onChange(of: isInterrupted) { _, newValue in
            if newValue {
                // 被中断：立即显示完整文本，且结束本次打字机
                renderImmediately(with: text, notify: true)
            }
        }
        .onChange(of: text) { _, newValue in
            // 历史消息：文本变化（比如刷新/合并）也直接渲染，不走打字机
            guard shouldAnimate else {
                renderImmediately(with: newValue, notify: false)
                return
            }
            guard !isInterrupted else {
                renderImmediately(with: newValue, notify: true)
                return
            }
            applyAnimatedTextChange(newValue)
        }
        .onDisappear {
            // 只有最新气泡才有 timer；离屏停止，避免后台跑计时器
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
        appState.chatMessages[currentIndex].segments = nil
        appState.chatMessages[currentIndex].scheduleEvents = nil
        appState.chatMessages[currentIndex].contacts = nil
        appState.chatMessages[currentIndex].invoices = nil
        appState.chatMessages[currentIndex].meetings = nil
        appState.chatMessages[currentIndex].streamingState = .idle
        
        // 重新调用API
        appState.isAgentTyping = true
        appState.startStreaming(messageId: messageId)
        appState.currentGenerationTask = Task {
            await SmartModelRouter.sendMessageStream(
                messages: Array(appState.chatMessages.prefix(currentIndex)), // 只包含当前消息之前的消息
                mode: appState.currentMode,
                onStructuredOutput: { output in
                    Task { @MainActor in
                        appState.applyStructuredOutput(output, to: messageId, modelContext: modelContext)
                    }
                },
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
                    Task { @MainActor in
                        appState.handleStreamingError(error, for: messageId)
                        appState.isAgentTyping = false
                    }
                }
            )
        }
    }
    
    private func resetAndStartTypewriter(with newText: String, startAt startIndex: Int = 0) {
        timer?.invalidate()
        timer = nil
        isCompleted = false
        
        let chars = Array(newText)
        guard !chars.isEmpty else { return }
        
        // 从指定下标继续（用于“只补齐新增尾部”）
        var idx = max(0, min(startIndex, chars.count))
        if idx == 0 {
            // 先立即显示第一个字符，避免闪一下空白
            displayedText = String(chars[0])
            idx = 1
        } else {
            // 保证 displayedText 至少是 prefix
            displayedText = String(chars.prefix(idx))
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            if idx < chars.count {
                displayedText.append(chars[idx])
                idx += 1
                if idx % 2 == 0 { HapticFeedback.soft() }
            } else {
                t.invalidate()
                timer = nil
                isCompleted = true
                onTypingCompleted?()
            }
        }
    }
    
    private func renderImmediately(with newText: String, notify: Bool) {
        timer?.invalidate()
        timer = nil
        displayedText = newText
        isCompleted = true
        if notify { onTypingCompleted?() }
    }

    /// 最新气泡：尽量“增量补齐”，避免每次 text 变化都从头打字。
    private func applyAnimatedTextChange(_ newText: String) {
        let trimmed = newText
        guard !trimmed.isEmpty else {
            // 空文本不启动
            displayedText = ""
            isCompleted = false
            timer?.invalidate()
            timer = nil
            return
        }

        // 已完成且一致：不重复触发
        if isCompleted && displayedText == trimmed { return }

        // 如果新文本以当前已显示内容为前缀：只补齐新增尾部
        if !displayedText.isEmpty, trimmed.hasPrefix(displayedText) {
            let start = displayedText.count
            resetAndStartTypewriter(with: trimmed, startAt: start)
            return
        }

        // 兜底：从头开始（例如文本被整体替换）
        displayedText = ""
        resetAndStartTypewriter(with: trimmed, startAt: 0)
    }
}

// 标准用户气泡
struct UserBubble: View {
    let message: ChatMessage
    let onOpenImage: (UIImage, CGRect) -> Void
    
    private let messageImageSize: CGFloat = 120
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 40) // 确保左侧有足够空间
            
            VStack(alignment: .trailing, spacing: 8) {
                if !message.images.isEmpty {
                    ForEach(Array(message.images.enumerated()), id: \.offset) { index, image in
                        ChatImageThumbnail(
                            image: image,
                            size: messageImageSize,
                            onTap: { rect in
                                onOpenImage(image, rect)
                            }
                        )
                    }
                }
                
                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(message.content)
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
            .frame(maxWidth: ScreenMetrics.width * 0.80, alignment: .trailing)
        }
    }
}

// 移除了不再使用的 FullscreenImagePreview，改用 SharedComponents 里的 FullScreenImageView

private struct ChatImageThumbnail: View {
    let image: UIImage
    let size: CGFloat
    let onTap: (CGRect) -> Void
    
    @State private var rect: CGRect = .zero
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .cornerRadius(12)
            .clipped()
            .contentShape(Rectangle())
            .getRect($rect)
            .onTapGesture {
                // 这里的 rect 是 global 坐标；用于 Hero 动画
                onTap(rect)
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

// MARK: - 聊天记录搜索
private struct ChatSearchView: View {
    let messages: [ChatMessage]
    let onSelect: (UUID) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    
    private var results: [ChatMessage] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return messages.filter { m in
            !m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            m.content.localizedCaseInsensitiveContains(q)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入关键词搜索聊天记录")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                } else if results.isEmpty {
                    Text("没有找到匹配内容")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(results) { m in
                        Button {
                            HapticFeedback.light()
                            onSelect(m.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(m.role == .user ? "我" : "圆圆")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Text(m.content)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索聊天内容")
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
        
        // 如果有会议纪要卡片，添加卡片信息
        if let meetings = message.meetings, !meetings.isEmpty {
            textToCopy += "\n\n会议纪要：\n"
            for (index, meeting) in meetings.enumerated() {
                textToCopy += "\n\(index + 1). \(meeting.title)\n"
                textToCopy += "   时间：\(meeting.formattedDate)\n"
                textToCopy += "   摘要：\(meeting.summary)\n"
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
        appState.chatMessages[currentIndex].segments = nil
        appState.chatMessages[currentIndex].scheduleEvents = nil
        appState.chatMessages[currentIndex].contacts = nil
        appState.chatMessages[currentIndex].invoices = nil
        appState.chatMessages[currentIndex].meetings = nil
        appState.chatMessages[currentIndex].streamingState = .idle
        
        // 重新调用API
        appState.isAgentTyping = true
        appState.startStreaming(messageId: messageId)
        appState.currentGenerationTask = Task {
            await SmartModelRouter.sendMessageStream(
                messages: Array(appState.chatMessages.prefix(currentIndex)), // 只包含当前消息之前的消息
                mode: appState.currentMode,
                onStructuredOutput: { output in
                    DispatchQueue.main.async {
                        appState.applyStructuredOutput(output, to: messageId, modelContext: modelContext)
                    }
                },
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
                    DispatchQueue.main.async {
                        appState.handleStreamingError(error, for: messageId)
                        appState.isAgentTyping = false
                    }
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
        let topLeftRadius: CGFloat = myRole == .agent ? 4 : 12
        let topRightRadius: CGFloat = 12
        let bottomLeftRadius: CGFloat = 12
        let bottomRightRadius: CGFloat = 12
        
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

// MARK: - Helper Shape for Rounded Corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
