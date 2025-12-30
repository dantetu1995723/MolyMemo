import Foundation

/// 后端聊天结构化输出：用于把 `card` 这类结果回填到 ChatMessage 的卡片字段里
struct BackendChatStructuredOutput: Equatable {
    var text: String = ""
    var taskId: String? = nil

    /// 是否为流式增量（delta）输出：为 true 时，AppState 应进行“追加/合并”，而不是覆盖整条消息
    var isDelta: Bool = false

    /// 保留后端 chunk 的顺序，用于前端“按 JSON 分段输出”（文字/卡片/文字…）
    var segments: [ChatSegment] = []

    var scheduleEvents: [ScheduleEvent] = []
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
        segments.isEmpty &&
        scheduleEvents.isEmpty &&
        contacts.isEmpty &&
        invoices.isEmpty &&
        meetings.isEmpty &&
        !isContactToolRunning &&
        !isScheduleToolRunning
    }
}


