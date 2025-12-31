import SwiftUI
import Combine
import SwiftData

extension NSNotification.Name {
    /// 远端日程数据发生变更（创建/更新/删除）后广播，用于驱动 UI 强刷，避免被缓存挡住
    static let remoteScheduleDidChange = NSNotification.Name("RemoteScheduleDidChange")
}

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

// 日程卡片数据
struct ScheduleEvent: Identifiable, Equatable, Codable {
    var id = UUID()
    /// 后端 schedule id（字符串/数字/uuid 都可能）；用于拉取详情 `/api/v1/schedules/{id}`
    var remoteId: String? = nil
    var title: String
    var description: String
    var startTime: Date
    var endTime: Date
    /// 是否为全天日程（优先由后端 `full_day` 明确给出）
    /// - 全天展示语义：00:00 ~ 24:00（endTime 存为次日 00:00，但 UI 会展示为 24:00）
    var isFullDay: Bool = false
    /// 是否由后端明确给出结束时间（end_time 不为 null 且可解析）
    /// - 用于列表展示：避免 end_time=null 时误显示 “+1h”
    var endTimeProvided: Bool = true
    var isSynced: Bool = false
    var hasConflict: Bool = false
    
    // 用于显示的辅助属性
    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd EEEE"
        return formatter.string(from: startTime)
    }

    var day: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: startTime)
    }
    
    var monthYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy MMM"
        return formatter.string(from: startTime)
    }
    
    var weekDay: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: startTime)
    }
    
    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if isFullDay {
            return "00:00 ~ 24:00"
        }
        return "\(formatter.string(from: startTime)) ~ \(formatter.string(from: endTime))"
    }

    // MARK: - Codable（向后兼容：旧数据没有 isFullDay 字段）
    private enum CodingKeys: String, CodingKey {
        case id, remoteId, title, description, startTime, endTime, isFullDay, endTimeProvided, isSynced, hasConflict
    }

    init(
        id: UUID = UUID(),
        remoteId: String? = nil,
        title: String,
        description: String,
        startTime: Date,
        endTime: Date,
        isFullDay: Bool = false,
        endTimeProvided: Bool = true,
        isSynced: Bool = false,
        hasConflict: Bool = false
    ) {
        self.id = id
        self.remoteId = remoteId
        self.title = title
        self.description = description
        self.startTime = startTime
        self.endTime = endTime
        self.isFullDay = isFullDay
        self.endTimeProvided = endTimeProvided
        self.isSynced = isSynced
        self.hasConflict = hasConflict
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        remoteId = try c.decodeIfPresent(String.self, forKey: .remoteId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decode(Date.self, forKey: .endTime)
        isFullDay = try c.decodeIfPresent(Bool.self, forKey: .isFullDay) ?? false
        endTimeProvided = try c.decodeIfPresent(Bool.self, forKey: .endTimeProvided) ?? true
        isSynced = try c.decodeIfPresent(Bool.self, forKey: .isSynced) ?? false
        hasConflict = try c.decodeIfPresent(Bool.self, forKey: .hasConflict) ?? false
    }
}

// 人脉卡片数据
struct ContactCard: Identifiable, Equatable, Codable {
    var id = UUID()
    /// 后端 contact id（字符串/数字/uuid 都可能）；用于拉取详情 `/api/v1/contacts/{id}` 与更新/删除
    var remoteId: String? = nil
    var name: String
    var englishName: String?
    var company: String?
    var title: String? // 职位
    var phone: String?
    var email: String?
    /// 生日（后端字段可能为 birthday / birth / birthday_text 等；统一落到 string，UI 直接展示）
    var birthday: String? = nil
    /// 性别
    var gender: String? = nil
    /// 行业
    var industry: String? = nil
    /// 地区
    var location: String? = nil
    /// 与我关系（后端可能用 relationship_type）
    var relationshipType: String? = nil
    /// 后端可选：备注（用户/系统输入）
    var notes: String? = nil
    /// 后端可选：AI 画像/印象，期望落到联系人详情的“备注”里
    var impression: String? = nil
    var avatarData: Data? // 头像
    var rawImage: Data? // 原始截图
}

// 发票卡片数据
struct InvoiceCard: Identifiable, Equatable, Codable {
    var id = UUID()
    var invoiceNumber: String // 发票号码
    var merchantName: String  // 商户名称
    var amount: Double        // 金额
    var date: Date            // 开票日期
    var type: String          // 类型（餐饮、交通等）
    var notes: String?        // 备注
}

// 会议纪要卡片数据
struct MeetingCard: Identifiable, Equatable, Codable {
    var id = UUID()
    var remoteId: String? = nil  // 远程服务器ID
    var title: String
    var date: Date
    var summary: String
    var duration: TimeInterval?
    var audioPath: String?
    /// 后端返回的原始录音文件 URL（可用于下载到本地后播放）
    var audioRemoteURL: String? = nil
    var transcriptions: [MeetingTranscription]?
    /// 是否正在生成会议纪要（后端异步处理中）
    var isGenerating: Bool = false
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 录音时长展示（00:00:00），仅基于 meeting.duration（后端 audio_duration）
    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

struct MeetingTranscription: Identifiable, Equatable, Codable {
    var id = UUID()
    var speaker: String
    var time: String
    var content: String
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
    var id: UUID
    let role: MessageRole
    
