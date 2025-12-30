import Foundation

/// 聊天消息的“分段渲染单元”：用于按后端 JSON chunk 顺序展示（文字/卡片/文字…）
struct ChatSegment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case text
        case scheduleCards
        case contactCards
        case invoiceCards
        case meetingCards
    }

    var id: UUID = UUID()
    var kind: Kind

    // MARK: - Payload
    var text: String? = nil
    var scheduleEvents: [ScheduleEvent]? = nil
    var contacts: [ContactCard]? = nil
    var invoices: [InvoiceCard]? = nil
    var meetings: [MeetingCard]? = nil

    // MARK: - Convenience
    static func text(_ s: String) -> ChatSegment {
        ChatSegment(kind: .text, text: s)
    }
    static func scheduleCards(_ events: [ScheduleEvent]) -> ChatSegment {
        ChatSegment(kind: .scheduleCards, scheduleEvents: events)
    }
    static func contactCards(_ cards: [ContactCard]) -> ChatSegment {
        ChatSegment(kind: .contactCards, contacts: cards)
    }
    static func invoiceCards(_ cards: [InvoiceCard]) -> ChatSegment {
        ChatSegment(kind: .invoiceCards, invoices: cards)
    }
    static func meetingCards(_ cards: [MeetingCard]) -> ChatSegment {
        ChatSegment(kind: .meetingCards, meetings: cards)
    }
}


