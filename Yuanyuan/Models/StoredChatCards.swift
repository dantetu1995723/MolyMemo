import Foundation
import SwiftData

// MARK: - 聊天室卡片持久化（资料库）

/// 存储「日程卡片」的一次批次（通常对应聊天室里一次卡片输出）
@Model
final class StoredScheduleCardBatch {
    var id: UUID
    var createdAt: Date
    var sourceMessageId: UUID?
    @Attribute(.externalStorage) var encodedEvents: Data

    init(events: [ScheduleEvent], sourceMessageId: UUID? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.sourceMessageId = sourceMessageId
        self.encodedEvents = (try? JSONEncoder().encode(events)) ?? Data()
    }

    func decodedEvents() -> [ScheduleEvent] {
        (try? JSONDecoder().decode([ScheduleEvent].self, from: encodedEvents)) ?? []
    }

    func update(events: [ScheduleEvent]) {
        encodedEvents = (try? JSONEncoder().encode(events)) ?? Data()
    }
}

/// 存储「联系人卡片」的一次批次
@Model
final class StoredContactCardBatch {
    var id: UUID
    var createdAt: Date
    var sourceMessageId: UUID?
    @Attribute(.externalStorage) var encodedContacts: Data

    init(contacts: [ContactCard], sourceMessageId: UUID? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.sourceMessageId = sourceMessageId
        self.encodedContacts = (try? JSONEncoder().encode(contacts)) ?? Data()
    }

    func decodedContacts() -> [ContactCard] {
        (try? JSONDecoder().decode([ContactCard].self, from: encodedContacts)) ?? []
    }

    func update(contacts: [ContactCard]) {
        encodedContacts = (try? JSONEncoder().encode(contacts)) ?? Data()
    }
}

/// 存储「发票卡片」的一次批次
@Model
final class StoredInvoiceCardBatch {
    var id: UUID
    var createdAt: Date
    var sourceMessageId: UUID?
    @Attribute(.externalStorage) var encodedInvoices: Data

    init(invoices: [InvoiceCard], sourceMessageId: UUID? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.sourceMessageId = sourceMessageId
        self.encodedInvoices = (try? JSONEncoder().encode(invoices)) ?? Data()
    }

    func decodedInvoices() -> [InvoiceCard] {
        (try? JSONDecoder().decode([InvoiceCard].self, from: encodedInvoices)) ?? []
    }

    func update(invoices: [InvoiceCard]) {
        encodedInvoices = (try? JSONEncoder().encode(invoices)) ?? Data()
    }
}

/// 存储「会议纪要卡片」的一次批次
@Model
final class StoredMeetingCardBatch {
    var id: UUID
    var createdAt: Date
    var sourceMessageId: UUID?
    @Attribute(.externalStorage) var encodedMeetings: Data

    init(meetings: [MeetingCard], sourceMessageId: UUID? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.sourceMessageId = sourceMessageId
        self.encodedMeetings = (try? JSONEncoder().encode(meetings)) ?? Data()
    }

    func decodedMeetings() -> [MeetingCard] {
        (try? JSONDecoder().decode([MeetingCard].self, from: encodedMeetings)) ?? []
    }

    func update(meetings: [MeetingCard]) {
        encodedMeetings = (try? JSONEncoder().encode(meetings)) ?? Data()
    }
}