    var content: String
    /// 按后端 JSON chunk 顺序的分段内容（用于“按 JSON 分段输出”渲染）
    /// - 仅运行态使用：当前 SwiftData 持久化仅保存 content/images
    var segments: [ChatSegment]? = nil
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
    var scheduleEvents: [ScheduleEvent]? = nil // 日程卡片列表
    var contacts: [ContactCard]? = nil // 人脉卡片列表
    var invoices: [InvoiceCard]? = nil // 发票卡片列表
    var meetings: [MeetingCard]? = nil // 会议纪要卡片列表
    var notes: String? = nil  // 临时存储数据（如待处理的报销信息）
    var isContactToolRunning: Bool = false // tool 中间态：用于联系人创建 loading
    var isScheduleToolRunning: Bool = false // tool 中间态：用于日程创建/更新 loading
    var showIntentSelection: Bool = false  // 是否显示意图选择器
    var isWrongClassification: Bool = false  // 是否是错误识别（用于"识别错了"按钮）
    var showReclassifyBubble: Bool = false  // 是否显示重新分类气泡
    var isInterrupted: Bool = false // 是否被中断
    var isLiveRecording: Bool = false // 是否是实时录音状态气泡
    
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
    init(id: UUID = UUID(), role: MessageRole, content: String, isGreeting: Bool = false, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.isGreeting = isGreeting
        self.messageType = .text
        self.timestamp = timestamp
        self.streamingState = role == .user ? .completed : (content.isEmpty ? .idle : .completed)
    }
    
