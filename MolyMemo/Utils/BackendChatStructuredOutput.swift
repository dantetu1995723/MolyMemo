import Foundation

/// 后端聊天结构化输出：用于把 `card` 这类结果回填到 ChatMessage 的卡片字段里
struct BackendChatStructuredOutput: Equatable {
    var text: String = ""
    var taskId: String? = nil
    /// 后端 message_id（用于“重新生成”等需要引用后端消息ID的场景）
    var messageId: String? = nil

    /// 是否为流式增量（delta）输出：为 true 时，AppState 应进行“追加/合并”，而不是覆盖整条消息
    var isDelta: Bool = false

    /// 保留后端 chunk 的顺序，用于前端“按 JSON 分段输出”（文字/卡片/文字…）
    var segments: [ChatSegment] = []

    var scheduleEvents: [ScheduleEvent] = []
    /// 从工具调用（例如 schedules_delete）解析出的“被删除日程 remoteId”列表。
    /// - 用途：让前端把历史消息里的对应日程卡片置灰（isObsolete=true）
    /// - 注意：该字段不会自动生成卡片 UI，仅用于状态回写与列表刷新触发
    var deletedScheduleRemoteIds: [String] = []
    var contacts: [ContactCard] = []
    var invoices: [InvoiceCard] = []
    var meetings: [MeetingCard] = []

    /// tool 中间态：用于前端在没有卡片产出前展示 loading（例如 contacts_create start）
    var isContactToolRunning: Bool = false
    /// tool 中间态：用于前端在没有卡片产出前展示 loading（例如 schedules_create start）
    var isScheduleToolRunning: Bool = false

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (taskId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        (messageId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        segments.isEmpty &&
        scheduleEvents.isEmpty &&
        deletedScheduleRemoteIds.isEmpty &&
        contacts.isEmpty &&
        invoices.isEmpty &&
        meetings.isEmpty &&
        !isContactToolRunning &&
        !isScheduleToolRunning
    }
}


