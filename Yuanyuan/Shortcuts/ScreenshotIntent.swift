import AppIntents
import SwiftUI
import UIKit
import SwiftData

/// Molly截图：截图后后台直发到聊天室（不打开 App，不走输入框预览路径）
struct MollyScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Molly截图"
    static var description = IntentDescription("自动获取最近一张截图并直接发送到圆圆聊天室，全程后台处理")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        print("📸➡️💬 MollyScreenshotIntent 触发")

        // 给系统一点时间把截图写入相册（尤其是自动化触发时）
        try? await Task.sleep(nanoseconds: 900_000_000)

        guard BackendChatConfig.isEnabled else {
            throw BackendChatError.invalidConfig("当前已关闭聊天后端，请在设置中启用")
        }
        guard BackendChatConfig.isConfigured else {
            throw BackendChatError.invalidConfig("聊天后端未配置，请先在设置中配置 baseURL")
        }

        guard let image = await PhotoManager.shared.fetchLatestScreenshot() else {
            throw MollyScreenshotError.noScreenshotFound
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

        // 先落地用户消息，确保打开App能看到正常用户气泡（含图片）
        context.insert(PersistentChatMessage.from(userMsg))
        try context.save()

        // 真正发给后端：禁止带 shortcut（只发 text + image_url）
        let replyText = try await sendToBackend(messages: history + [userMsg], mode: .work)

        let agentMsg = ChatMessage(role: .agent, content: replyText, timestamp: Date())
        context.insert(PersistentChatMessage.from(agentMsg))
        try context.save()

        return .result()
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

    private func sendToBackend(messages: [ChatMessage], mode: AppMode) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                await BackendChatService.sendMessageStream(
                    messages: messages,
                    mode: mode,
                    includeShortcut: false,
                    onStructuredOutput: nil,
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

enum MollyScreenshotError: LocalizedError {
    case noScreenshotFound

    var errorDescription: String? {
        switch self {
        case .noScreenshotFound:
            return "没有找到最近的截图（请确认已允许相册权限）"
        }
    }
}

// App 快捷指令提供器
struct YuanyuanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MollyScreenshotIntent(),
            phrases: [
                "\(.applicationName)Molly截图",
                "用\(.applicationName)Molly截图",
                "在\(.applicationName)Molly截图"
            ],
            shortTitle: "Molly截图",
            systemImageName: "photo.on.rectangle.angled"
        )
        
        AppShortcut(
            intent: StartMeetingRecordingIntent(),
            phrases: [
                "在\(.applicationName)Moly录音",
                "用\(.applicationName)Moly录音",
                "\(.applicationName)Moly录音"
            ],
            shortTitle: "Moly录音",
            systemImageName: "mic.circle.fill"
        )
    }
}