    // 图片消息初始化
    init(id: UUID = UUID(), role: MessageRole, images: [UIImage], content: String = "", timestamp: Date = Date()) {
        self.id = id
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
        lhs.segments == rhs.segments &&
        lhs.streamingState == rhs.streamingState &&
        lhs.images.count == rhs.images.count &&
        lhs.pendingAction == rhs.pendingAction &&
        lhs.showActionButtons == rhs.showActionButtons &&
        lhs.todoPreview == rhs.todoPreview &&
        lhs.contactPreview == rhs.contactPreview &&
        lhs.expensePreview == rhs.expensePreview &&
        lhs.scheduleEvents == rhs.scheduleEvents &&
        lhs.contacts == rhs.contacts &&
        lhs.invoices == rhs.invoices &&
        lhs.meetings == rhs.meetings &&
        lhs.isContactToolRunning == rhs.isContactToolRunning &&
        lhs.isScheduleToolRunning == rhs.isScheduleToolRunning &&
        lhs.showIntentSelection == rhs.showIntentSelection &&
        lhs.isWrongClassification == rhs.isWrongClassification &&
        lhs.showReclassifyBubble == rhs.showReclassifyBubble &&
        lhs.isInterrupted == rhs.isInterrupted
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
@MainActor
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
    
    // 全局颜色选择（与主页调色板同步）
    @Published var colorIndex: Int = 0  // 默认雾蓝灰
    
    // 星球动画状态
    @Published var planetScale: CGFloat = 1.0
    @Published var planetRotation: Double = 0
    @Published var planetPulse: Bool = false
    
    // 首次显示标记
    @Published var isFirstAppearance: Bool = true
    
    // Session管理（app打开到关闭之间的聊天）
    @Published var sessionStartTime: Date = Date()  // 当前session开始时间
    
    // 聊天室状态 - 保存对话历史
    @Published var chatMessages: [ChatMessage] = []
    @Published var isAgentTyping: Bool = false
    @Published var selectedImages: [UIImage] = []
    @Published var shouldAddGreeting: Bool = false  // 标记是否需要添加打招呼
    @Published var pendingScreenshot: UIImage? = nil  // 待发送的截图（已废弃，现在用shouldSendClipboardImage）
    @Published var shouldSendClipboardImage: Bool = false  // 标记是否需要从剪贴板发送截图
    @Published var screenshotCategory: ScreenshotCategory? = nil  // 截图预分类结果
    @Published var isLoadingOlderMessages: Bool = false  // 是否正在加载更早的消息
    @Published var activeRecordingMessageId: UUID? = nil // 当前活动的录音气泡ID

    /// AppIntent/快捷指令后台写入的 AI 回复：需要在 ChatView 中触发一次性打字机动画的消息 id
    @Published var pendingAnimatedAgentMessageId: UUID? = nil
    
    // 当前生成任务（用于中止）
    var currentGenerationTask: Task<Void, Never>?
    
    // 打字机效果控制
    @Published var isTyping: Bool = false
    private var typingTask: Task<Void, Never>?

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
    
    /// 开始流式接收
    func startStreaming(messageId: UUID) {
        objectWillChange.send()
        StreamingMessageManager.startStreaming(messageId: messageId, in: &chatMessages)
    }
    
    /// 停止生成
    func stopGeneration() {
        print("🛑 用户手动中止生成")
        
        // 1. 取消任务
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        
        // 2. 更新状态
        isAgentTyping = false
        
        // 3. 标记最后一条AI消息为被中断
        if let lastIndex = chatMessages.lastIndex(where: { $0.role == .agent && $0.streamingState.isActive }) {
            var message = chatMessages[lastIndex]
            message.isInterrupted = true
            message.streamingState = .completed // 标记为完成，结束 loading 状态
            // 如果内容为空，给点提示
            if message.content.isEmpty {
                message.content = "..."
            }
            chatMessages[lastIndex] = message
        }
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

    /// 设置完整响应内容 - 由AIBubble负责逐字显示动画
    func playResponse(_ content: String, for messageId: UUID) async {
        let normalized = BackendChatService.normalizeDisplayText(content)
        print("🎬 设置响应内容，总长度: \(normalized.count)")
        
        // 查找消息索引
        guard let messageIndex = chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("⚠️ 找不到消息ID: \(messageId)")
            return
        }
        
        // 在同一个主线程事务里同时更新 typing 状态和消息内容，
        // 避免出现「正在思考」消失但内容还没刷新的空档
        await MainActor.run {
            // 如果内容为空，显示错误提示
            guard !normalized.isEmpty else {
                print("⚠️ 收到空内容")
                var updatedMessage = chatMessages[messageIndex]
                updatedMessage.content = "抱歉，没有收到AI的回复内容"
                updatedMessage.streamingState = .error("空响应")
                chatMessages[messageIndex] = updatedMessage
                
                // 无论成功与否，都结束打字中状态
                isAgentTyping = false
                return
            }
            
            // 正常设置完整内容，让 AIBubble 负责逐字显示动画
            var updatedMessage = chatMessages[messageIndex]
            // 避免重复赋值触发 UI 抖动/打字机重置
            if updatedMessage.content != normalized {
                updatedMessage.content = normalized
            }
            updatedMessage.streamingState = .completed
            chatMessages[messageIndex] = updatedMessage
            
            // 内容与状态一起更新，避免 UI 闪一下空白
            // isAgentTyping = false // 交给 AIBubble 打字机结束后处理，以支持打字过程中也能显示停止按钮
            print("✅ 消息内容已设置，由AIBubble负责逐字显示")
        }
    }

    /// 后端结构化输出回填：把 card 等结果写入当前 AI 消息的卡片字段
    func applyStructuredOutput(_ output: BackendChatStructuredOutput, to messageId: UUID) {
        // 重要：@Published 的数组元素就地修改不会触发 UI 刷新，这里显式发送变更
        objectWillChange.send()
        guard let index = chatMessages.firstIndex(where: { $0.id == messageId }) else { return }
        var msg = chatMessages[index]

        let beforeScheduleCount = msg.scheduleEvents?.count ?? 0
        let beforeScheduleRemoteIds: Set<String> = Set(
            (msg.scheduleEvents ?? [])
                .compactMap { $0.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

#if DEBUG
        let beforeSchedule = msg.scheduleEvents?.count ?? -1
        let beforeContacts = msg.contacts?.count ?? -1
        let beforeInvoices = msg.invoices?.count ?? -1
        let beforeMeetings = msg.meetings?.count ?? -1
        print("🧩 [Structured->AppState] apply to msg=\(messageId) BEFORE schedule=\(beforeSchedule) contacts=\(beforeContacts) invoices=\(beforeInvoices) meetings=\(beforeMeetings) textLen=\(msg.content.count)")
        print("🧩 [Structured->AppState] incoming taskId=\(output.taskId ?? "nil") schedule=\(output.scheduleEvents.count) contacts=\(output.contacts.count) invoices=\(output.invoices.count) meetings=\(output.meetings.count) textLen=\(output.text.count)")
#endif

        StructuredOutputApplier.apply(output, to: &msg)

        // 若日程卡片发生实质变化（新增/补齐 remoteId），触发远端日程缓存失效 + UI 强刷
        if !output.isDelta, !output.scheduleEvents.isEmpty {
            let afterScheduleCount = msg.scheduleEvents?.count ?? 0
            let afterScheduleRemoteIds: Set<String> = Set(
                (msg.scheduleEvents ?? [])
                    .compactMap { $0.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            let didChange = (afterScheduleCount != beforeScheduleCount) || (afterScheduleRemoteIds != beforeScheduleRemoteIds)
            if didChange {
                Task { await ScheduleService.invalidateScheduleCaches() }
                NotificationCenter.default.post(name: .remoteScheduleDidChange, object: nil, userInfo: nil)
            }
        }

        chatMessages[index] = msg

#if DEBUG
        let after = chatMessages[index]
        let afterSchedule = after.scheduleEvents?.count ?? -1
        let afterContacts = after.contacts?.count ?? -1
        let afterInvoices = after.invoices?.count ?? -1
        let afterMeetings = after.meetings?.count ?? -1
        print("🧩 [Structured->AppState] AFTER  schedule=\(afterSchedule) contacts=\(afterContacts) invoices=\(afterInvoices) meetings=\(afterMeetings) notes=\(after.notes ?? "nil")")
#endif
    }

    private func mergeContactsPreservingImpression(existing: [ContactCard]?, incoming: [ContactCard]) -> [ContactCard] {
        var result = existing ?? []
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

        for item in incoming {
            if let idx = result.firstIndex(where: { $0.id == item.id }) {
                let old = result[idx]
                var merged = item

                // 关键：tool observation 的 impression/notes 优先保留（除非新值非空）
                if trimmed(merged.impression).isEmpty { merged.impression = old.impression }
                if trimmed(merged.notes).isEmpty { merged.notes = old.notes }

                // 其它可选字段尽量不丢
                if merged.avatarData == nil { merged.avatarData = old.avatarData }
                if merged.rawImage == nil { merged.rawImage = old.rawImage }

                result[idx] = merged
            } else {
                result.append(item)
            }
        }
        return result
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

    // MARK: - 聊天卡片批次持久化（按 message.id 关联）

    private func persistCardBatchesIfNeeded(for message: ChatMessage, modelContext: ModelContext) {
        do {
            try upsertOrDeleteScheduleBatch(for: message, modelContext: modelContext)
            try upsertOrDeleteContactBatch(for: message, modelContext: modelContext)
            try upsertOrDeleteInvoiceBatch(for: message, modelContext: modelContext)
            try upsertOrDeleteMeetingBatch(for: message, modelContext: modelContext)
        } catch {
            print("⚠️ 卡片批次持久化失败: \(error)")
        }
    }

    private func upsertOrDeleteScheduleBatch(for message: ChatMessage, modelContext: ModelContext) throws {
        let mid: UUID? = message.id
        let descriptor = FetchDescriptor<StoredScheduleCardBatch>(
            predicate: #Predicate<StoredScheduleCardBatch> { batch in
                batch.sourceMessageId == mid
            }
        )
        let existing = try modelContext.fetch(descriptor).first

        let events = (message.scheduleEvents ?? []).dedup(by: ChatCardStableId.schedule)
        if events.isEmpty {
            if let existing { modelContext.delete(existing) }
            return
        }

        if let existing {
            existing.createdAt = message.timestamp
            existing.update(events: events)
        } else {
            modelContext.insert(StoredScheduleCardBatch(events: events, sourceMessageId: message.id, createdAt: message.timestamp))
        }
    }

    private func upsertOrDeleteContactBatch(for message: ChatMessage, modelContext: ModelContext) throws {
        let mid: UUID? = message.id
        let descriptor = FetchDescriptor<StoredContactCardBatch>(
            predicate: #Predicate<StoredContactCardBatch> { batch in
                batch.sourceMessageId == mid
            }
        )
        let existing = try modelContext.fetch(descriptor).first

        let cards = (message.contacts ?? []).dedup(by: ChatCardStableId.contact)
        if cards.isEmpty {
            if let existing { modelContext.delete(existing) }
            return
        }

        if let existing {
            existing.createdAt = message.timestamp
            existing.update(contacts: cards)
        } else {
            modelContext.insert(StoredContactCardBatch(contacts: cards, sourceMessageId: message.id, createdAt: message.timestamp))
        }
    }

    private func upsertOrDeleteInvoiceBatch(for message: ChatMessage, modelContext: ModelContext) throws {
        let mid: UUID? = message.id
        let descriptor = FetchDescriptor<StoredInvoiceCardBatch>(
            predicate: #Predicate<StoredInvoiceCardBatch> { batch in
                batch.sourceMessageId == mid
            }
        )
        let existing = try modelContext.fetch(descriptor).first

        let cards = (message.invoices ?? []).dedup(by: ChatCardStableId.invoice)
        if cards.isEmpty {
            if let existing { modelContext.delete(existing) }
            return
        }

        if let existing {
            existing.createdAt = message.timestamp
            existing.update(invoices: cards)
        } else {
            modelContext.insert(StoredInvoiceCardBatch(invoices: cards, sourceMessageId: message.id, createdAt: message.timestamp))
        }
    }

    private func upsertOrDeleteMeetingBatch(for message: ChatMessage, modelContext: ModelContext) throws {
        let mid: UUID? = message.id
        let descriptor = FetchDescriptor<StoredMeetingCardBatch>(
            predicate: #Predicate<StoredMeetingCardBatch> { batch in
                batch.sourceMessageId == mid
            }
        )
        let existing = try modelContext.fetch(descriptor).first

        let cards = (message.meetings ?? []).dedup(by: ChatCardStableId.meeting)
        if cards.isEmpty {
            if let existing { modelContext.delete(existing) }
            return
        }

        if let existing {
            existing.createdAt = message.timestamp
            existing.update(meetings: cards)
        } else {
            modelContext.insert(StoredMeetingCardBatch(meetings: cards, sourceMessageId: message.id, createdAt: message.timestamp))
        }
    }

    func hydrateCardBatchesIfNeeded(for messages: inout [ChatMessage], modelContext: ModelContext) {
        let ids = Set(messages.map { $0.id })
        guard !ids.isEmpty else { return }

        do {
            // 注意：SwiftData 当前对 “optional + contains(IN) + nil 兜底(三元/??)” 的 SQL 生成不完整，
            // 会触发 `unimplemented SQL generation for predicate` 崩溃（你截图中的错误）。
            //
            // 这里改为：先用「简单、可 SQL 化」的 predicate 缩小范围（按时间），
            // 再在内存里用 ids 做精确过滤，既避免全表拉取，也避免 SQL 生成崩溃。
            let minTs = messages.map(\.timestamp).min() ?? Date.distantPast
            let maxTs = messages.map(\.timestamp).max() ?? Date.distantFuture

            let scheduleBatches = try modelContext.fetch(
                FetchDescriptor<StoredScheduleCardBatch>(
                    predicate: #Predicate<StoredScheduleCardBatch> { batch in
                        batch.createdAt >= minTs && batch.createdAt <= maxTs
                    }
                )
            )
            let contactBatches = try modelContext.fetch(
                FetchDescriptor<StoredContactCardBatch>(
                    predicate: #Predicate<StoredContactCardBatch> { batch in
                        batch.createdAt >= minTs && batch.createdAt <= maxTs
                    }
                )
            )
            let invoiceBatches = try modelContext.fetch(
                FetchDescriptor<StoredInvoiceCardBatch>(
                    predicate: #Predicate<StoredInvoiceCardBatch> { batch in
                        batch.createdAt >= minTs && batch.createdAt <= maxTs
                    }
                )
            )
            let meetingBatches = try modelContext.fetch(
                FetchDescriptor<StoredMeetingCardBatch>(
                    predicate: #Predicate<StoredMeetingCardBatch> { batch in
                        batch.createdAt >= minTs && batch.createdAt <= maxTs
                    }
                )
            )

