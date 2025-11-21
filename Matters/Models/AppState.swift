import SwiftUI
import Combine
import SwiftData

// MARK: - 枚举类型

// 底部按钮类型
enum BottomButtonType: Int, CaseIterable {
    case text = 0
    case menu = 1
    
    var icon: String {
        switch self {
        case .text: return "text.bubble.fill"
        case .menu: return "list.bullet"
        }
    }
    
    var title: String {
        switch self {
        case .text: return "文字"
        case .menu: return "目录"
        }
    }
}

// 目录子按钮类型
enum MenuButtonType: Int, CaseIterable {
    case todos = 0
    case contacts = 1
    case reimbursement = 2
    case meeting = 3
    
    var icon: String {
        switch self {
        case .todos: return "checklist"
        case .contacts: return "person.2.fill"
        case .reimbursement: return "dollarsign.circle.fill"
        case .meeting: return "mic.circle.fill"
        }
    }
    
    var title: String {
        switch self {
        case .todos: return "待办"
        case .contacts: return "人脉"
        case .reimbursement: return "报销"
        case .meeting: return "会议"
        }
    }
}

// 模式类型
enum AppMode: String, CaseIterable {
    case work = "工作模式"
    case emotion = "情感模式"
}

// 流式消息状态
enum StreamingState: Equatable {
    case idle
    case streaming
    case completed
    case error(String)
    
    var isActive: Bool {
        if case .streaming = self {
            return true
        }
        return false
    }
}

// 待处理操作类型
enum PendingActionType: Equatable {
    case imageAnalysis
    case textAnalysis
}

// 截图分类结果
enum ScreenshotCategory: String {
    case todo = "待办"
    case expense = "报销"
    case contact = "人脉"
    case unknown = "未知"

    var appMode: AppMode {
        return .work  // 所有截图分析都使用工作模式
    }
}

// MARK: - 预览数据结构

// 待办预览数据
struct TodoPreviewData: Equatable {
    var title: String
    var description: String
    var startTime: Date
    var endTime: Date
    var reminderTime: Date
    var imageData: Data
}

// 人脉预览数据
struct ContactPreviewData: Equatable {
    var name: String
    var phoneNumber: String?
    var company: String?
    var identity: String?
    var hobbies: String?
    var relationship: String?
    var avatarData: Data?
    var imageData: Data
    var isEditMode: Bool
    var existingContactId: UUID?
}

// 报销预览数据
struct ExpensePreviewData: Equatable {
    var amount: Double
    var title: String
    var category: String?
    var event: String?  // 事件（报销项目发生情形）
    var occurredAt: Date
    var notes: String?
    var imageData: [Data]  // 支持多张图片
}

// MARK: - 聊天消息

// 聊天消息
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    
    var content: String
    var streamingState: StreamingState = .idle
    var timestamp: Date
    var isGreeting: Bool = false
    var messageType: MessageType = .text
    var images: [UIImage] = []
    var pendingAction: PendingActionType? = nil
    var showActionButtons: Bool = false
    var todoPreview: TodoPreviewData? = nil
    var contactPreview: ContactPreviewData? = nil
    var expensePreview: ExpensePreviewData? = nil
    var notes: String? = nil  // 临时存储数据（如待处理的报销信息）
    var showIntentSelection: Bool = false  // 是否显示意图选择器
    var isWrongClassification: Bool = false  // 是否是错误识别（用于"识别错了"按钮）
    var showReclassifyBubble: Bool = false  // 是否显示重新分类气泡
    
    enum MessageRole {
        case user
        case agent
    }
    
    enum MessageType {
        case text
        case image
        case mixed
    }
    
    var displayedContent: String {
        return content
    }
    
    var isStreaming: Bool {
        return streamingState.isActive
    }
    
    // 文字消息初始化
    init(role: MessageRole, content: String, isGreeting: Bool = false, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.isGreeting = isGreeting
        self.messageType = .text
        self.timestamp = timestamp
        self.streamingState = role == .user ? .completed : (content.isEmpty ? .idle : .completed)
    }
    
    // 图片消息初始化
    init(role: MessageRole, images: [UIImage], content: String = "", timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.images = images
        self.messageType = content.isEmpty ? .image : .mixed
        self.timestamp = timestamp
        self.streamingState = .completed
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.streamingState == rhs.streamingState &&
        lhs.images.count == rhs.images.count &&
        lhs.pendingAction == rhs.pendingAction &&
        lhs.showActionButtons == rhs.showActionButtons &&
        lhs.todoPreview == rhs.todoPreview &&
        lhs.contactPreview == rhs.contactPreview &&
        lhs.expensePreview == rhs.expensePreview &&
        lhs.showIntentSelection == rhs.showIntentSelection &&
        lhs.isWrongClassification == rhs.isWrongClassification &&
        lhs.showReclassifyBubble == rhs.showReclassifyBubble
    }
}

