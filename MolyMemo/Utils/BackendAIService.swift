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
                    // ✅ 纯文本/小任务：禁用 shortcut（避免触发后端工具链与中间态“需要使用工具...”混入最终文本）
                    includeShortcut: false,
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
}