            var scheduleMap: [UUID: [ScheduleEvent]] = [:]
            var contactMap: [UUID: [ContactCard]] = [:]
            var invoiceMap: [UUID: [InvoiceCard]] = [:]
            var meetingMap: [UUID: [MeetingCard]] = [:]

            for b in scheduleBatches {
                guard let mid = b.sourceMessageId, ids.contains(mid) else { continue }
                scheduleMap[mid] = b.decodedEvents().dedup(by: ChatCardStableId.schedule)
            }
            for b in contactBatches {
                guard let mid = b.sourceMessageId, ids.contains(mid) else { continue }
                contactMap[mid] = b.decodedContacts().dedup(by: ChatCardStableId.contact)
            }
            for b in invoiceBatches {
                guard let mid = b.sourceMessageId, ids.contains(mid) else { continue }
                invoiceMap[mid] = b.decodedInvoices().dedup(by: ChatCardStableId.invoice)
            }
            for b in meetingBatches {
                guard let mid = b.sourceMessageId, ids.contains(mid) else { continue }
                meetingMap[mid] = b.decodedMeetings().dedup(by: ChatCardStableId.meeting)
            }

            for i in messages.indices {
                let mid = messages[i].id
                if let s = scheduleMap[mid], !s.isEmpty { messages[i].scheduleEvents = s }
                if let c = contactMap[mid], !c.isEmpty { messages[i].contacts = c }
                if let inv = invoiceMap[mid], !inv.isEmpty { messages[i].invoices = inv }
                if let m = meetingMap[mid], !m.isEmpty { messages[i].meetings = m }
            }
        } catch {
            print("⚠️ 卡片批次回填失败: \(error)")
        }
    }
    
    /// 从本地存储加载聊天记录
    func loadMessagesFromStorage(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PersistentChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            let persistentMessages = try modelContext.fetch(descriptor)
            // 兼容旧版本：同 id 多次 insert 会产生重复记录，这里按 id 去重（保留最后一次出现）
            var byId: [UUID: ChatMessage] = [:]
            for p in persistentMessages {
                byId[p.id] = p.toChatMessage()
            }
            var loadedMessages = Array(byId.values).sorted(by: { $0.timestamp < $1.timestamp })
            hydrateCardBatchesIfNeeded(for: &loadedMessages, modelContext: modelContext)
            
            DispatchQueue.main.async {
                self.chatMessages = loadedMessages
                print("✅ 从本地加载了 \(loadedMessages.count) 条聊天记录")
            }
        } catch {
            print("⚠️ 加载聊天记录失败: \(error)")
        }
    }

    /// 从本地存储“增量刷新”最近 N 条消息，并与当前内存消息做 upsert 合并（避免整包替换导致 UI 大幅跳动）。
    func upsertLatestMessagesFromStorage(modelContext: ModelContext, limit: Int = 120) {
        var descriptor = FetchDescriptor<PersistentChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)

        do {
            let persistents = try modelContext.fetch(descriptor)
            // 去重：同 id 保留最后一次出现
            var byId: [UUID: ChatMessage] = [:]
            for p in persistents {
                byId[p.id] = p.toChatMessage()
            }
            var loaded = Array(byId.values).sorted(by: { $0.timestamp < $1.timestamp })
            hydrateCardBatchesIfNeeded(for: &loaded, modelContext: modelContext)

            // upsert 合并：已有的 streaming 消息不要被 storage 覆盖（避免影响当前会话流式输出）
            var mergedMap: [UUID: ChatMessage] = Dictionary(uniqueKeysWithValues: chatMessages.map { ($0.id, $0) })
            for m in loaded {
                if let existing = mergedMap[m.id], existing.streamingState.isActive {
#if DEBUG
                    // Debug：如果你看到“卡在正在识别/正在思考”，通常就是这里被保护逻辑挡住了
                    let old = existing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let new = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if old != new {
                        print("🧱 [ChatStorageMerge] skipOverwrite id=\(m.id) oldLen=\(existing.content.count) newLen=\(m.content.count)")
                    }
#endif
                    continue
                }
                mergedMap[m.id] = m
            }
            let merged = mergedMap.values.sorted(by: { $0.timestamp < $1.timestamp })
            self.chatMessages = merged
        } catch {
            print("⚠️ 增量刷新聊天记录失败: \(error)")
        }
    }

    /// 处理“聊天存储已更新”（通常来自快捷指令/AppIntent 后台写入）。
    /// - 职责：刷新 chatMessages、设置一次性动画目标、把目标 AI 消息标记为 streaming 以触发打字机
    func handleChatStorageUpdated(agentMessageId: UUID?, modelContext: ModelContext) {
        // ⚠️ 关键：快捷指令/AppIntent 会在“另一个进程”里写入 SwiftData store。
        // SwiftData 的 ModelContext 可能缓存旧对象，导致 fetch 读到的仍是占位“正在思考...”，从而 UI 永远不刷新。
        // 这里用一个“全新容器/上下文”去读最新落盘数据（失败再回退到当前 context）。
        // 注意：必须持有 ModelContainer 的生命周期；只取 mainContext 而不保留 container 会导致 context 失效并触发崩溃/断点。
        let freshContainer = try? SharedModelContainer.makeContainer()
        let readContext = freshContainer?.mainContext ?? modelContext

        upsertLatestMessagesFromStorage(modelContext: readContext, limit: 200)
        guard let id = agentMessageId else { return }
        guard let idx = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        guard chatMessages[idx].role == .agent else { return }

        // ⚠️ 关键修复：
        // 这里如果把消息标为 `.streaming`，会被 `upsertLatestMessagesFromStorage` 的“streaming 不覆盖”保护挡住，
        // 导致：先写入占位（正在识别/正在思考）→ 后台写入最终内容 → 主App刷新时永远不更新 → 气泡永久卡住。
        // 因此只设置“一次性动画目标”，不改变 streamingState，让后续 storage 写入可以正常覆盖。
        let content = chatMessages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty, content != "正在思考...", content != "正在识别" {
            pendingAnimatedAgentMessageId = id
        }

#if DEBUG
        // 你要求的实时链路日志：这里打印一次“跨进程刷新命中”的关键字段
        print("🔔 [ChatStorageUpdated] id=\(id) contentLen=\(chatMessages[idx].content.count) tool(contact=\(chatMessages[idx].isContactToolRunning) schedule=\(chatMessages[idx].isScheduleToolRunning)) segments=\(chatMessages[idx].segments?.count ?? 0)")
#endif
    }

    /// 兜底处理：当 AppIntent 通过 `openAppWhenRun` 启动了主App，但 Darwin 通知在监听注册前发出而丢失，
    /// 或者 UI 还未订阅进程内通知时，这里主动读取 App Group 的 pending 状态来完成一次刷新。
    func processPendingChatUpdateIfNeeded(modelContext: ModelContext) {
        guard let defaults = UserDefaults(suiteName: ChatSharedDefaults.suite) else { return }

        let ts = defaults.double(forKey: ChatSharedDefaults.lastUpdateTimestampKey)
        let lastHandled = defaults.double(forKey: ChatSharedDefaults.lastHandledUpdateTimestampKey)
        guard ts > 0, ts > lastHandled else { return }
        defaults.set(ts, forKey: ChatSharedDefaults.lastHandledUpdateTimestampKey)

        let idString = (defaults.string(forKey: ChatSharedDefaults.lastInsertedAgentMessageIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID(uuidString: idString)
        handleChatStorageUpdated(agentMessageId: id, modelContext: modelContext)
    }
    
    /// 保存单条消息到本地存储
    func saveMessageToStorage(_ message: ChatMessage, modelContext: ModelContext) {
        do {
            // Upsert：避免同 id 重复插入导致历史加载/ForEach duplicate id
            let mid = message.id
            let descriptor = FetchDescriptor<PersistentChatMessage>(
                predicate: #Predicate<PersistentChatMessage> { msg in
                    msg.id == mid
                }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                let updated = PersistentChatMessage.from(message)
                existing.roleRawValue = updated.roleRawValue
                existing.content = updated.content
                existing.timestamp = updated.timestamp
                existing.isGreeting = updated.isGreeting
                existing.messageTypeRawValue = updated.messageTypeRawValue
                existing.encodedImageData = updated.encodedImageData
                existing.isInterrupted = updated.isInterrupted
            } else {
                modelContext.insert(PersistentChatMessage.from(message))
            }

            // 同步保存卡片批次（按 message.id）
            persistCardBatchesIfNeeded(for: message, modelContext: modelContext)

            try modelContext.save()
            print("✅ 消息已保存到本地: \(message.content.prefix(20))...")
        } catch {
            print("⚠️ 保存消息失败: \(error)")
        }
    }

    // MARK: - Chat 卡片同步（以“后端返回”为准）

    /// 将“后端返回的最新联系人卡片”同步到当前聊天里所有引用它的联系人卡片上（用于：详情页保存后刷新聊天卡片展示）
    @MainActor
    func applyUpdatedContactCardToChatMessages(_ updated: ContactCard) {
        objectWillChange.send()

        let rid = (updated.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        for i in chatMessages.indices {
            guard var cards = chatMessages[i].contacts, !cards.isEmpty else { continue }

            var changed = false
            for j in cards.indices {
                let cardRid = (cards[j].remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let isMatch: Bool = (!rid.isEmpty && cardRid == rid) || (cards[j].id == updated.id)
                guard isMatch else { continue }

                cards[j].remoteId = updated.remoteId ?? cards[j].remoteId
                cards[j].name = updated.name
                cards[j].company = updated.company
                cards[j].title = updated.title
                cards[j].phone = updated.phone
                cards[j].email = updated.email
                cards[j].notes = updated.notes
                cards[j].impression = updated.impression
                if let v = updated.avatarData { cards[j].avatarData = v }
                changed = true
            }

            if changed {
                chatMessages[i].contacts = cards
            }
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
            // 去重 + 回填卡片
            var byId: [UUID: ChatMessage] = [:]
            for p in persistentMessages {
                byId[p.id] = p.toChatMessage()
            }
            var olderMessages = Array(byId.values).sorted(by: { $0.timestamp < $1.timestamp })
            hydrateCardBatchesIfNeeded(for: &olderMessages, modelContext: modelContext)
            let existingIds = Set(chatMessages.map { $0.id })
            olderMessages = olderMessages.filter { !existingIds.contains($0.id) }

            DispatchQueue.main.async {
                if !olderMessages.isEmpty {
                    // 因为消息是按时间从早到晚排序的，更早的消息应该插入到最前面
                    // olderMessages 中的所有消息都比 timestamp 早，所以直接插入到索引0
                    self.chatMessages.insert(contentsOf: olderMessages, at: 0)
                }
                self.isLoadingOlderMessages = false
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoadingOlderMessages = false
            }
        }
    }

    /// 加载最近的 N 条消息（懒加载，保持实现简单，避免跨 actor 捕获 ModelContext）
    func loadRecentMessages(modelContext: ModelContext, limit: Int = 50) {
        var descriptor = FetchDescriptor<PersistentChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            let persistentMessages = try modelContext.fetch(descriptor)
            // 反转顺序，使最早的消息在前面
            var byId: [UUID: ChatMessage] = [:]
            for p in persistentMessages.reversed() {
                byId[p.id] = p.toChatMessage()
            }
            var loadedMessages = Array(byId.values).sorted(by: { $0.timestamp < $1.timestamp })
            hydrateCardBatchesIfNeeded(for: &loadedMessages, modelContext: modelContext)
            self.chatMessages = loadedMessages
        } catch {
        }
    }

    /// 从 SwiftData 刷新聊天记录（用于：AppIntent/Widget 在后台写入后，主 App 拉取同步）
    /// - 策略：
    ///   - 若内存为空：加载全部本地聊天记录（聊天室展示全量历史）
    ///   - 若内存不为空：只追加“比最后一条更晚”的新消息，避免重复加载/插入
    /// - limit：仅用于“增量追加”的单次最大拉取数量（防止极端情况下前台一次性追加过多）
    func refreshChatMessagesFromStorageIfNeeded(modelContext: ModelContext, limit: Int = 80) {
        let cap = max(10, limit)

        // 1) 首次：内存为空 -> 只加载最近 cap 条，避免首次进入聊天室同步拉全量导致卡顿
        if chatMessages.isEmpty {
            loadRecentMessages(modelContext: modelContext, limit: cap)
            return
        }

        // 2) 增量：只拉取更新时间更晚的消息
        let lastTs = chatMessages.last?.timestamp ?? Date.distantPast
        var descriptor = FetchDescriptor<PersistentChatMessage>(
            predicate: #Predicate<PersistentChatMessage> { msg in
                msg.timestamp > lastTs
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = cap

        do {
            let persistents = try modelContext.fetch(descriptor)
            guard !persistents.isEmpty else { return }

            let existingIds = Set(chatMessages.map { $0.id })
            var incoming = persistents.map { $0.toChatMessage() }
            hydrateCardBatchesIfNeeded(for: &incoming, modelContext: modelContext)
            incoming = incoming.filter { !existingIds.contains($0.id) }
            guard !incoming.isEmpty else { return }

            chatMessages.append(contentsOf: incoming)
        } catch {
        }
    }

    /// 清空所有聊天记录（从内存和本地存储）
    func clearAllMessages(modelContext: ModelContext) {
        // 清空内存中的消息
        chatMessages.removeAll()
        
        // 清空本地存储
        do {
            try modelContext.delete(model: PersistentChatMessage.self)
            try modelContext.delete(model: StoredScheduleCardBatch.self)
            try modelContext.delete(model: StoredContactCardBatch.self)
            try modelContext.delete(model: StoredInvoiceCardBatch.self)
            try modelContext.delete(model: StoredMeetingCardBatch.self)
            try modelContext.save()
            print("✅ 已清空所有聊天记录")
        } catch {
            print("⚠️ 清空聊天记录失败: \(error)")
        }
    }
    
    // MARK: - Session 管理（仅用于分段/时间戳，不生成总结）

    /// 开始新的session
    func startNewSession() {
        sessionStartTime = Date()
        print("🆕 开始新Session - 时间: \(sessionStartTime)")
    }
    
    // MARK: - 调试/演示
    
    /// 添加示例日程消息
    func addSampleScheduleMessage() {
        let calendar = Calendar.current
        
        // Helper to create dates
        func createDate(day: Int, hour: Int, minute: Int) -> Date {
            var components = DateComponents()
            components.year = 2025
            components.month = 12
            components.day = day
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components) ?? Date()
        }
        
        // Event 1
        var event1 = ScheduleEvent(
            title: "定粤菜馆",
            description: "提前一周预定和王总吃饭的餐馆",
            startTime: createDate(day: 9, hour: 10, minute: 30),
            endTime: createDate(day: 9, hour: 11, minute: 0)
        )
        event1.hasConflict = true // 示例冲突
        
        // Event 2
        let event2 = ScheduleEvent(
            title: "和张总开会",
            description: "讨论下季度项目规划",
            startTime: createDate(day: 10, hour: 14, minute: 0),
            endTime: createDate(day: 10, hour: 15, minute: 30)
        )
        
        // Event 3
        var event3 = ScheduleEvent(
            title: "团队周会",
            description: "同步本周工作进度和下周计划",
            startTime: createDate(day: 11, hour: 9, minute: 30),
            endTime: createDate(day: 11, hour: 11, minute: 0)
        )
        event3.hasConflict = true
        
        // Event 4
        let event4 = ScheduleEvent(
            title: "客户拜访",
            description: "去上海分公司拜访李总，确认合同细节",
            startTime: createDate(day: 12, hour: 10, minute: 0),
            endTime: createDate(day: 12, hour: 12, minute: 0)
        )
        
        // Event 5
        let event5 = ScheduleEvent(
            title: "项目复盘",
            description: "针对上一期项目进行复盘总结",
            startTime: createDate(day: 13, hour: 15, minute: 0),
            endTime: createDate(day: 13, hour: 17, minute: 0)
        )
        
        var message = ChatMessage(role: .agent, content: "已为您创建了五个日程，可滑动查看，长按可调整。")
        message.scheduleEvents = [event1, event2, event3, event4, event5]
        
        chatMessages.append(message)
    }
    
    /// 添加示例人脉消息
    func addSampleContactMessage() {
        // Contact 1
        let contact1 = ContactCard(
            name: "庄靖瑶",
            englishName: "Kinyoo",
            company: "北京数据项素智能科技有限公司",
            title: "UI 设计师",
            phone: "18311117777",
            email: "18311117777@dataelem.com"
        )
        
        // Contact 2
        let contact2 = ContactCard(
            name: "王建国",
            englishName: "James",
            company: "上海科技创新中心",
            title: "产品总监",
            phone: "13900008888",
            email: "james.wang@sh-tech.com"
        )
        
        var message = ChatMessage(role: .agent, content: "识别到人脉信息，已为您创建了一个人脉卡片，长按可调整，点击可翻面查看。")
        message.contacts = [contact1, contact2]
        
        chatMessages.append(message)
    }
    
    /// 添加示例发票消息
    func addSampleInvoiceMessage() {
        // Invoice 1
        let invoice1 = InvoiceCard(
            invoiceNumber: "2511200000247821866",
            merchantName: "北京市紫光园餐饮有限责任公司",
            amount: 71.00,
            date: Date(),
            type: "餐饮",
            notes: "中午请客吃饭"
        )
        
        var message = ChatMessage(role: .agent, content: "识别到发票信息，已为您创建了发票记录，长按可调整。")
        message.invoices = [invoice1]
        
        chatMessages.append(message)
    }
    
    /// 添加示例会议纪要消息
    func addSampleMeetingMessage() {
        let meeting = MeetingCard(
            title: "圆圆产品记忆系统设计",
            date: {
                var components = DateComponents()
                components.year = 2025
                components.month = 12
                components.day = 17
                components.hour = 1
                components.minute = 27
                components.second = 27
                return Calendar.current.date(from: components) ?? Date()
            }(),
            summary: "本次会议围绕个人AI助手「圆圆」的产品功能设计与技术实现路径展开，重点讨论了核心功能模块、知识库构建策略以及多模态交互体验的优化方案。会议明确了第一阶段的研发重点为长效记忆的准确索引与上下文关联能力的提升。",
            transcriptions: [
                MeetingTranscription(
                    speaker: "说话人1",
                    time: "00:00:00",
                    content: "本次会议围绕个人AI助手「圆圆」的产品功能设计与技术实现路径展开，重点讨论了核心功能模块、信息采集方式、人脉系统逻辑及记忆架构等关键议题。"
                ),
                MeetingTranscription(
                    speaker: "说话人2",
                    time: "00:00:00",
                    content: "本次会议围绕个人AI助手「圆圆」的产品功能设计与技术实现路径展开，重点讨论了核心功能模块、信息采集方式、人脉系统逻辑及记忆架构等关键议题。"
                )
            ]
        )
        
        var message = ChatMessage(role: .agent, content: MeetingCardCopy.agentMessageReady)
        message.meetings = [meeting]
        
        chatMessages.append(message)
    }
    
    /// 添加会议卡片消息（从录音完成后调用）
    @discardableResult
    func addMeetingCardMessage(_ meetingCard: MeetingCard) -> ChatMessage {
        let content = meetingCard.isGenerating
            ? MeetingCardCopy.agentMessageGenerating
            : MeetingCardCopy.agentMessageReady
        var message = ChatMessage(role: .agent, content: content)
        message.meetings = [meetingCard]
        withAnimation {
            chatMessages.append(message)
        }
        print("✅ 会议卡片消息已添加: \(meetingCard.title)")
        return message
    }

    // MARK: - Copy
    private enum MeetingCardCopy {
        /// demo / 真实流程统一：生成完成后的 AI 气泡文案
        static let agentMessageReady = "已为您创建了一份会议纪要文件，长按可调整。"
        /// 真实录音生成中：避免出现“已生成”时态不一致
        static let agentMessageGenerating = "正在生成会议纪要，请稍候..."
    }
    
    /// 用户提示气泡：录音完成，正在生成录音卡片（用于“停止录音”后即时反馈）
    @discardableResult
    func addRecordingGeneratingUserMessage() -> ChatMessage {
        let message = ChatMessage(role: .user, content: "录音完成，正在生成录音卡片")
        withAnimation {
            chatMessages.append(message)
        }
        return message
    }

    /// 用户提示气泡：开始录音（用于"快捷指令启动录音"后即时反馈）
    @discardableResult
    func addRecordingStartedUserMessage() -> ChatMessage {
        let message = ChatMessage(role: .user, content: "录音已开始")
        withAnimation {
            chatMessages.append(message)
        }
        return message
    }

    /// 执行停止录音流程：添加生成中提示气泡 -> 调用停止
    func stopRecordingAndShowGenerating(modelContext: ModelContext) {
        guard LiveRecordingManager.shared.isRecording else { return }
        
        // 添加"正在生成"提示
        let userMsg = addRecordingGeneratingUserMessage()
        saveMessageToStorage(userMsg, modelContext: modelContext)
        
        // 停止录音
        LiveRecordingManager.shared.stopRecording(modelContext: modelContext)
    }

    /// 清理活动的录音气泡状态（已简化，保留空方法以兼容调用）
    func clearActiveRecordingStatus() {
        // 录音气泡已简化为纯文字，无需清理动态状态
    }
    
}

// MARK: - Small helpers

private extension Array {
    /// 保序去重：按 key 提取函数判重，保留第一次出现的元素。
    func dedup<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen: Set<Key> = []
        var out: [Element] = []
        out.reserveCapacity(count)
        for e in self {
            let k = key(e)
            if seen.insert(k).inserted {
                out.append(e)
            }
        }
        return out
    }
}


