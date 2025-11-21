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
    var messageTypeRawValue: String
    var encodedImageData: Data?
    
    init(
        id: UUID,
        roleRawValue: String,
        content: String,
        timestamp: Date,
        isGreeting: Bool,
        messageTypeRawValue: String,
        encodedImageData: Data?
    ) {
        self.id = id
        self.roleRawValue = roleRawValue
        self.content = content
        self.timestamp = timestamp
        self.isGreeting = isGreeting
        self.messageTypeRawValue = messageTypeRawValue
        self.encodedImageData = encodedImageData
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
        
        return PersistentChatMessage(
            id: message.id,
            roleRawValue: roleValue,
            content: message.content,
            timestamp: message.timestamp,
            isGreeting: message.isGreeting,
            messageTypeRawValue: messageTypeValue,
            encodedImageData: encodedData
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
        let message: ChatMessage
        if images.isEmpty {
            // 纯文字消息
            message = ChatMessage(role: role, content: content, isGreeting: isGreeting, timestamp: timestamp)
        } else {
            // 图片消息
            message = ChatMessage(role: role, images: images, content: content, timestamp: timestamp)
        }
        
        var mutableMessage = message
        mutableMessage.streamingState = .completed
        return mutableMessage
    }
}

