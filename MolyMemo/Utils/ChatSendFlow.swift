import SwiftUI
import SwiftData
import UIKit

/// 聊天消息发送流程（App 内发送统一入口）。
///
/// 目标：
/// - 统一：用户消息 -> AI 占位 -> 流式结构化回填 -> 完成落库
/// - 复用：减少 ChatView/其他入口重复实现，降低链路复杂度
@MainActor
enum ChatSendFlow {
    static func send(
        appState: AppState,
        modelContext: ModelContext,
        text: String,
        images: [UIImage] = [],
        isGreeting: Bool = false,
        includeHistory: Bool = true
    ) {
        // 只用 trim 判空；写入/发送内容保持“原始文本”
        let isEffectivelyEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !isEffectivelyEmpty || !images.isEmpty else { return }

        // 1) 用户消息（支持：纯文字 / 纯图片 / 图文混合）
        let userMsg: ChatMessage = {
            if images.isEmpty {
                return ChatMessage(role: .user, content: text, isGreeting: isGreeting)
            } else {
                return ChatMessage(role: .user, images: images, content: text)
            }
        }()

        withAnimation {
            appState.chatMessages.append(userMsg)
        }
        appState.saveMessageToStorage(userMsg, modelContext: modelContext)

        // 发送给模型的上下文：默认带历史；截图等"直发"场景可选择不带历史避免串话
        let messagesForModel: [ChatMessage] = includeHistory ? appState.chatMessages : [userMsg]

        // 2) AI 占位消息
        let agentMsg = ChatMessage(role: .agent, content: "")
        withAnimation {
            appState.chatMessages.append(agentMsg)
        }
        let messageId = agentMsg.id

        // 3) 调用 AI（结构化输出实时回填）
        appState.isAgentTyping = true
        appState.startStreaming(messageId: messageId)
        appState.currentGenerationTask = Task {
            await SmartModelRouter.sendMessageStream(
                messages: messagesForModel,
                mode: appState.currentMode,
                onStructuredOutput: { output in
                    Task { @MainActor in
                        appState.applyStructuredOutput(output, to: messageId, modelContext: modelContext)
                    }
                },
                onComplete: { finalText in
                    await appState.playResponse(finalText, for: messageId)
                    await MainActor.run {
                        appState.isAgentTyping = false
                        if let completedMessage = appState.chatMessages.first(where: { $0.id == messageId }) {
                            appState.saveMessageToStorage(completedMessage, modelContext: modelContext)
                        }
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        appState.handleStreamingError(error, for: messageId)
                        appState.isAgentTyping = false
                    }
                }
            )
        }
    }
    
    /// 立即发送占位消息并返回消息ID，用于后续更新消息内容
    static func sendPlaceholder(
        appState: AppState,
        modelContext: ModelContext,
        placeholderText: String = "",
        includeHistory: Bool = true
    ) -> UUID? {
        // 1) 创建用户占位消息
        let userMsg = ChatMessage(role: .user, content: placeholderText)
        
        withAnimation {
            appState.chatMessages.append(userMsg)
        }
        appState.saveMessageToStorage(userMsg, modelContext: modelContext)
        
        return userMsg.id
    }
    
    /// 删除占位消息（用于转录失败或结果为空的情况）
    static func removePlaceholder(
        appState: AppState,
        modelContext: ModelContext,
        messageId: UUID
    ) {
        guard let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        withAnimation {
            _ = appState.chatMessages.remove(at: index)
        }
        
        // 从存储中删除
        do {
            let descriptor = FetchDescriptor<PersistentChatMessage>(
                predicate: #Predicate { $0.id == messageId }
            )
            if let stored = try modelContext.fetch(descriptor).first {
                modelContext.delete(stored)
                try modelContext.save()
            }
        } catch {
            // 忽略删除错误
        }
    }
    
    /// 更新已存在的用户消息内容并触发AI对话
    static func updateAndSend(
        appState: AppState,
        modelContext: ModelContext,
        messageId: UUID,
        text: String,
        includeHistory: Bool = true
    ) {
        // 只用 trim 判空；写入/发送内容保持“原始文本”
        let isEffectivelyEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !isEffectivelyEmpty else {
            // 如果内容为空，删除占位消息
            removePlaceholder(appState: appState, modelContext: modelContext, messageId: messageId)
            return
        }
        
        // 更新用户消息内容
        guard let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            // 如果找不到消息，直接发送新消息
            send(appState: appState, modelContext: modelContext, text: text, includeHistory: includeHistory)
            return
        }
        
        var updatedMessage = appState.chatMessages[index]
        updatedMessage.content = text
        appState.chatMessages[index] = updatedMessage
        appState.saveMessageToStorage(updatedMessage, modelContext: modelContext)
        
        // 发送给模型的上下文
        let messagesForModel: [ChatMessage] = includeHistory ? appState.chatMessages : [updatedMessage]
        
        // 创建AI占位消息
        let agentMsg = ChatMessage(role: .agent, content: "")
        withAnimation {
            appState.chatMessages.append(agentMsg)
        }
        let agentMessageId = agentMsg.id
        
        // 调用 AI
        appState.isAgentTyping = true
        appState.startStreaming(messageId: agentMessageId)
        appState.currentGenerationTask = Task {
            await SmartModelRouter.sendMessageStream(
                messages: messagesForModel,
                mode: appState.currentMode,
                onStructuredOutput: { output in
                    Task { @MainActor in
                        appState.applyStructuredOutput(output, to: agentMessageId, modelContext: modelContext)
                    }
                },
                onComplete: { finalText in
                    await appState.playResponse(finalText, for: agentMessageId)
                    await MainActor.run {
                        appState.isAgentTyping = false
                        if let completedMessage = appState.chatMessages.first(where: { $0.id == agentMessageId }) {
                            appState.saveMessageToStorage(completedMessage, modelContext: modelContext)
                        }
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        appState.handleStreamingError(error, for: agentMessageId)
                        appState.isAgentTyping = false
                    }
                }
            )
        }
    }
}


