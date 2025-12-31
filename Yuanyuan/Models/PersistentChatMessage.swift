import Foundation
import SwiftData
import UIKit

// SwiftData 持久化模型 - 用于存储聊天记录
@Model
final class PersistentChatMessage {
    var id: UUID
    var roleRawValue: String
    var content: String
    var timestamp: Date
    var isGreeting: Bool
    var isInterrupted: Bool = false
    var messageTypeRawValue: String
    var encodedImageData: Data?
    /// 按后端 JSON chunk 顺序的分段渲染（用于历史消息与当次会话保持一致的展示顺序）
    /// - 旧版本可能为 nil；UI 会自动走 fallback 渲染
    @Attribute(.externalStorage) var encodedSegments: Data?
    
    init(
        id: UUID,
        roleRawValue: String,
        content: String,
        timestamp: Date,
        isGreeting: Bool,
        messageTypeRawValue: String,
        encodedImageData: Data?,
        encodedSegments: Data? = nil,
        isInterrupted: Bool = false
    ) {
        self.id = id
        self.roleRawValue = roleRawValue
        self.content = content
        self.timestamp = timestamp
        self.isGreeting = isGreeting
        self.messageTypeRawValue = messageTypeRawValue
        self.encodedImageData = encodedImageData
        self.encodedSegments = encodedSegments
        self.isInterrupted = isInterrupted
    }
}

// 扩展：转换方法（不在 @Model 类内部）
extension PersistentChatMessage {
    // 从 ChatMessage 创建 PersistentChatMessage
    static func from(_ message: ChatMessage) -> PersistentChatMessage {
        let roleValue = message.role == .user ? "user" : "agent"
        let messageTypeValue: String
        switch message.messageType {
        case .text: messageTypeValue = "text"
        case .image: messageTypeValue = "image"
        case .mixed: messageTypeValue = "mixed"
        }
        
        // 将 UIImage 数组转换为 Data 数组，然后编码
        let imageDataArray = message.images.compactMap { image -> Data? in
            return image.jpegData(compressionQuality: 0.8)
        }
        
        // 使用 JSONEncoder 编码数组
        let encodedData: Data? = {
            guard !imageDataArray.isEmpty else { return nil }
            return try? JSONEncoder().encode(imageDataArray)
        }()

        // segments（可选）
        let encodedSegments: Data? = {
            guard let segs = message.segments, !segs.isEmpty else { return nil }
            return try? JSONEncoder().encode(segs)
        }()
        
        return PersistentChatMessage(
            id: message.id,
            roleRawValue: roleValue,
            content: message.content,
            timestamp: message.timestamp,
            isGreeting: message.isGreeting,
            messageTypeRawValue: messageTypeValue,
            encodedImageData: encodedData,
            encodedSegments: encodedSegments,
            isInterrupted: message.isInterrupted
        )
    }
    
    // 转换为 ChatMessage
    func toChatMessage() -> ChatMessage {
        let role: ChatMessage.MessageRole = roleRawValue == "user" ? .user : .agent
        
        // 解码并转换回 UIImage 数组
        let images: [UIImage] = {
            guard let encodedData = encodedImageData,
                  let imageDataArray = try? JSONDecoder().decode([Data].self, from: encodedData) else {
                return []
            }
            return imageDataArray.compactMap { UIImage(data: $0) }
        }()
        
        // 创建消息
        var mutableMessage: ChatMessage
        if images.isEmpty {
            // 纯文字消息
            mutableMessage = ChatMessage(id: id, role: role, content: content, isGreeting: isGreeting, timestamp: timestamp)
        } else {
            // 图片消息
            mutableMessage = ChatMessage(id: id, role: role, images: images, content: content, timestamp: timestamp)
        }
        mutableMessage.streamingState = .completed
        mutableMessage.isInterrupted = isInterrupted
        
        // 解码 segments（如果有）
        if let encodedSegments,
           let segs = try? JSONDecoder().decode([ChatSegment].self, from: encodedSegments),
           !segs.isEmpty {
            mutableMessage.segments = segs

            // ✅ 聚合字段回填：确保从 storage 加载的“分段卡片”也能正常打开详情/支持旧逻辑复用
            var schedules: [ScheduleEvent] = []
            var contacts: [ContactCard] = []
            var invoices: [InvoiceCard] = []
            var meetings: [MeetingCard] = []
            for seg in segs {
                if let s = seg.scheduleEvents, !s.isEmpty { schedules.append(contentsOf: s) }
                if let c = seg.contacts, !c.isEmpty { contacts.append(contentsOf: c) }
                if let i = seg.invoices, !i.isEmpty { invoices.append(contentsOf: i) }
                if let m = seg.meetings, !m.isEmpty { meetings.append(contentsOf: m) }
            }
            if !schedules.isEmpty { mutableMessage.scheduleEvents = schedules }
            if !contacts.isEmpty { mutableMessage.contacts = contacts }
            if !invoices.isEmpty { mutableMessage.invoices = invoices }
            if !meetings.isEmpty { mutableMessage.meetings = meetings }
        }
        return mutableMessage
    }
}