// MARK: - 流式消息管理器

struct StreamingMessageManager {
    static func startStreaming(messageId: UUID, in messages: inout [ChatMessage]) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.streamingState = .streaming
            messages[index] = updatedMessage
        }
    }
    
    static func appendChunk(_ chunk: String, to messageId: UUID, in messages: inout [ChatMessage]) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.content += chunk
            updatedMessage.streamingState = .streaming
            messages[index] = updatedMessage
        }
    }
    
    static func completeStreaming(messageId: UUID, in messages: inout [ChatMessage]) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.streamingState = .completed
            messages[index] = updatedMessage
        }
    }
    
    static func handleError(_ error: Error, for messageId: UUID, in messages: inout [ChatMessage]) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.streamingState = .error(error.localizedDescription)
            if updatedMessage.content.isEmpty {
                updatedMessage.content = "抱歉，没有收到AI的回复内容"
            }
            messages[index] = updatedMessage
        }
    }
    
    static func handleError(_ errorMessage: String, for messageId: UUID, in messages: inout [ChatMessage]) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.streamingState = .error(errorMessage)
            if updatedMessage.content.isEmpty {
                updatedMessage.content = "抱歉，没有收到AI的回复内容"
            }
            messages[index] = updatedMessage
        }
    }
}

// MARK: - 应用状态管理

// 应用状态管理 - 管理主页和聊天室状态
class AppState: ObservableObject {
    // 界面状态
    @Published var isMenuExpanded: Bool = false
    @Published var showChatRoom: Bool = false  // 控制是否显示聊天室
    @Published var showSettings: Bool = false  // 控制是否显示设置页面
    @Published var showTodoList: Bool = false  // 控制是否显示待办列表
    @Published var showContactList: Bool = false  // 控制是否显示人脉列表
    @Published var showExpenseList: Bool = false  // 控制是否显示报销列表
    @Published var showMeetingList: Bool = false  // 控制是否显示会议纪要列表
    @Published var scrollToContactId: UUID? = nil  // 需要滚动到的联系人ID
    @Published var showLiveRecording: Bool = false  // 控制是否显示实时录音界面

    // 选中的按钮
    @Published var selectedBottomButton: BottomButtonType? = nil
    
    // 当前模式
    @Published var currentMode: AppMode = .work
    
    // 星球动画状态
    @Published var planetScale: CGFloat = 1.0
    @Published var planetRotation: Double = 0
    @Published var planetPulse: Bool = false
    
    // 首次显示标记
    @Published var isFirstAppearance: Bool = true
    
    // AI生成的打招呼
    @Published var aiGreeting: String = ""
    @Published var displayedGreeting: String = ""  // 用于打字效果显示的文字
    @Published var isGeneratingGreeting: Bool = false
    
    // 聊天室状态 - 保存对话历史
    @Published var chatMessages: [ChatMessage] = []
    @Published var isAgentTyping: Bool = false
    @Published var selectedImages: [UIImage] = []
    @Published var shouldAddGreeting: Bool = false  // 标记是否需要添加打招呼
    @Published var pendingScreenshot: UIImage? = nil  // 待发送的截图（已废弃，现在用shouldSendClipboardImage）
    @Published var shouldSendClipboardImage: Bool = false  // 标记是否需要从剪贴板发送截图
    @Published var screenshotCategory: ScreenshotCategory? = nil  // 截图预分类结果
    @Published var isLoadingOlderMessages: Bool = false  // 是否正在加载更早的消息
    
