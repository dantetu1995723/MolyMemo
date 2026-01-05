import Foundation

// 智能模型路由器 - 根据消息内容自动选择最合适的模型
class SmartModelRouter {
    
    /// 判断当前这轮对话是否需要多模态模型（只检查最新的用户消息）
    /// - Parameter messages: 聊天消息数组
    /// - Returns: 如果最新的用户消息包含图片则返回 true
    static func containsImages(in messages: [ChatMessage]) -> Bool {
        // 只检查最后一条用户消息是否有图片
        // 这样可以确保：发图片时用omni，纯文字对话时用plus（即使历史有图片）
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            return false
        }
        
        return !lastUserMessage.images.isEmpty
    }
    
    /// 统一发送消息：仅使用自有后端（Qwen 已弃用）
    /// - Parameters:
    ///   - messages: 聊天消息数组
    ///   - mode: 应用模式（工作/情感）
    ///   - onComplete: 完成回调
    ///   - onError: 错误回调
    static func sendMessageStream(
        messages: [ChatMessage],
        mode: AppMode,
        onStructuredOutput: (@MainActor (BackendChatStructuredOutput) -> Void)? = nil,
        onComplete: @escaping (String) async -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        
        guard BackendChatConfig.isEnabled else {
            await MainActor.run {
                onError(BackendChatError.invalidConfig("当前已移除 Qwen 回退，请在设置中启用自有后端"))
            }
            return
        }
        
        // 你要求的“实时后端聊天链路”日志：入口处先打一次上下文概览（不打印图片 base64）
#if DEBUG
        _ = messages.last(where: { $0.role == .user })
#else
#endif
        await BackendChatService.sendMessageStream(
            messages: messages,
            mode: mode,
            onStructuredOutput: onStructuredOutput,
            onComplete: onComplete,
            onError: onError
        )
    }
}

