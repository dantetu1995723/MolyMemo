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
    /// 提醒时间（后端字段 reminder_time），例如：-5m / -30m / -1h / -1d
    var reminderTime: String? = nil
    /// 日程分类（后端字段 category），例如：meeting / client_visit / travel
    var category: String? = nil
    /// 地点（后端字段 location）
    var location: String? = nil
    /// 是否为全天日程（优先由后端 `full_day` 明确给出）
    /// - 全天展示语义：00:00 ~ 23:59
    var isFullDay: Bool = false
    /// 是否由后端明确给出结束时间（end_time 不为 null 且可解析）
    /// - 用于列表展示：避免 end_time=null 时误显示 “+1h”
    var endTimeProvided: Bool = true
    var isSynced: Bool = false
    var hasConflict: Bool = false
    /// 是否已废弃（由于更新而产生了新卡片）
    var isObsolete: Bool = false
    
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
            return "00:00 ~ 23:59"
        }
        return "\(formatter.string(from: startTime)) ~ \(formatter.string(from: endTime))"
    }

    // MARK: - Codable（向后兼容：旧数据没有 isFullDay 字段）
    private enum CodingKeys: String, CodingKey {
        case id, remoteId, title, description, startTime, endTime, reminderTime, category, location, isFullDay, endTimeProvided, isSynced, hasConflict, isObsolete
    }

    init(
        id: UUID = UUID(),
        remoteId: String? = nil,
        title: String,
        description: String,
        startTime: Date,
        endTime: Date,
        reminderTime: String? = nil,
        category: String? = nil,
        location: String? = nil,
        isFullDay: Bool = false,
        endTimeProvided: Bool = true,
        isSynced: Bool = false,
        hasConflict: Bool = false,
        isObsolete: Bool = false
    ) {
        self.id = id
        self.remoteId = remoteId
        self.title = title
        self.description = description
        self.startTime = startTime
        self.endTime = endTime
        self.reminderTime = reminderTime
        self.category = category
        self.location = location
        self.isFullDay = isFullDay
        self.endTimeProvided = endTimeProvided
        self.isSynced = isSynced
        self.hasConflict = hasConflict
        self.isObsolete = isObsolete
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        remoteId = try c.decodeIfPresent(String.self, forKey: .remoteId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decode(Date.self, forKey: .endTime)
        reminderTime = try c.decodeIfPresent(String.self, forKey: .reminderTime)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        isFullDay = try c.decodeIfPresent(Bool.self, forKey: .isFullDay) ?? false
        endTimeProvided = try c.decodeIfPresent(Bool.self, forKey: .endTimeProvided) ?? true
        isSynced = try c.decodeIfPresent(Bool.self, forKey: .isSynced) ?? false
        hasConflict = try c.decodeIfPresent(Bool.self, forKey: .hasConflict) ?? false
        isObsolete = try c.decodeIfPresent(Bool.self, forKey: .isObsolete) ?? false
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
    /// 是否已废弃
    var isObsolete: Bool = false
    
    // MARK: - Codable（向后兼容：旧数据没有 isObsolete 字段）
    private enum CodingKeys: String, CodingKey {
        case id, remoteId, name, englishName, company, title, phone, email, birthday, gender, industry, location, relationshipType, notes, impression, avatarData, rawImage, isObsolete
    }
    
    init(
        id: UUID = UUID(),
        remoteId: String? = nil,
        name: String,
        englishName: String? = nil,
        company: String? = nil,
        title: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        birthday: String? = nil,
        gender: String? = nil,
        industry: String? = nil,
        location: String? = nil,
        relationshipType: String? = nil,
        notes: String? = nil,
        impression: String? = nil,
        avatarData: Data? = nil,
        rawImage: Data? = nil,
        isObsolete: Bool = false
    ) {
        self.id = id
        self.remoteId = remoteId
        self.name = name
        self.englishName = englishName
        self.company = company
        self.title = title
        self.phone = phone
        self.email = email
        self.birthday = birthday
        self.gender = gender
        self.industry = industry
        self.location = location
        self.relationshipType = relationshipType
        self.notes = notes
        self.impression = impression
        self.avatarData = avatarData
        self.rawImage = rawImage
        self.isObsolete = isObsolete
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        remoteId = try c.decodeIfPresent(String.self, forKey: .remoteId)
        name = try c.decode(String.self, forKey: .name)
        englishName = try c.decodeIfPresent(String.self, forKey: .englishName)
        company = try c.decodeIfPresent(String.self, forKey: .company)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        birthday = try c.decodeIfPresent(String.self, forKey: .birthday)
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        industry = try c.decodeIfPresent(String.self, forKey: .industry)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        relationshipType = try c.decodeIfPresent(String.self, forKey: .relationshipType)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        impression = try c.decodeIfPresent(String.self, forKey: .impression)
        avatarData = try c.decodeIfPresent(Data.self, forKey: .avatarData)
        rawImage = try c.decodeIfPresent(Data.self, forKey: .rawImage)
        isObsolete = try c.decodeIfPresent(Bool.self, forKey: .isObsolete) ?? false
    }
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
    /// 是否已废弃
    var isObsolete: Bool = false
    
    // MARK: - Codable（向后兼容：旧数据没有 isObsolete 字段）
    private enum CodingKeys: String, CodingKey {
        case id, invoiceNumber, merchantName, amount, date, type, notes, isObsolete
    }
    
    init(
        id: UUID = UUID(),
        invoiceNumber: String,
        merchantName: String,
        amount: Double,
        date: Date,
        type: String,
        notes: String? = nil,
        isObsolete: Bool = false
    ) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.merchantName = merchantName
        self.amount = amount
        self.date = date
        self.type = type
        self.notes = notes
        self.isObsolete = isObsolete
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        invoiceNumber = try c.decode(String.self, forKey: .invoiceNumber)
        merchantName = try c.decode(String.self, forKey: .merchantName)
        amount = try c.decode(Double.self, forKey: .amount)
        date = try c.decode(Date.self, forKey: .date)
        type = try c.decode(String.self, forKey: .type)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        isObsolete = try c.decodeIfPresent(Bool.self, forKey: .isObsolete) ?? false
    }
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
    /// 是否已废弃
    var isObsolete: Bool = false
    
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
    
    // MARK: - Codable（向后兼容：旧数据没有 isObsolete 字段）
    private enum CodingKeys: String, CodingKey {
        case id, remoteId, title, date, summary, duration, audioPath, audioRemoteURL, transcriptions, isGenerating, isObsolete
    }
    
    init(
        id: UUID = UUID(),
        remoteId: String? = nil,
        title: String,
        date: Date,
        summary: String,
        duration: TimeInterval? = nil,
        audioPath: String? = nil,
        audioRemoteURL: String? = nil,
        transcriptions: [MeetingTranscription]? = nil,
        isGenerating: Bool = false,
        isObsolete: Bool = false
    ) {
        self.id = id
        self.remoteId = remoteId
        self.title = title
        self.date = date
        self.summary = summary
        self.duration = duration
        self.audioPath = audioPath
        self.audioRemoteURL = audioRemoteURL
        self.transcriptions = transcriptions
        self.isGenerating = isGenerating
        self.isObsolete = isObsolete
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        remoteId = try c.decodeIfPresent(String.self, forKey: .remoteId)
        title = try c.decode(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        summary = try c.decode(String.self, forKey: .summary)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        audioPath = try c.decodeIfPresent(String.self, forKey: .audioPath)
        audioRemoteURL = try c.decodeIfPresent(String.self, forKey: .audioRemoteURL)
        transcriptions = try c.decodeIfPresent([MeetingTranscription].self, forKey: .transcriptions)
        isGenerating = try c.decodeIfPresent(Bool.self, forKey: .isGenerating) ?? false
        isObsolete = try c.decodeIfPresent(Bool.self, forKey: .isObsolete) ?? false
    }
}

struct MeetingTranscription: Identifiable, Equatable, Codable {
    var id = UUID()
    var speaker: String
    var time: String
    var content: String
    /// 该句开始时间（秒）。用于“播放跟随滚动/高亮”；旧数据可能为 nil。
    var startTime: TimeInterval? = nil
    /// 该句结束时间（秒）。可选：后端有时提供；旧数据可能为 nil。
    var endTime: TimeInterval? = nil
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
    /// 仅运行态：当联系人工具链路刚结束（contacts_create/contacts_update），允许“下一批联系人卡片”把本地 soft-delete 的联系人复活。
    /// - 目的：支持“删了又创建同名联系人”时，聊天/工具箱不应继续划杠。
    /// - 注意：不落盘，不参与 Equatable（避免 Date/状态抖动影响 UI diff）。
    var reviveContactsForNextCards: Bool = false
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
    // MARK: - 软删除（统一：聊天室卡片 & 工具箱同步）
    
    /// 统一实体键：优先使用 remoteId（若它可解析成 UUID 则用 UUID 形态稳定映射），否则退回本地 UUID。
    private enum EntityKey {
        static func trimmedLower(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        
        static func schedule(_ e: ScheduleEvent) -> String {
            let rid = trimmedLower(e.remoteId)
            if let u = UUID(uuidString: rid) { return "uuid:\(u.uuidString.lowercased())" }
            if !rid.isEmpty { return "rid:\(rid)" }
            return "id:\(e.id.uuidString.lowercased())"
        }
        
        static func contactCard(_ c: ContactCard) -> String {
            let rid = trimmedLower(c.remoteId)
            if let u = UUID(uuidString: rid) { return "uuid:\(u.uuidString.lowercased())" }
            if !rid.isEmpty { return "rid:\(rid)" }
            return "id:\(c.id.uuidString.lowercased())"
        }
        
        static func contactModel(_ c: Contact) -> String {
            let rid = trimmedLower(c.remoteId)
            if let u = UUID(uuidString: rid) { return "uuid:\(u.uuidString.lowercased())" }
            if !rid.isEmpty { return "rid:\(rid)" }
            return "id:\(c.id.uuidString.lowercased())"
        }
    }
    
    private enum SoftDeleteStoreKeys {
        static let deletedScheduleSnapshots = "yuanyuan_deleted_schedule_snapshots_v1"
    }
    
    /// 被删除（软删）的日程快照：用于“后端删了列表不再返回，但工具箱仍要显示置灰划杠”
    @Published private(set) var deletedScheduleSnapshotByKey: [String: ScheduleEvent] = [:]
    
    init() {
        // 日程软删快照（从 UserDefaults 恢复）
        if let data = UserDefaults.standard.data(forKey: SoftDeleteStoreKeys.deletedScheduleSnapshots),
           let arr = try? JSONDecoder().decode([ScheduleEvent].self, from: data)
        {
            var map: [String: ScheduleEvent] = [:]
            for e in arr {
                var v = e
                v.isObsolete = true
                map[EntityKey.schedule(v)] = v
            }
            self.deletedScheduleSnapshotByKey = map
        }
    }
    
    /// 将“删除日程”的状态应用到任意列表：把命中的 event 标记 obsolete，并把本地快照补回列表中（用于后端已删除的情况）。
    func applyScheduleSoftDeleteOverlay(to events: [ScheduleEvent]) -> [ScheduleEvent] {
        var result: [ScheduleEvent] = []
        result.reserveCapacity(events.count + deletedScheduleSnapshotByKey.count)
        
        var seen: Set<String> = []
        seen.reserveCapacity(events.count)
        
        for e in events {
            var v = e
            let k = EntityKey.schedule(v)
            if deletedScheduleSnapshotByKey[k] != nil {
                v.isObsolete = true
            }
            result.append(v)
            seen.insert(k)
        }
        
        // 补回后端不再返回的“已删除日程”
        for (k, snap) in deletedScheduleSnapshotByKey where !seen.contains(k) {
            var v = snap
            v.isObsolete = true
            result.append(v)
        }
        
        result.sort(by: { $0.startTime < $1.startTime })
        return result
    }
    
    private func persistDeletedScheduleSnapshots() {
        // 控制体积：只保留最近 200 条（按 startTime 倒序取前 200）
        let arr = deletedScheduleSnapshotByKey.values
            .sorted(by: { $0.startTime > $1.startTime })
        let capped = Array(arr.prefix(200))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: SoftDeleteStoreKeys.deletedScheduleSnapshots)
        }
    }
    
    /// 统一：软删除一个日程（聊天室卡片 + 工具箱列表同步，按 id/remoteId 统一）
    func softDeleteSchedule(_ event: ScheduleEvent, modelContext: ModelContext) async {
        // 1) 聊天历史：把所有同实体的卡片置灰划杠并落库
        _ = markScheduleCardsAsObsoleteAndPersist(updated: event, modelContext: modelContext)
        
        // 2) 工具箱：保留一份快照（后端删了也能显示“已删除”）
        var snap = event
        snap.isObsolete = true
        deletedScheduleSnapshotByKey[EntityKey.schedule(snap)] = snap
        persistDeletedScheduleSnapshots()
        
        // 3) 后端：若有 remoteId 则真实删除（维持数据正确），同时通知工具箱/通知栏刷新
        let rid = (event.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rid.isEmpty {
            do {
                try await DeleteActions.deleteRemoteSchedule(event)
            } catch {
                // 删除失败也保留“已删除”视觉态，避免 UI 回跳；错误由调用方自行决定是否提示
            }
        }
        Task { await ScheduleService.invalidateCachesAndNotifyRemoteScheduleDidChange() }
    }
    
    /// 统一：软删除一个联系人（聊天室卡片 + 工具箱联系人列表同步，按 id/remoteId 统一）
    func softDeleteContactCard(_ card: ContactCard, modelContext: ModelContext) async {
        // ✅ 关键：删除可能发生在“用户还没打开聊天室 / chatMessages 仍为空”的场景。
        // 此时仅修改内存数组不会影响落盘历史，导致“联系人列表删了，但聊天仍正常显示”。
        // 这里先把最近一批聊天历史拉进内存，再做统一置灰并落库。
        if chatMessages.isEmpty {
            refreshChatMessagesFromStorageIfNeeded(modelContext: modelContext, limit: 200)
        }

        // 1) 聊天历史：同实体卡片置灰划杠并落库
        markContactCardsAsObsoleteAndPersist(updated: card, modelContext: modelContext)
        
        // 2) 工具箱联系人库：确保本地 Contact 存在，并标记为 obsolete（不硬删）
        do {
            let all = try modelContext.fetch(FetchDescriptor<Contact>())
            let local = ContactCardLocalSync.findOrCreateContact(from: card, allContacts: all, modelContext: modelContext)
            if !local.isObsolete {
                local.isObsolete = true
                local.lastModified = Date()
                try? modelContext.save()
            }
        } catch {
        }
        
        // 3) 后端删除（若有 remoteId）
        let rid = (card.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rid.isEmpty {
            do {
                try await ContactService.deleteContact(remoteId: rid)
            } catch {
            }
        }
        Task { await ContactService.invalidateContactCaches() }
    }

    // MARK: - 会议记录：删除同步（聊天室卡片 -> 工具箱列表 + 后端）

    /// 统一：从聊天室删除一个会议卡片，同时同步：
    /// - 聊天历史：移除所有同一会议（按 remoteId 优先，其次 audioPath）
    /// - 工具箱会议列表：通过通知立即移除
    /// - 后端：有 remoteId 则真实删除
    ///
    /// 设计目标：前后端一致、逻辑清晰；删除失败则回滚聊天室，避免“聊天室删了但工具箱/后端还在”。
    @MainActor
    func deleteMeetingCardEverywhere(_ meeting: MeetingCard, modelContext: ModelContext) async {
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

        func normalizeLocalAudioPath(_ raw: String?) -> String {
            let s = trimmed(raw)
            guard !s.isEmpty else { return "" }
            if let u = URL(string: s), u.isFileURL {
                return u.standardizedFileURL.path
            }
            return URL(fileURLWithPath: s).standardizedFileURL.path
        }

        let rid = trimmed(meeting.remoteId)
        let localPath = normalizeLocalAudioPath(meeting.audioPath)

        func isSameMeeting(_ other: MeetingCard) -> Bool {
            let otherRid = trimmed(other.remoteId)
            if !rid.isEmpty, !otherRid.isEmpty {
                return otherRid == rid
            }
            let otherPath = normalizeLocalAudioPath(other.audioPath)
            if !localPath.isEmpty, !otherPath.isEmpty {
                return otherPath == localPath
            }
            // 最后兜底：同一条消息内删除（按本地 UUID）
            return other.id == meeting.id
        }

        func rebuildAggregatesFromSegments(_ segments: [ChatSegment], into message: inout ChatMessage) {
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

        // 1) 先在本地聊天室“乐观移除”，并记录快照用于失败回滚
        var snapshots: [(idx: Int, old: ChatMessage)] = []
        for i in chatMessages.indices {
            var msg = chatMessages[i]
            let old = msg
            var changed = false

            // a) 聚合字段 meetings
            if var ms = msg.meetings, !ms.isEmpty {
                let before = ms.count
                ms.removeAll(where: { isSameMeeting($0) })
                if ms.count != before {
                    msg.meetings = ms.isEmpty ? nil : ms
                    changed = true
                }
            }

            // b) 分段字段 segments（优先）
            if var segs = msg.segments, !segs.isEmpty {
                var segChanged = false
                for j in segs.indices {
                    guard segs[j].kind == .meetingCards else { continue }
                    if var ms = segs[j].meetings, !ms.isEmpty {
                        let before = ms.count
                        ms.removeAll(where: { isSameMeeting($0) })
                        if ms.count != before {
                            segs[j].meetings = ms.isEmpty ? nil : ms
                            segChanged = true
                        }
                    }
                }
                if segChanged {
                    // 删除空的 meetingCards 段，避免 UI 留下“空卡片占位”
                    segs.removeAll(where: { $0.kind == .meetingCards && (($0.meetings ?? []).isEmpty) })
                    msg.segments = segs.isEmpty ? nil : segs
                    if let newSegs = msg.segments {
                        rebuildAggregatesFromSegments(newSegs, into: &msg)
                    } else {
                        // 没有 segments：保持现有聚合字段（已经处理 meetings）
                    }
                    changed = true
                }
            }

            if changed {
                snapshots.append((idx: i, old: old))
                chatMessages[i] = msg
                saveMessageToStorage(msg, modelContext: modelContext)
            }
        }

        // 若本地没有任何命中，就不做后续动作
        guard !snapshots.isEmpty else { return }

        // 2) 后端删除（有 remoteId 才删）；失败则回滚聊天室，保持一致性
        do {
            if !rid.isEmpty {
                try await MeetingMinutesService.deleteMeetingMinutes(id: rid)
            }

            // 3) 删本地音频文件（仅当 path 存在）
            if !localPath.isEmpty {
                let url = URL(fileURLWithPath: localPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            // 4) 通知会议列表立即移除（工具箱同步）
            NotificationCenter.default.post(
                name: NSNotification.Name("MeetingListDidDelete"),
                object: nil,
                userInfo: [
                    "remoteId": rid,
                    "audioPath": meeting.audioPath ?? ""
                ]
            )
        } catch {
            // 回滚：恢复本地聊天室（并落库），避免“聊天室删了但后端/工具箱还在”
            for s in snapshots {
                chatMessages[s.idx] = s.old
                saveMessageToStorage(s.old, modelContext: modelContext)
            }
        }
    }
    
    /// 从工具箱联系人（SwiftData Contact）发起的删除：转换为统一卡片删除逻辑，确保聊天室同步。
    func softDeleteContactModel(_ contact: Contact, modelContext: ModelContext) async {
        let stub = ContactCard(
            id: contact.id,
            remoteId: {
                let rid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return rid.isEmpty ? nil : rid
            }(),
            name: contact.name,
            company: contact.company,
            title: contact.identity,
            phone: contact.phoneNumber,
            email: contact.email,
            birthday: {
                let v = (contact.birthday ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }(),
            gender: {
                let v = (contact.gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }(),
            industry: {
                let v = (contact.industry ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }(),
            location: {
                let v = (contact.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }(),
            relationshipType: {
                let v = (contact.relationship ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }(),
            notes: {
                let v = (contact.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }(),
            impression: nil,
            avatarData: contact.avatarData,
            rawImage: nil,
            isObsolete: true
        )
        await softDeleteContactCard(stub, modelContext: modelContext)
    }
    
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

    /// 触发截图分析流程 - 打开聊天室并从剪贴板发送截图（由快捷指令/URL scheme 注入）
    /// - Parameter category: 预分类结果（可选）
    func handleScreenshotFromClipboard(category: ScreenshotCategory? = nil) {
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
    }

    /// ChatView 出现时调用：若检测到快捷指令/URL scheme 标记，则从剪贴板取图并直接发送给 AI（无需“转发截图”按钮）。
    func consumeClipboardScreenshotAndAutoSendIfNeeded(modelContext: ModelContext) {
        guard shouldSendClipboardImage else { return }
        shouldSendClipboardImage = false

        // 读取剪贴板中的图片（优先 image，其次尝试常见格式）
        let pasteboard = UIPasteboard.general
        let image: UIImage? = {
            if let img = pasteboard.image { return img }
            let types = ["public.png", "public.jpeg", "public.heic", "public.image"]
            for t in types {
                if let data = pasteboard.data(forPasteboardType: t),
                   let img = UIImage(data: data) {
                    return img
                }
            }
            return nil
        }()

        guard let image else {
            return
        }

        // 默认：截图直发不注入固定文案；如需附带提示词可在此处加开关
        ChatSendFlow.send(
            appState: self,
            modelContext: modelContext,
            text: "",
            images: [image],
            includeHistory: false
        )
    }
    
    /// 快捷指令/AppIntent：从 App Group 文件队列读取待发送截图，并用 ChatSendFlow 发送（与 App 内发送同链路）。
    func processPendingScreenshotIfNeeded(modelContext: ModelContext) {
        // 旧实现是“每次只处理一张 + 正在生成就直接 return”：
        // - 用户连续截图很快时，会堆积多张 pending，但通知只触发一次/前几次被丢掉
        // - 后续某个时刻才处理到旧截图，看起来像“回复时序混乱/消息串台”
        //
        // 新实现：启动一个 drain 任务，按入队顺序逐个发送；每张截图先插入占位消息，再按 messageId 回填。
        // ✅ 进一步优化：对“连续截图”做 debounce，避免第一张触发主 App 立刻开始解码/发网，
        // 造成后续快捷指令（截屏动作 + AppIntent）被系统资源竞争拖慢。
        schedulePendingScreenshotDrain(modelContext: modelContext)
    }

    // MARK: - Pending screenshot drain (serial)

    /// pending 截图串行 drain 任务：确保“截图顺序”与“聊天中消息位置”稳定一致。
    private var pendingScreenshotDrainTask: Task<Void, Never>? = nil
    /// 连续截图 debounce：有新截图进来就延后启动 drain（让快捷指令更“秒过”）
    private var pendingScreenshotDrainDebounceTask: Task<Void, Never>? = nil

    /// 延迟启动 drain：多次触发会取消前一次延迟，最终只启动一次 drain。
    private func schedulePendingScreenshotDrain(modelContext: ModelContext) {
        // 如果 drain 已经在跑，就不需要 debounce 了（它会继续吃掉队列）
        if pendingScreenshotDrainTask != nil { return }

        pendingScreenshotDrainDebounceTask?.cancel()
        pendingScreenshotDrainDebounceTask = Task.detached(priority: .utility) { [weak self] in
            // 适度延迟：给系统/快捷指令截屏流程留出时间，避免资源竞争
            try? await Task.sleep(nanoseconds: 650_000_000) // 0.65s
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pendingScreenshotDrainDebounceTask = nil
                self.startPendingScreenshotDrainIfNeeded(modelContext: modelContext)
            }
        }
    }

    /// 若已有 drain 在跑则不重复启动；否则启动一个后台任务，循环处理 pending 队列直到为空。
    private func startPendingScreenshotDrainIfNeeded(modelContext: ModelContext) {
        // 已在 drain：让现有任务继续吃掉队列即可
        if pendingScreenshotDrainTask != nil { return }

        // ⚠️ 优先级刻意调低：避免主 App 立刻开始 heavy work，影响用户在快捷指令里连续截屏的流畅度
        pendingScreenshotDrainTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            // 进入 drain 后：把 UI 统一标为“生成中”，避免用户在 auto-send 期间再并发触发新请求
            await MainActor.run {
                self.isAgentTyping = true
            }

            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isAgentTyping = false
                    self.pendingScreenshotDrainTask = nil
                }
            }

            while true {
                // 每轮取一张（严格按文件名时间戳升序）
                let nextRelPathAndThumb: (String, String?)? = await MainActor.run {
                    // ✅ 关键修复：
                    // 聊天历史是“进入聊天室时懒加载”（ChatView.onAppear 里：仅当 chatMessages 为空才加载）。
                    // pending 截图可能在 ChatView 出现前就触发 drain；这里先把最近历史拉进内存，
                    // 避免 UI 误判“已有消息”而跳过历史加载。
                    if self.chatMessages.isEmpty {
                        self.refreshChatMessagesFromStorageIfNeeded(modelContext: modelContext, limit: 120)
                    }
                    guard let rel = PendingScreenshotQueue.listPendingRelativePaths(limit: 1).first else { return nil }
                    let thumb = PendingScreenshotQueue.thumbnailRelativePath(forPendingImageRelativePath: rel)
                    return (rel, thumb)
                }

                guard let (rel, thumbRelPath) = nextRelPathAndThumb else { break }

                // 读取图片（失败就丢弃该文件，继续下一张）
                guard let image = PendingScreenshotQueue.loadImage(relativePath: rel) else {
                    PendingScreenshotQueue.remove(relativePath: rel)
                    continue
                }
                // 读到内存后立刻删除，防止重复发送
                PendingScreenshotQueue.remove(relativePath: rel)

                // 快捷指令现在走“秒过”快路径：可能没有提前生成缩略图
                let ensuredThumbRelPath: String? = {
                    if let thumbRelPath, !thumbRelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return thumbRelPath
                    }
                    // 在主App侧生成缩略图（不阻塞快捷指令）
                    guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ScreenshotSendAttributes.appGroupId) else {
                        return nil
                    }
                    let dir = groupURL.appendingPathComponent("screenshot_thumbnails", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let thumb = image.yy_resizedThumbnail(maxPixel: 320)
                    guard let data = thumb.jpegData(compressionQuality: 0.72) else { return nil }
                    let filename = "thumb_\(UUID().uuidString).jpg"
                    let fileURL = dir.appendingPathComponent(filename)
                    do {
                        try data.write(to: fileURL, options: [.atomic])
                        return "screenshot_thumbnails/\(filename)"
                    } catch {
                        return nil
                    }
                }()

                // 通知：主App开始实际处理该截图（会覆盖 intent 里“已交给Moly”那条 sending 通知）
                await ScreenshotSendNotifications.postSending(thumbnailRelativePath: ensuredThumbRelPath)

                // 1) 先插入用户消息 + AI 占位消息（确保 UI 顺序稳定）
                let (messageId, messagesForModel): (UUID, [ChatMessage]) = await MainActor.run {
                    self.showChatRoom = true

                    let userMsg = ChatMessage(role: .user, images: [image], content: "")
                    withAnimation {
                        self.chatMessages.append(userMsg)
                    }
                    self.saveMessageToStorage(userMsg, modelContext: modelContext)

                    let agentMsg = ChatMessage(role: .agent, content: "")
                    withAnimation {
                        self.chatMessages.append(agentMsg)
                    }
                    let agentMessageId = agentMsg.id

                    self.startStreaming(messageId: agentMessageId)

                    // 与 ChatSendFlow 一致：默认带历史。SmartModelRouter 若选择后端实现，会自行只取 last user。
                    let snapshot = self.chatMessages
                    return (agentMessageId, snapshot)
                }

                // 2) 串行发送：等待该张截图完整结束（成功/失败）后再处理下一张
                await SmartModelRouter.sendMessageStream(
                    messages: messagesForModel,
                    mode: await MainActor.run { self.currentMode },
                    onStructuredOutput: { output in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.applyStructuredOutput(output, to: messageId, modelContext: modelContext)
                        }
                    },
                    onComplete: { finalText in
                        // playResponse 内会按 messageId 定位并回填内容（不 append），确保时序稳定
                        await self.playResponse(finalText, for: messageId)
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            if let completedMessage = self.chatMessages.first(where: { $0.id == messageId }) {
                                self.saveMessageToStorage(completedMessage, modelContext: modelContext)
                            }
                        }

                        let normalized = BackendChatService.normalizeDisplayText(finalText)
                        let success = !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let resultNotificationId = "molymemo.screenshot_send.result.\(messageId.uuidString)"
                        await ScreenshotSendNotifications.postResult(
                            success: success,
                            thumbnailRelativePath: ensuredThumbRelPath,
                            id: resultNotificationId
                        )
                    },
                    onError: { error in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.handleStreamingError(error, for: messageId)
                            // 失败也继续 drain 下一张
                        }
                        let resultNotificationId = "molymemo.screenshot_send.result.\(messageId.uuidString)"
                        Task {
                            await ScreenshotSendNotifications.postResult(
                                success: false,
                                thumbnailRelativePath: ensuredThumbRelPath,
                                id: resultNotificationId
                            )
                        }
                    }
                )
            }
        }
    }

    // MARK: - 聊天室流式更新方法
    
    /// 开始流式接收
    func startStreaming(messageId: UUID) {
        objectWillChange.send()
        StreamingMessageManager.startStreaming(messageId: messageId, in: &chatMessages)
    }
    
    /// 停止生成
    func stopGeneration() {
        
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
        
        // 查找消息索引
        guard let messageIndex = chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        // 在同一个主线程事务里同时更新 typing 状态和消息内容，
        // 避免出现「正在思考」消失但内容还没刷新的空档
        await MainActor.run {
            // 如果内容为空，显示错误提示
            guard !normalized.isEmpty else {
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
        }
    }

    /// 后端结构化输出回填：把 card 等结果写入当前 AI 消息的卡片字段
    func applyStructuredOutput(_ output: BackendChatStructuredOutput, to messageId: UUID, modelContext: ModelContext? = nil) {
        // 重要：@Published 的数组元素就地修改不会触发 UI 刷新，这里显式发送变更
        objectWillChange.send()
        guard let index = chatMessages.firstIndex(where: { $0.id == messageId }) else { return }
        var msg = chatMessages[index]

        // 用“内容签名”判断是否发生了“修改”（不仅仅是新增/补齐 remoteId）
        func scheduleSignature(_ e: ScheduleEvent) -> String {
            let rid = (e.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = rid.isEmpty ? "lid:\(e.id.uuidString)" : "rid:\(rid)"
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = e.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = String(Int64(e.startTime.timeIntervalSince1970 * 1000))
            let end = String(Int64(e.endTime.timeIntervalSince1970 * 1000))
            return [
                key,
                title,
                desc,
                start,
                end,
                e.isFullDay ? "fullDay:1" : "fullDay:0",
                e.endTimeProvided ? "endProvided:1" : "endProvided:0"
            ].joined(separator: "|")
        }
        let beforeScheduleSignatures: Set<String> = Set((msg.scheduleEvents ?? []).map(scheduleSignature))
        let beforeScheduleToolRunning = msg.isScheduleToolRunning
        let beforeContactToolRunning = msg.isContactToolRunning

        // ✅ 在应用结构化输出前，如果 output 包含卡片，检查是否是更新操作
        // 如果是更新（即 remoteId 已在之前的消息中存在），则将旧卡片标记为已废弃
        let obsoleteChangedMessageIds = markPreviousCardsAsObsoleteIfNeeded(output: output)

        StructuredOutputApplier.apply(output, to: &msg)
        
        // ✅ 联系人 tool 从 running -> finished：允许“紧随其后的联系人卡片”把本地 soft-delete 的联系人复活
        let afterContactToolRunning = msg.isContactToolRunning
        if beforeContactToolRunning && !afterContactToolRunning {
            msg.reviveContactsForNextCards = true
        }

        // ✅ 聊天里“创建联系人/更新联系人”成功后：
        // 把 contact card 同步到本地 SwiftData Contact 库，随后由 ContactCardLocalSync 触发单向写入系统通讯录。
        if let modelContext {
            let incoming = (msg.contacts ?? []).dedup(by: ChatCardStableId.contact)
            let allowReviveFromThisMessage = msg.reviveContactsForNextCards
            if !incoming.isEmpty {
#if DEBUG
                print("[AppState] applyStructuredOutput() syncing contacts to local store. isDelta=\(output.isDelta) count=\(incoming.count)")
#endif
                do {
                    var all = try modelContext.fetch(FetchDescriptor<Contact>())
                    for card in incoming {
                        let local = ContactCardLocalSync.findOrCreateContact(from: card, allContacts: all, modelContext: modelContext, reviveIfObsolete: allowReviveFromThisMessage)
                        if !all.contains(where: { $0.id == local.id }) {
                            all.append(local)
                        }
                    }
                    // 只对“紧随 tool 完成的这一批卡片”生效一次，避免影响后续纯展示场景
                    if msg.reviveContactsForNextCards { msg.reviveContactsForNextCards = false }
                } catch {
#if DEBUG
                    print("[AppState] applyStructuredOutput() local Contact sync failed: \(error.localizedDescription)")
#endif
                }
            }

            // ✅ 删除态统一：
            // 若本地联系人库里该联系人已被软删除（Contact.isObsolete=true），则任何新回填到聊天里的同实体联系人卡片
            // 都应展示为“已删除”（置灰划杠），避免出现「联系人列表已删，但聊天新生成仍正常显示」的不一致。
            // 例外：若该消息刚完成 contacts_create/contacts_update，则允许显示/复活联系人（否则“删了再建”会一直划杠）
            if allowReviveFromThisMessage, !incoming.isEmpty {
                // 本条消息属于“创建/更新联系人”的落卡阶段：不做 sticky 删除覆盖
            } else if !msg.reviveContactsForNextCards {
                applyContactSoftDeleteOverlayIfNeeded(to: &msg, modelContext: modelContext)
            } else {
                // 即使没有卡片同步成功，也确保该开关只影响当前一轮
                msg.reviveContactsForNextCards = false
            }
        }

        // ✅ 每次“聊天室创建或修改完日程”后立刻强刷：
        // 触发条件：
        // 1) 非 delta 的最终输出里，日程内容签名发生变化（可覆盖“修改但 remoteId 不变”的情况）
        // 2) 日程 tool 从 running -> finished（可覆盖“删除但没返回卡片”的情况）
        let afterScheduleSignatures: Set<String> = Set((msg.scheduleEvents ?? []).map(scheduleSignature))
        let afterScheduleToolRunning = msg.isScheduleToolRunning
        let scheduleToolJustFinished = beforeScheduleToolRunning && !afterScheduleToolRunning
        let scheduleCardsChangedOnFinal = (!output.isDelta) && (!output.scheduleEvents.isEmpty) && (afterScheduleSignatures != beforeScheduleSignatures)
        if scheduleToolJustFinished || scheduleCardsChangedOnFinal {
            Task { await ScheduleService.invalidateCachesAndNotifyRemoteScheduleDidChange() }
        }

        chatMessages[index] = msg

        // ✅ 工具删除：schedules_delete 通常不会产生 card chunk，但需要把历史卡片置灰
        // 基于 output.deletedScheduleRemoteIds，回写历史消息里的同 remoteId 日程为 isObsolete=true，并落库/写软删快照。
        var allObsoleteChangedMessageIds = obsoleteChangedMessageIds
        if let modelContext, !output.deletedScheduleRemoteIds.isEmpty {
            let extra = applyDeletedSchedulesFromTool(remoteIds: output.deletedScheduleRemoteIds, modelContext: modelContext)
            if !extra.isEmpty {
                allObsoleteChangedMessageIds.formUnion(extra)
            }
            // 删除也应刷新工具箱/通知栏列表（后端已删除，列表会少一条；同时用于通知栏更新）
            Task { await ScheduleService.invalidateCachesAndNotifyRemoteScheduleDidChange() }
        }

        // ✅ 把“废弃旧卡”的变化也落库，确保下次打开仍能看到划杠变灰的历史卡片
        if let modelContext, !allObsoleteChangedMessageIds.isEmpty {
            for mid in allObsoleteChangedMessageIds {
                if let idx = chatMessages.firstIndex(where: { $0.id == mid }) {
                    saveMessageToStorage(chatMessages[idx], modelContext: modelContext)
                }
            }
        }
    }

    /// 将“本地已删除联系人（Contact.isObsolete=true）”的删除态覆盖到聊天消息里的联系人卡片上（含 segments / 聚合字段）。
    /// - 目标：删除是 sticky 的；任何后续出现的同一联系人卡片都应该展示为已删除。
    @MainActor
    private func applyContactSoftDeleteOverlayIfNeeded(to message: inout ChatMessage, modelContext: ModelContext) {
        // 快路径：消息里根本没有联系人卡片就不处理
        let hasAggregate = (message.contacts?.isEmpty == false)
        let hasSegments: Bool = {
            guard let segs = message.segments, !segs.isEmpty else { return false }
            return segs.contains(where: { $0.kind == .contactCards && (($0.contacts ?? []).isEmpty == false) })
        }()
        guard hasAggregate || hasSegments else { return }

        let all: [Contact] = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []
        let obsoleteContacts = all.filter { $0.isObsolete }
        guard !obsoleteContacts.isEmpty else { return }

        // 1) 已删除实体 key（remoteId/uuid 归一，保证大小写/格式一致）
        let obsoleteKeys: Set<String> = Set(obsoleteContacts.map { EntityKey.contactModel($0) })

        // 2) 强兜底 key：phone/email（避免卡片还没补齐 remoteId 时无法命中）
        func trimmedLower(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func normalizedPhone(_ s: String?) -> String {
            let raw = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return "" }
            let allowed = CharacterSet(charactersIn: "+0123456789")
            let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
            return String(String.UnicodeScalarView(filtered))
        }
        var strongStableKeys: Set<String> = []
        strongStableKeys.reserveCapacity(obsoleteContacts.count * 2)
        for c in obsoleteContacts {
            let phone = normalizedPhone(c.phoneNumber)
            if !phone.isEmpty { strongStableKeys.insert("phone:\(phone)") }
            let email = trimmedLower(c.email)
            if !email.isEmpty { strongStableKeys.insert("email:\(email)") }
        }

        func shouldBeObsolete(_ card: ContactCard) -> Bool {
            if obsoleteKeys.contains(EntityKey.contactCard(card)) { return true }
            if !strongStableKeys.isEmpty {
                let s = ChatCardStableId.contact(card)
                if s.hasPrefix("phone:") || s.hasPrefix("email:") {
                    return strongStableKeys.contains(s)
                }
            }
            return false
        }

        // 覆盖聚合字段
        if var cards = message.contacts, !cards.isEmpty {
            var changed = false
            for i in cards.indices {
                if !cards[i].isObsolete, shouldBeObsolete(cards[i]) {
                    cards[i].isObsolete = true
                    changed = true
                }
            }
            if changed { message.contacts = cards }
        }

        // 覆盖 segments
        if var segs = message.segments, !segs.isEmpty {
            var segsChanged = false
            for si in segs.indices where segs[si].kind == .contactCards {
                guard var cs = segs[si].contacts, !cs.isEmpty else { continue }
                var localChanged = false
                for ci in cs.indices {
                    if !cs[ci].isObsolete, shouldBeObsolete(cs[ci]) {
                        cs[ci].isObsolete = true
                        localChanged = true
                    }
                }
                if localChanged {
                    segs[si].contacts = cs
                    segsChanged = true
                }
            }
            if segsChanged { message.segments = segs }
        }
    }

    /// 检查并标记旧卡片为废弃
    private func markPreviousCardsAsObsoleteIfNeeded(output: BackendChatStructuredOutput) -> Set<UUID> {
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        
        let incomingScheduleRids = Set(output.scheduleEvents.compactMap { trimmed($0.remoteId) }.filter { !$0.isEmpty })
        let incomingContactRids = Set(output.contacts.compactMap { trimmed($0.remoteId) }.filter { !$0.isEmpty })
        let incomingInvoiceIds = Set(output.invoices.map { $0.id })
        let incomingMeetingRids = Set(output.meetings.compactMap { trimmed($0.remoteId) }.filter { !$0.isEmpty })
        
        if incomingScheduleRids.isEmpty && incomingContactRids.isEmpty && incomingInvoiceIds.isEmpty && incomingMeetingRids.isEmpty {
            return []
        }
        
        var changed = false
        var changedMessageIds: Set<UUID> = []
        for i in chatMessages.indices {
            var msg = chatMessages[i]
            var msgChanged = false
            
            // 1) 检查日程
            if !incomingScheduleRids.isEmpty {
                if var events = msg.scheduleEvents, !events.isEmpty {
                    for j in events.indices {
                        let rid = trimmed(events[j].remoteId)
                        if !rid.isEmpty, incomingScheduleRids.contains(rid), !events[j].isObsolete {
                            events[j].isObsolete = true
                            msgChanged = true
                        }
                    }
                    if msgChanged { msg.scheduleEvents = events }
                }
                if var segments = msg.segments, !segments.isEmpty {
                    for j in segments.indices {
                        if segments[j].kind == .scheduleCards, var events = segments[j].scheduleEvents, !events.isEmpty {
                            var segChanged = false
                            for k in events.indices {
                                let rid = trimmed(events[k].remoteId)
                                if !rid.isEmpty, incomingScheduleRids.contains(rid), !events[k].isObsolete {
                                    events[k].isObsolete = true
                                    segChanged = true
                                    msgChanged = true
                                }
                            }
                            if segChanged { segments[j].scheduleEvents = events }
                        }
                    }
                    if msgChanged { msg.segments = segments }
                }
            }
            
            // 2) 检查人脉
            if !incomingContactRids.isEmpty {
                if var contacts = msg.contacts, !contacts.isEmpty {
                    for j in contacts.indices {
                        let rid = trimmed(contacts[j].remoteId)
                        if !rid.isEmpty, incomingContactRids.contains(rid), !contacts[j].isObsolete {
                            contacts[j].isObsolete = true
                            msgChanged = true
                        }
                    }
                    if msgChanged { msg.contacts = contacts }
                }
                if var segments = msg.segments, !segments.isEmpty {
                    for j in segments.indices {
                        if segments[j].kind == .contactCards, var cards = segments[j].contacts, !cards.isEmpty {
                            var segChanged = false
                            for k in cards.indices {
                                let rid = trimmed(cards[k].remoteId)
                                if !rid.isEmpty, incomingContactRids.contains(rid), !cards[k].isObsolete {
                                    cards[k].isObsolete = true
                                    segChanged = true
                                    msgChanged = true
                                }
                            }
                            if segChanged { segments[j].contacts = cards }
                        }
                    }
                    if msgChanged { msg.segments = segments }
                }
            }

            // 3) 检查发票 (通常按 id)
            if !incomingInvoiceIds.isEmpty {
                if var invoices = msg.invoices, !invoices.isEmpty {
                    for j in invoices.indices {
                        if incomingInvoiceIds.contains(invoices[j].id), !invoices[j].isObsolete {
                            invoices[j].isObsolete = true
                            msgChanged = true
                        }
                    }
                    if msgChanged { msg.invoices = invoices }
                }
                if var segments = msg.segments, !segments.isEmpty {
                    for j in segments.indices {
                        if segments[j].kind == .invoiceCards, var cards = segments[j].invoices, !cards.isEmpty {
                            var segChanged = false
                            for k in cards.indices {
                                if incomingInvoiceIds.contains(cards[k].id), !cards[k].isObsolete {
                                    cards[k].isObsolete = true
                                    segChanged = true
                                    msgChanged = true
                                }
                            }
                            if segChanged { segments[j].invoices = cards }
                        }
                    }
                    if msgChanged { msg.segments = segments }
                }
            }

            // 4) 检查会议
            if !incomingMeetingRids.isEmpty {
                if var meetings = msg.meetings, !meetings.isEmpty {
                    for j in meetings.indices {
                        let rid = trimmed(meetings[j].remoteId)
                        if !rid.isEmpty, incomingMeetingRids.contains(rid), !meetings[j].isObsolete {
                            meetings[j].isObsolete = true
                            msgChanged = true
                        }
                    }
                    if msgChanged { msg.meetings = meetings }
                }
                if var segments = msg.segments, !segments.isEmpty {
                    for j in segments.indices {
                        if segments[j].kind == .meetingCards, var cards = segments[j].meetings, !cards.isEmpty {
                            var segChanged = false
                            for k in cards.indices {
                                let rid = trimmed(cards[k].remoteId)
                                if !rid.isEmpty, incomingMeetingRids.contains(rid), !cards[k].isObsolete {
                                    cards[k].isObsolete = true
                                    segChanged = true
                                    msgChanged = true
                                }
                            }
                            if segChanged { segments[j].meetings = cards }
                        }
                    }
                    if msgChanged { msg.segments = segments }
                }
            }

            if msgChanged {
                chatMessages[i] = msg
                changed = true
                changedMessageIds.insert(msg.id)
            }
        }
        
        if changed {
            objectWillChange.send()
        }
        return changedMessageIds
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
            }
        } catch {
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
                    }
#endif
                    continue
                }
                mergedMap[m.id] = m
            }
            let merged = mergedMap.values.sorted(by: { $0.timestamp < $1.timestamp })
            self.chatMessages = merged
        } catch {
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
            let existingAll = try modelContext.fetch(descriptor)
            if let existing = existingAll.first {
                let updated = PersistentChatMessage.from(message)
                existing.roleRawValue = updated.roleRawValue
                existing.content = updated.content
                existing.timestamp = updated.timestamp
                existing.isGreeting = updated.isGreeting
                existing.messageTypeRawValue = updated.messageTypeRawValue
                existing.encodedImageData = updated.encodedImageData
                existing.encodedSegments = updated.encodedSegments
                existing.isInterrupted = updated.isInterrupted

                // ✅ 兼容旧版本：如果历史里同 id 有重复记录，保留第一条并删除其余，避免重启加载被旧记录覆盖
                if existingAll.count > 1 {
                    for extra in existingAll.dropFirst() {
                        modelContext.delete(extra)
                    }
                }
            } else {
                modelContext.insert(PersistentChatMessage.from(message))
            }

            // 同步保存卡片批次（按 message.id）
            persistCardBatchesIfNeeded(for: message, modelContext: modelContext)

            try modelContext.save()
        } catch {
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

    // MARK: - Chat 卡片修订（版本化：旧卡废弃 + 新卡生成）

    /// 统一：提交一次“日程卡片修改”到聊天历史
    /// - 行为：把历史中匹配同一实体的旧卡置为 isObsolete=true 并落库；然后追加一条新的 agent 消息（提示文字 + 新卡片）并落库。
    @MainActor
    func commitScheduleCardRevision(
        updated: ScheduleEvent,
        modelContext: ModelContext,
        reasonText: String = "已更新日程"
    ) {
        _ = markScheduleCardsAsObsoleteAndPersist(updated: updated, modelContext: modelContext)

        var msg = ChatMessage(role: .agent, content: reasonText)
        msg.segments = [
            .text(reasonText),
            .scheduleCards([updated])
        ]
        msg.scheduleEvents = [updated]

        withAnimation {
            chatMessages.append(msg)
        }
        saveMessageToStorage(msg, modelContext: modelContext)

        // 确保工具箱/通知栏同步
        Task { await ScheduleService.invalidateCachesAndNotifyRemoteScheduleDidChange() }
    }

    /// 统一：提交一次“联系人卡片修改”到聊天历史
    /// - 行为：把历史中匹配同一实体的旧卡置为 isObsolete=true 并落库；然后追加一条新的 agent 消息（提示文字 + 新卡片）并落库。
    @MainActor
    func commitContactCardRevision(
        updated: ContactCard,
        modelContext: ModelContext,
        reasonText: String = "已更新联系人"
    ) {
        markContactCardsAsObsoleteAndPersist(updated: updated, modelContext: modelContext)

        // ✅ 同步到本地联系人库：让工具箱“联系人列表/详情”第一次打开就能读到更新后的字段
        do {
            let all = try modelContext.fetch(FetchDescriptor<Contact>())
            _ = ContactCardLocalSync.findOrCreateContact(from: updated, allContacts: all, modelContext: modelContext)
        } catch {
        }

        // ✅ 失效联系人网络缓存：避免工具箱进入时先用旧 cache 覆盖本地新值
        Task { await ContactService.invalidateContactCaches() }

        let t = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        var msg = ChatMessage(role: .agent, content: t)
        // ✅ 若没有后端文案，则只追加卡片，不再硬塞默认提示词
        if t.isEmpty {
            msg.segments = [
                .contactCards([updated])
            ]
        } else {
            msg.segments = [
                .text(t),
                .contactCards([updated])
            ]
        }
        msg.contacts = [updated]

        withAnimation {
            chatMessages.append(msg)
        }
        saveMessageToStorage(msg, modelContext: modelContext)
    }

    @MainActor
    private func markScheduleCardsAsObsoleteAndPersist(updated: ScheduleEvent, modelContext: ModelContext) -> Set<UUID> {
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let rid = trimmed(updated.remoteId)

        var changedMessageIds: Set<UUID> = []
        for i in chatMessages.indices {
            var msg = chatMessages[i]
            var msgChanged = false

            if var events = msg.scheduleEvents, !events.isEmpty {
                for j in events.indices {
                    let match: Bool = (!rid.isEmpty && trimmed(events[j].remoteId) == rid) || (events[j].id == updated.id)
                    guard match, !events[j].isObsolete else { continue }
                    events[j].isObsolete = true
                    msgChanged = true
                }
                if msgChanged { msg.scheduleEvents = events }
            }

            if var segs = msg.segments, !segs.isEmpty {
                var segsChanged = false
                for si in segs.indices {
                    guard segs[si].kind == .scheduleCards else { continue }
                    guard var evs = segs[si].scheduleEvents, !evs.isEmpty else { continue }
                    var localChanged = false
                    for ei in evs.indices {
                        let match: Bool = (!rid.isEmpty && trimmed(evs[ei].remoteId) == rid) || (evs[ei].id == updated.id)
                        guard match, !evs[ei].isObsolete else { continue }
                        evs[ei].isObsolete = true
                        localChanged = true
                    }
                    if localChanged {
                        segs[si].scheduleEvents = evs
                        segsChanged = true
                        msgChanged = true
                    }
                }
                if segsChanged {
                    msg.segments = segs
                }
            }

            if msgChanged {
                chatMessages[i] = msg
                changedMessageIds.insert(msg.id)
            }
        }

        // 逐条落库（保证下次打开仍能看到“划杠变灰”的旧卡）
        for mid in changedMessageIds {
            if let idx = chatMessages.firstIndex(where: { $0.id == mid }) {
                saveMessageToStorage(chatMessages[idx], modelContext: modelContext)
            }
        }
        return changedMessageIds
    }

    /// schedules_delete 工具回写：按 remoteId 找到历史里的日程卡片并置灰，同时写入软删快照（用于工具箱展示“已删除”）。
    @MainActor
    private func applyDeletedSchedulesFromTool(remoteIds: [String], modelContext: ModelContext) -> Set<UUID> {
        func trimmedLower(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let incoming = remoteIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return [] }

        // 去重（保持顺序）
        var seen: Set<String> = []
        var unique: [String] = []
        for rid in incoming {
            let k = trimmedLower(rid)
            if seen.insert(k).inserted { unique.append(rid) }
        }

        var changed: Set<UUID> = []
        var anyApplied = false

        for rid in unique {
            if let snap0 = findScheduleSnapshotByRemoteId(rid) {
                var snap = snap0
                // 以 remoteId 为主键，强制对齐（避免快照里 remoteId 为空/带空格）
                snap.remoteId = rid
                snap.isObsolete = true

                let ids = markScheduleCardsAsObsoleteAndPersist(updated: snap, modelContext: modelContext)
                if !ids.isEmpty {
                    changed.formUnion(ids)
                }

                // 工具箱软删快照：保证后端已删除时仍能展示“已删除”状态（与手动删除一致）
                deletedScheduleSnapshotByKey[EntityKey.schedule(snap)] = snap
                anyApplied = true
            } else {
                // 找不到历史快照也不强造卡片；但仍应视为远端变更（用于工具箱刷新）
                anyApplied = true
            }
        }

        if anyApplied {
            persistDeletedScheduleSnapshots()
        }
        return changed
    }

    /// 从聊天历史中按 remoteId 找一个“可作为快照”的 ScheduleEvent（用于删除置灰）。
    /// - 策略：从新到旧找，优先 segments 内的 scheduleCards，其次聚合 scheduleEvents。
    @MainActor
    private func findScheduleSnapshotByRemoteId(_ remoteId: String) -> ScheduleEvent? {
        let rid = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

        for msg in chatMessages.reversed() {
            if let segs = msg.segments, !segs.isEmpty {
                for seg in segs.reversed() where seg.kind == .scheduleCards {
                    if let evs = seg.scheduleEvents, !evs.isEmpty {
                        if let hit = evs.first(where: { trimmed($0.remoteId) == rid }) {
                            return hit
                        }
                    }
                }
            }
            if let evs = msg.scheduleEvents, !evs.isEmpty {
                if let hit = evs.first(where: { trimmed($0.remoteId) == rid }) {
                    return hit
                }
            }
        }
        return nil
    }

    @MainActor
    private func markContactCardsAsObsoleteAndPersist(updated: ContactCard, modelContext: ModelContext) {
        // ⚠️ 这里不能只按 raw remoteId 直接 ==：
        // - remoteId 可能大小写不同（UUID）
        // - 卡片可能暂未补齐 remoteId（先给字段，后补 remoteId）
        // 因此用统一 key（remoteId -> UUID 归一 -> lowercased），并用 phone/email 做安全兜底。
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let targetKey = EntityKey.contactCard(updated)
        let targetStable: String? = {
            let s = ChatCardStableId.contact(updated)
            // 只在“强锚点”时兜底，避免仅按 name/company/title 的指纹误伤
            if s.hasPrefix("phone:") || s.hasPrefix("email:") { return s }
            return nil
        }()

        func isSameEntity(_ card: ContactCard) -> Bool {
            if EntityKey.contactCard(card) == targetKey { return true }
            if let targetStable {
                return ChatCardStableId.contact(card) == targetStable
            }
            return false
        }

        // @Published 数组元素变更有时不会触发 UI 刷新：这里显式发一次变更，确保聊天页能立刻看到“置灰划杠”
        objectWillChange.send()

        var changedMessageIds: Set<UUID> = []
        for i in chatMessages.indices {
            var msg = chatMessages[i]
            var msgChanged = false

            if var cards = msg.contacts, !cards.isEmpty {
                for j in cards.indices {
                    guard isSameEntity(cards[j]), !cards[j].isObsolete else { continue }
                    cards[j].isObsolete = true
                    msgChanged = true
                }
                if msgChanged { msg.contacts = cards }
            }

            if var segs = msg.segments, !segs.isEmpty {
                var segsChanged = false
                for si in segs.indices {
                    guard segs[si].kind == .contactCards else { continue }
                    guard var cs = segs[si].contacts, !cs.isEmpty else { continue }
                    var localChanged = false
                    for ci in cs.indices {
                        guard isSameEntity(cs[ci]), !cs[ci].isObsolete else { continue }
                        cs[ci].isObsolete = true
                        localChanged = true
                    }
                    if localChanged {
                        segs[si].contacts = cs
                        segsChanged = true
                        msgChanged = true
                    }
                }
                if segsChanged {
                    msg.segments = segs
                }
            }

            if msgChanged {
                chatMessages[i] = msg
                changedMessageIds.insert(msg.id)
            }
        }

        for mid in changedMessageIds {
            if let idx = chatMessages.firstIndex(where: { $0.id == mid }) {
                saveMessageToStorage(chatMessages[idx], modelContext: modelContext)
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
        } catch {
        }
    }
    
    // MARK: - Session 管理（仅用于分段/时间戳，不生成总结）

    /// 开始新的session
    func startNewSession() {
        sessionStartTime = Date()
    }
    
    // MARK: - 调试/演示
    
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
        return message
    }

    // MARK: - Copy
    private enum MeetingCardCopy {
        /// demo / 真实流程统一：生成完成后的 AI 气泡文案
        static let agentMessageReady = "已为您创建了一份会议记录文件，长按可调整。"
        /// 真实录音生成中：避免出现“已生成”时态不一致
        static let agentMessageGenerating = "正在生成会议记录，请稍候..."
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

// MARK: - Small helpers (local)

private extension UIImage {
    func yy_resizedThumbnail(maxPixel: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > 0 else { return self }
        let scale = min(1.0, maxPixel / maxSide)
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
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


