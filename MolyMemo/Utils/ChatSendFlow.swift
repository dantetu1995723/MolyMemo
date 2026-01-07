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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }

        // 1) 用户消息（支持：纯文字 / 纯图片 / 图文混合）
        let userMsg: ChatMessage = {
            if images.isEmpty {
                return ChatMessage(role: .user, content: trimmed, isGreeting: isGreeting)
            } else {
                return ChatMessage(role: .user, images: images, content: trimmed)
            }
        }()

        withAnimation {
            appState.chatMessages.append(userMsg)
        }
        appState.saveMessageToStorage(userMsg, modelContext: modelContext)

        // 发送给模型的上下文：默认带历史；截图等“直发”场景可选择不带历史避免串话
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
}


