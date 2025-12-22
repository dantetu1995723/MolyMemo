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
    
    /// 智能发送消息 - 自动选择 qwen-max 或 qwen-omni
    /// - Parameters:
    ///   - messages: 聊天消息数组
    ///   - mode: 应用模式（工作/情感）
    ///   - onComplete: 完成回调
    ///   - onError: 错误回调
    static func sendMessageStream(
        messages: [ChatMessage],
        mode: AppMode,
        onComplete: @escaping (String) async -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        
        // 全量调试阶段：只要启用后端，就始终走后端；配置缺失则直接报错，不回退到内置模型
        if BackendChatConfig.isEnabled {
            print("🌐 使用自有后端聊天接口（已启用，禁止回退）")
            await BackendChatService.sendMessageStream(
                messages: messages,
                mode: mode,
                onComplete: onComplete,
                onError: onError
            )
            return
        }
        
        // 判断是否需要使用多模态模型
        let hasImages = containsImages(in: messages)
        
        if hasImages {
            // 有图片 -> 使用 qwen-omni（多模态模型）
            print("🎨 检测到图片，使用 qwen-omni 模型（支持多模态 + 联网搜索）")
            await QwenOmniService.sendMessageStream(
                messages: messages,
                mode: mode,
                onComplete: onComplete,
                onError: onError
            )
        } else {
            // 纯文本 -> 使用 qwen-plus-latest（更强的文本能力 + 联网搜索）
            print("📝 纯文本对话，使用 qwen-plus-latest 模型（支持联网搜索）")
            await QwenMaxService.sendMessageStream(
                messages: messages,
                mode: mode,
                onComplete: onComplete,
                onError: onError
            )
        }
    }
}

