import AppIntents
import ActivityKit
import SwiftData
import UIKit

// “后台发送最新截图到聊天室”——不打开主界面
struct SendLatestScreenshotToChatIntent: AppIntent {
    static var title: LocalizedStringResource = "截图后发送到聊天室"
    static var description = IntentDescription("自动获取最近一张截图并发送到圆圆聊天室，全程后台处理")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        print("📸➡️💬 SendLatestScreenshotToChatIntent 触发")

        // 给系统一点时间把截图写入相册（尤其是自动化触发时）
        try? await Task.sleep(nanoseconds: 900_000_000)

        // 灵动岛提示：发送中
        let activity = await startLiveActivityIfPossible()

        do {
            guard let image = await PhotoManager.shared.fetchLatestScreenshot() else {
                throw ScreenshotSendError.noScreenshotFound
            }

            // 读写同一份 SwiftData（App Group store）
            let container = try SharedModelContainer.makeContainer()
            let context = container.mainContext

            // 取最近若干条上下文（避免 token 爆炸）
            let history = try fetchRecentMessages(modelContext: context, limit: 8)

            let userMsg = ChatMessage(
                role: .user,
                images: [image],
                content: "请帮我分析这张截图",
                timestamp: Date()
            )

            // 先落地用户消息，确保“已发送”后打开App能看到
            context.insert(PersistentChatMessage.from(userMsg))
            try context.save()

            // 真正发给后端/模型（在 AppIntent 进程里完成，不依赖主App UI）
            let replyText = try await sendToAI(messages: history + [userMsg], mode: .work)

            let agentMsg = ChatMessage(role: .agent, content: replyText, timestamp: Date())
            context.insert(PersistentChatMessage.from(agentMsg))
            try context.save()

            await finishLiveActivityIfPossible(activity, success: true, message: "已发送到聊天室")
            return .result()
        } catch {
            await finishLiveActivityIfPossible(activity, success: false, message: "发送失败")
            throw error
        }
    }

    // MARK: - Live Activity

    private func startLiveActivityIfPossible() async -> Any? {
        guard #available(iOS 16.1, *) else { return nil }
        return await ScreenshotSendLiveActivity.start()
    }

    private func finishLiveActivityIfPossible(_ token: Any?, success: Bool, message: String) async {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = token as? Activity<ScreenshotSendAttributes> else { return }
        let status: ScreenshotSendAttributes.ContentState.Status = success ? .sent : .failed
        await ScreenshotSendLiveActivity.finish(activity, status: status, message: message, lingerSeconds: 2.0)
    }

    // MARK: - Storage

    private func fetchRecentMessages(modelContext: ModelContext, limit: Int) throws -> [ChatMessage] {
        var descriptor = FetchDescriptor<PersistentChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        let persistents = try modelContext.fetch(descriptor)
        // 反转成“从早到晚”，与 ChatView 一致
        return persistents.reversed().map { $0.toChatMessage() }
    }

    // MARK: - Network/AI

    private func sendToAI(messages: [ChatMessage], mode: AppMode) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                await SmartModelRouter.sendMessageStream(
                    messages: messages,
                    mode: mode,
                    onComplete: { finalText in
                        continuation.resume(returning: finalText)
                    },
                    onError: { error in
                        continuation.resume(throwing: error)
                    }
                )
            }
        }
    }
}

enum ScreenshotSendError: LocalizedError {
    case noScreenshotFound

    var errorDescription: String? {
        switch self {
        case .noScreenshotFound:
            return "没有找到最近的截图（请确认已允许相册权限）"
        }
    }
}