    // 打字机效果控制
    @Published var isTyping: Bool = false
    private var typingTask: Task<Void, Never>?
    
    // 打字机效果 - 只用于主页打招呼
    func typeText(_ text: String, speed: TimeInterval = 0.05) {
        typingTask?.cancel()
        displayedGreeting = ""
        isTyping = true
        
        typingTask = Task {
            var charCount = 0
            for char in text {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    displayedGreeting.append(char)
                    // 每2个字符触发一次轻微震动，营造有节奏的打字感
                    if charCount % 2 == 0 {
                        HapticFeedback.soft()
                    }
                }
                
                charCount += 1
                try? await Task.sleep(nanoseconds: UInt64(speed * 1_000_000_000))
            }
            
            await MainActor.run {
                isTyping = false
            }
        }
    }
    
    func cancelTyping() {
        typingTask?.cancel()
        isTyping = false
    }
    
    // MARK: - 截图处理（从相册）

    /// 触发截图分析流程 - 打开聊天室并从相册发送最近一张照片
    /// - Parameter category: 预分类结果（可选）
    func handleScreenshotFromClipboard(category: ScreenshotCategory? = nil) {
        print("🔍 触发截图分析流程（从相册获取最近照片）")
        if let category = category {
            print("📊 预分类结果: \(category.rawValue)")
        }

        // 保存预分类结果
        screenshotCategory = category

        // 设置标记，让聊天室知道需要从相册发送截图
        shouldSendClipboardImage = true

        // 根据分类结果设置模式
        if let category = category {
            currentMode = category.appMode
        }

        // 打开聊天室
        showChatRoom = true
        print("✅ 已打开聊天室，标记已设置: shouldSendClipboardImage = true")
    }
    
    // MARK: - 聊天室流式更新方法
    private let typingInterval: UInt64 = 15_000_000  // 15ms打字速度
    
    /// 开始流式接收
    func startStreaming(messageId: UUID) {
        objectWillChange.send()
        StreamingMessageManager.startStreaming(messageId: messageId, in: &chatMessages)
    }

    /// 追加流式内容块
    func appendChunk(_ chunk: String, to messageId: UUID) {
        objectWillChange.send()
        StreamingMessageManager.appendChunk(chunk, to: messageId, in: &chatMessages)
    }

    /// 完成流式接收
    func completeStreaming(messageId: UUID) {
        objectWillChange.send()
        StreamingMessageManager.completeStreaming(messageId: messageId, in: &chatMessages)
    }

    /// 播放完整响应 - 逐字显示，优化索引查找
    func playResponse(_ content: String, for messageId: UUID) async {
        print("🎬 开始播放响应，内容长度: \(content.count)")
        
        // 立即隐藏 typing indicator，避免出现两个头像
        isAgentTyping = false
        
        // 一次性查找并缓存索引，避免循环中重复查找
        guard let messageIndex = chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("⚠️ 找不到消息ID: \(messageId)")
            return
        }
        
        print("✅ 找到消息，索引: \(messageIndex)，当前内容: \(chatMessages[messageIndex].content)")

        // 如果内容为空，显示错误提示
        guard !content.isEmpty else {
            print("⚠️ 收到空内容")
            await MainActor.run {
                var updatedMessage = chatMessages[messageIndex]
                updatedMessage.content = "抱歉，没有收到AI的回复内容"
                updatedMessage.streamingState = .error("空响应")
                chatMessages[messageIndex] = updatedMessage
            }
            return
        }

        var accumulatedText = ""
        var charCount = 0

        // 逐字符显示，每次更新都刷新
        for char in content {
            accumulatedText.append(char)
            charCount += 1

            // 直接使用缓存的索引更新，避免重复查找
            await MainActor.run {
                // 确保索引仍然有效（简单边界检查）
                guard messageIndex < chatMessages.count else {
                    print("⚠️ 播放中消息索引失效")
                    return
                }
                
                // 直接更新消息内容，使用缓存的索引
                var updatedMessage = chatMessages[messageIndex]
                updatedMessage.content = accumulatedText
                chatMessages[messageIndex] = updatedMessage
            }
            
            // 每2个字符触发一次轻微震动
            if charCount % 2 == 0 {
                await MainActor.run {
                    HapticFeedback.soft()
                }
            }
            
            // 字符间隔延迟
            try? await Task.sleep(nanoseconds: typingInterval)
        }

        // 最终更新：确保显示完整内容
        await MainActor.run {
            guard messageIndex < chatMessages.count else {
                print("⚠️ 最终更新时消息索引失效")
                return
            }
            
            var updatedMessage = chatMessages[messageIndex]
            updatedMessage.content = content
            updatedMessage.streamingState = .completed
            chatMessages[messageIndex] = updatedMessage
            print("✅ 消息状态已更新为completed")
            
            // 播放完成时触发一次成功反馈
            HapticFeedback.success()
        }
    }

    /// 处理流式错误
    func handleStreamingError(_ error: Error, for messageId: UUID) {
        objectWillChange.send()
        StreamingMessageManager.handleError(error, for: messageId, in: &chatMessages)
    }

    /// 处理流式错误（字符串版本）
    func handleStreamingError(_ errorMessage: String, for messageId: UUID) {
        objectWillChange.send()
        StreamingMessageManager.handleError(errorMessage, for: messageId, in: &chatMessages)
    }
    
    // MARK: - SwiftData 持久化方法
    
    /// 从本地存储加载聊天记录
    func loadMessagesFromStorage(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PersistentChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            let persistentMessages = try modelContext.fetch(descriptor)
            let loadedMessages = persistentMessages.map { $0.toChatMessage() }
            
            DispatchQueue.main.async {
                self.chatMessages = loadedMessages
                print("✅ 从本地加载了 \(loadedMessages.count) 条聊天记录")
            }
        } catch {
            print("⚠️ 加载聊天记录失败: \(error)")
        }
    }
    
    /// 保存单条消息到本地存储
    func saveMessageToStorage(_ message: ChatMessage, modelContext: ModelContext) {
        let persistentMessage = PersistentChatMessage.from(message)
        modelContext.insert(persistentMessage)
        
        do {
            try modelContext.save()
            print("✅ 消息已保存到本地: \(message.content.prefix(20))...")
        } catch {
            print("⚠️ 保存消息失败: \(error)")
        }
    }
    
    /// 批次加载更早的消息（每次50条）
    func loadOlderMessages(modelContext: ModelContext, before timestamp: Date, limit: Int = 50) {
        guard !isLoadingOlderMessages else { return }

        isLoadingOlderMessages = true

        var descriptor = FetchDescriptor<PersistentChatMessage>(
            predicate: #Predicate<PersistentChatMessage> { message in
                message.timestamp < timestamp
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            let persistentMessages = try modelContext.fetch(descriptor)
            let olderMessages = persistentMessages.map { $0.toChatMessage() }.reversed()

            DispatchQueue.main.async {
                if !olderMessages.isEmpty {
                    // 因为消息是按时间从早到晚排序的，更早的消息应该插入到最前面
                    // olderMessages 中的所有消息都比 timestamp 早，所以直接插入到索引0
                    self.chatMessages.insert(contentsOf: olderMessages, at: 0)
                    print("✅ 加载了 \(olderMessages.count) 条更早的消息，已插入到最前面")
                    print("   - 最早消息时间: \(olderMessages.first?.timestamp ?? Date())")
                    print("   - 最晚消息时间: \(olderMessages.last?.timestamp ?? Date())")
                    print("   - 当前总消息数: \(self.chatMessages.count)")
                } else {
                    print("ℹ️ 没有更早的消息了")
                }
                self.isLoadingOlderMessages = false
            }
        } catch {
            print("⚠️ 加载更早消息失败: \(error)")
            DispatchQueue.main.async {
                self.isLoadingOlderMessages = false
            }
        }
    }

    /// 异步加载最近的 N 条消息（懒加载）
    func loadRecentMessages(modelContext: ModelContext, limit: Int = 50) async {
        print("🚀 开始异步加载最近 \(limit) 条消息...")

        // 在后台线程执行数据库查询
        let result = await Task.detached {
            var descriptor = FetchDescriptor<PersistentChatMessage>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = limit

            do {
                let persistentMessages = try modelContext.fetch(descriptor)
                // 反转顺序，使最早的消息在前面
                let loadedMessages = persistentMessages.reversed().map { $0.toChatMessage() }
                return (loadedMessages, nil as Error?)
            } catch {
                return ([ChatMessage](), error)
            }
        }.value

        // 在主线程更新 UI
        await MainActor.run {
            if let error = result.1 {
                print("⚠️ 加载最近消息失败: \(error)")
            } else {
                self.chatMessages = result.0
                print("✅ 异步加载了 \(result.0.count) 条最近的消息")
            }
        }
    }

    /// 清空所有聊天记录（从内存和本地存储）
    func clearAllMessages(modelContext: ModelContext) {
        // 清空内存中的消息
        chatMessages.removeAll()
        
        // 清空本地存储
        do {
            try modelContext.delete(model: PersistentChatMessage.self)
            try modelContext.save()
            print("✅ 已清空所有聊天记录")
        } catch {
            print("⚠️ 清空聊天记录失败: \(error)")
        }
    }
    
    // MARK: - 每日总结管理
    
    /// 获取最近一天的历史卡片总结
    func getLatestDailySummary(modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<DailyChatSummary>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        do {
            let summaries = try modelContext.fetch(descriptor)
            // 返回最近一天的总结
            return summaries.first?.summary
        } catch {
            print("⚠️ 获取历史卡片失败: \(error)")
            return nil
        }
    }
    
    /// 更新当天的聊天总结
    func updateTodaySummary(modelContext: ModelContext) {
        Task {
            await generateAndSaveTodaySummary(modelContext: modelContext)
        }
    }
    
    /// 生成并保存当天的聊天总结
    private func generateAndSaveTodaySummary(modelContext: ModelContext) async {
        let today = DailyChatSummary.startOfDay(Date())
        
        // 获取当天的消息
        let todayMessages = chatMessages.filter { message in
            let messageDay = DailyChatSummary.startOfDay(message.timestamp)
            return messageDay == today
        }
        
        // 如果当天没有真实消息（排除打招呼），不生成总结
        let realMessages = todayMessages.filter { !$0.isGreeting }
        guard !realMessages.isEmpty else {
            print("ℹ️ 当天没有真实消息，跳过总结生成")
            return
        }
        
        print("🔄 开始生成当天总结 - 消息数: \(todayMessages.count), 真实消息: \(realMessages.count)")
        
        do {
            // 调用API生成总结
            let summaryText = try await QwenAPIService.generateDailySummary(
                messages: todayMessages,
                date: today
            )
            
            // 保存到数据库
            await MainActor.run {
                // 查找是否已存在当天的总结
                let descriptor = FetchDescriptor<DailyChatSummary>(
                    predicate: #Predicate<DailyChatSummary> { summary in
                        summary.date == today
                    }
                )
                
                do {
                    let existingSummaries = try modelContext.fetch(descriptor)
                    
                    if let existingSummary = existingSummaries.first {
                        // 更新现有总结
                        existingSummary.summary = summaryText
                        existingSummary.messageCount = realMessages.count
                        existingSummary.lastUpdated = Date()
                        print("✅ 已更新当天总结")
                    } else {
                        // 创建新总结
                        let newSummary = DailyChatSummary(
                            date: today,
                            summary: summaryText,
                            messageCount: realMessages.count,
                            lastUpdated: Date()
                        )
                        modelContext.insert(newSummary)
                        print("✅ 已创建当天总结")
                    }
                    
                    try modelContext.save()
                    print("✅ 总结已保存到数据库: \(summaryText)")
                } catch {
                    print("⚠️ 保存总结失败: \(error)")
                }
            }
        } catch {
            print("⚠️ 生成总结失败: \(error)")
        }
    }
}


