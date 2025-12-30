import AppIntents
import SwiftUI
import UIKit
import SwiftData

/// Molly截图：截图后后台直发到聊天室（不打开 App，不走输入框预览路径）
struct MollyScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Molly截图"
    static var description = IntentDescription("仅接收快捷指令传入的截图，并直接发送到圆圆聊天室（不读取系统相册）")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "截图",
        description: "直接接收上一步“截屏/拍摄屏幕截图”的输出（不弹文件选择器）。",
        supportedTypeIdentifiers: [
            "public.image",
            "public.png",
            "public.jpeg",
            "public.heic"
        ],
        requestValueDialog: IntentDialog("请先在快捷指令里加「截屏」并把输出连接到这里"),
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("发送截图到圆圆聊天室") {
            \.$screenshot
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        print("📸➡️💬 MollyScreenshotIntent 触发")

        let activity = await ScreenshotSendLiveActivity.start()
        await ScreenshotSendLiveActivity.update(activity, status: .sending, message: "准备截图…", thumbnailRelativePath: nil)

        guard BackendChatConfig.isEnabled else {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：聊天后端未启用", thumbnailRelativePath: nil)
            throw BackendChatError.invalidConfig("当前已关闭聊天后端，请在设置中启用")
        }
        guard BackendChatConfig.isConfigured else {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：后端未配置", thumbnailRelativePath: nil)
            throw BackendChatError.invalidConfig("聊天后端未配置，请先在设置中配置 baseURL")
        }

        // ✅ 只使用快捷指令传入的截图：不读取系统相册，不做任何兜底
        guard let image = loadUIImage(from: screenshot) else {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：截图数据无效（请把截屏输出连接到本动作的「截图」参数）", thumbnailRelativePath: nil)
            throw MollyScreenshotError.invalidScreenshotInput
        }

        let thumbnailPath = saveThumbnailToAppGroup(image)
        await ScreenshotSendLiveActivity.update(activity, status: .sending, message: "发送中…", thumbnailRelativePath: thumbnailPath)
        await ScreenshotSendNotifications.postSending(thumbnailRelativePath: thumbnailPath)

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
        do {
            let replyText = try await sendToBackend(messages: history + [userMsg], mode: .work)

            let agentMsg = ChatMessage(role: .agent, content: replyText, timestamp: Date())
            context.insert(PersistentChatMessage.from(agentMsg))
            try context.save()

            await ScreenshotSendLiveActivity.finish(activity, status: .sent, message: "已发送", thumbnailRelativePath: thumbnailPath)
            await ScreenshotSendNotifications.postResult(success: true, thumbnailRelativePath: thumbnailPath)
        } catch {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败", thumbnailRelativePath: thumbnailPath)
            await ScreenshotSendNotifications.postResult(success: false, thumbnailRelativePath: thumbnailPath)
            throw error
        }

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

    // MARK: - Helpers

    private func loadUIImage(from file: IntentFile) -> UIImage? {
        UIImage(data: file.data)
    }

    /// 把缩略图写到 App Group，供 Widget/灵动岛读取展示
    private func saveThumbnailToAppGroup(_ image: UIImage) -> String? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupId) else {
            return nil
        }

        let dir = groupURL.appendingPathComponent("screenshot_thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let thumb = image.yy_resizedThumbnail(maxPixel: 320)
        guard let data = thumb.jpegData(compressionQuality: 0.72) else { return nil }

        let filename = "thumb_\(UUID().uuidString).jpg"
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: [.atomic])
            // 返回“相对 App Group”的路径，避免 Widget/主App 的 URL 计算不一致
            return "screenshot_thumbnails/\(filename)"
        } catch {
            print("⚠️ [MollyScreenshotIntent] 缩略图写入失败: \(error)")
            return nil
        }
    }
}

private extension UIImage {
    func yy_resizedThumbnail(maxPixel: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > 0 else { return self }
        let scale = min(1.0, maxPixel / maxSide)
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

enum MollyScreenshotError: LocalizedError {
    case invalidScreenshotInput

    var errorDescription: String? {
        switch self {
        case .invalidScreenshotInput:
            return "截图数据无效。请在快捷指令里把“截屏/拍摄屏幕截图”的输出连接到「圆圆→Molly截图→截图」参数。"
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

