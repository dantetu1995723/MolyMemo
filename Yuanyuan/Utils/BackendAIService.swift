import Foundation
import UIKit

/// 统一的“文本/多模态小任务”入口：全部走自有后端，不再依赖任何 Qwen/DashScope 客户端代码。
final class BackendAIService {
    private init() {}
    
    /// 让后端执行一个一次性任务，返回纯文本结果。
    static func generateText(
        prompt: String,
        images: [UIImage] = [],
        mode: AppMode = .work
    ) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return "" }
        
        return try await withCheckedThrowingContinuation { continuation in
            let userMsg: ChatMessage = {
                if images.isEmpty {
                    return ChatMessage(role: .user, content: trimmed)
                } else {
                    return ChatMessage(role: .user, images: images, content: trimmed)
                }
            }()
            
            // 避免 onComplete/onError 双回调导致重复 resume
            let lock = NSLock()
            var finished = false
            func finish(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            
            Task {
                await BackendChatService.sendMessageStream(
                    messages: [userMsg],
                    mode: mode,
                    onStructuredOutput: nil,
                    onComplete: { text in
                        finish(.success(text))
                    },
                    onError: { error in
                        finish(.failure(error))
                    }
                )
            }
        }
    }
    
    /// 生成聊天总结（用于 DailyChatSummary / SessionSummary）
    static func generateChatSummary(
        messages: [ChatMessage],
        date: Date
    ) async throws -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd"
        let day = df.string(from: date)
        
        // 压缩上下文：只保留最近一段，避免 prompt 过长
        let real = messages.filter { !$0.isGreeting }
        let recent = Array(real.suffix(40))
        
        let transcript = recent.map { msg in
            let role = (msg.role == .user) ? "用户" : "助理"
            let text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(role)：\(text.isEmpty ? "（空）" : text)"
        }.joined(separator: "\n")
        
        let prompt = """
        请基于以下聊天记录，为 \(day) 生成一段简洁总结。
        
        要求：
        - 100~220 字
        - 只输出总结正文，不要标题/序号/markdown
        - 聚焦：做了什么、决定了什么、下一步是什么（如果有）
        
        聊天记录：
        \(transcript)
        """
        
        return try await generateText(prompt: prompt, mode: .work)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


