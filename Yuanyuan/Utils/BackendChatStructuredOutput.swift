import Foundation

/// 后端聊天结构化输出：用于把 `card` 这类结果回填到 ChatMessage 的卡片字段里
struct BackendChatStructuredOutput: Equatable {
    var text: String = ""
    var taskId: String? = nil

    var scheduleEvents: [ScheduleEvent] = []
    var contacts: [ContactCard] = []
    var invoices: [InvoiceCard] = []
    var meetings: [MeetingCard] = []

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (taskId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        scheduleEvents.isEmpty &&
        contacts.isEmpty &&
        invoices.isEmpty &&
        meetings.isEmpty
    }
}


