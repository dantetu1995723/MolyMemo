import Foundation

/// 后端聊天结构化输出：用于把 `card` 这类结果回填到 ChatMessage 的卡片字段里
struct BackendChatStructuredOutput: Equatable {
    var text: String = ""
    var taskId: String? = nil

    var scheduleEvents: [ScheduleEvent] = []
    var contacts: [ContactCard] = []
    var invoices: [InvoiceCard] = []
    var meetings: [MeetingCard] = []

    /// tool 中间态：用于前端在没有卡片产出前展示 loading（例如 contacts_create start）
    var isContactToolRunning: Bool = false

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (taskId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        scheduleEvents.isEmpty &&
        contacts.isEmpty &&
        invoices.isEmpty &&
        meetings.isEmpty &&
        !isContactToolRunning
    }
}


