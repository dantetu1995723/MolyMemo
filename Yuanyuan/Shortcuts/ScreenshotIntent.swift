import AppIntents
import ActivityKit
import SwiftUI
import UIKit
import SwiftData
import CryptoKit

// MARK: - Background streaming persistence (AppIntent -> SwiftData -> Darwin notify)

/// 后台发送收敛器：避免“超时/完成/失败”多条路径同时触发导致重复落库/重复结束 Live Activity。
private actor BackgroundSendGate {
    private var finished: Bool = false
    func tryFinish() -> Bool {
        if finished { return false }
        finished = true
        return true
    }
}

/// AppIntent 后台流式发送时：节流把增量结构化输出写回同一条 AI 消息，避免“等整包返回才一次性刷新”。
private actor BackgroundAgentStreamPersister {
    private let agentMessageId: UUID
    private let placeholderTimestamp: Date
    private let throttleNanos: UInt64

    private var message: ChatMessage
    private var scheduledFlush: Task<Void, Never>?
    private var finished: Bool = false

    init(agentMessageId: UUID, placeholderTimestamp: Date, initialContent: String, throttleMillis: UInt64 = 160) {
        self.agentMessageId = agentMessageId
        self.placeholderTimestamp = placeholderTimestamp
        self.throttleNanos = max(40, throttleMillis) * 1_000_000
        self.message = ChatMessage(id: agentMessageId, role: .agent, content: initialContent, timestamp: placeholderTimestamp)
    }

    func receive(_ delta: BackendChatStructuredOutput) {
        guard !finished else { return }
        StructuredOutputApplier.apply(delta, to: &message)
        scheduleFlushIfNeeded()
    }

    func complete(finalText: String) async {
        guard !finished else { return }
        finished = true

        // 完成态：用最终文本覆盖一次（segments/卡片以累积为准）
        let normalized = BackendChatService.normalizeDisplayText(finalText)
        if !normalized.isEmpty {
            message.content = normalized
        }
        await flushNow()
    }

    func fail(errorText: String) async {
        guard !finished else { return }
        finished = true
        message.content = errorText
        await flushNow()
    }

    private func scheduleFlushIfNeeded() {
        guard scheduledFlush == nil else { return }
        scheduledFlush = Task { [throttleNanos] in
            try? await Task.sleep(nanoseconds: throttleNanos)
            await flushNow()
        }
    }

    private func flushNow() async {
        scheduledFlush?.cancel()
        scheduledFlush = nil

        let snapshot = message
        await MainActor.run {
            do {
                let container = try SharedModelContainer.makeContainer()
                let context = container.mainContext
                try upsertPersistentChatMessageForIntent(snapshot, in: context)
                try context.save()
                postChatStorageUpdatedForIntent(agentMessageId: snapshot.id)
            } catch {
                print("⚠️ [MollyScreenshotIntent] 流式写回失败: \(error)")
            }
        }
    }
}

@MainActor
private func upsertPersistentChatMessageForIntent(_ message: ChatMessage, in context: ModelContext) throws {
    let mid = message.id
    let descriptor = FetchDescriptor<PersistentChatMessage>(
        predicate: #Predicate<PersistentChatMessage> { msg in
            msg.id == mid
        }
    )
    if let existing = try context.fetch(descriptor).first {
        let updated = PersistentChatMessage.from(message)
        existing.roleRawValue = updated.roleRawValue
        existing.content = updated.content
        existing.timestamp = updated.timestamp
        existing.isGreeting = updated.isGreeting
        existing.messageTypeRawValue = updated.messageTypeRawValue
        existing.encodedImageData = updated.encodedImageData
        existing.encodedSegments = updated.encodedSegments
        existing.isInterrupted = updated.isInterrupted
    } else {
        context.insert(PersistentChatMessage.from(message))
    }
}

private func postChatStorageUpdatedForIntent(agentMessageId: UUID) {
    let defaults = UserDefaults(suiteName: SharedModelContainer.appGroupId)
    defaults?.set(agentMessageId.uuidString, forKey: ChatSharedDefaults.lastInsertedAgentMessageIdKey)
    defaults?.set(Date().timeIntervalSince1970, forKey: ChatSharedDefaults.lastUpdateTimestampKey)
    DarwinNotificationCenter.post(ChatDarwinNames.chatUpdated)
}

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
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：聊天后端未启用", thumbnailRelativePath: nil, lingerSeconds: 0.2)
            throw BackendChatError.invalidConfig("当前已关闭聊天后端，请在设置中启用")
        }
        guard BackendChatConfig.isConfigured else {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：后端未配置", thumbnailRelativePath: nil, lingerSeconds: 0.2)
            throw BackendChatError.invalidConfig("聊天后端未配置，请先在设置中配置 baseURL")
        }

        // ✅ 只使用快捷指令传入的截图：不读取系统相册，不做任何兜底
        guard let image = loadUIImage(from: screenshot) else {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：截图数据无效（请把截屏输出连接到本动作的「截图」参数）", thumbnailRelativePath: nil, lingerSeconds: 0.2)
            throw MollyScreenshotError.invalidScreenshotInput
        }

        let thumbnailPath = saveThumbnailToAppGroup(image)
        await ScreenshotSendLiveActivity.update(activity, status: .sending, message: "发送中…", thumbnailRelativePath: thumbnailPath)
        await ScreenshotSendNotifications.postSending(thumbnailRelativePath: thumbnailPath)

        // 读写同一份 SwiftData（App Group store）
        let container = try SharedModelContainer.makeContainer()
        let context = container.mainContext

        // ⚠️ 关键修复：
        // 快捷指令“发图直传”默认不要带历史聊天上下文，否则后端会受历史内容影响，
        // 在用户这次输入（content 为空、仅图片）时很容易生成“与本次图片无关”的回答，看起来像缓存/串话。
        // 如需“带上下文”的版本，建议做成设置开关再启用。
        let history: [ChatMessage] = []

        let userMsg = ChatMessage(
            role: .user,
            images: [image],
            // 需求：快捷指令截图直发后端时，不注入任何固定文案，纯图片即可
            content: "",
            timestamp: Date()
        )

        // 先落地用户消息，确保打开App能看到正常用户气泡（含图片）
        context.insert(PersistentChatMessage.from(userMsg))
        
        // ✅ 与 App 内发送保持一致：同时落地一个 AI 占位气泡（同一条气泡后续会被更新，而不是再插入新消息）
        let agentId = UUID()
        let placeholderTs = userMsg.timestamp.addingTimeInterval(0.001)
        let agentPlaceholder = ChatMessage(id: agentId, role: .agent, content: "正在思考...", timestamp: placeholderTs)
        context.insert(PersistentChatMessage.from(agentPlaceholder))

#if DEBUG
        // 用图片数据做一个短指纹，帮助对齐“我这次到底发的是哪张图”
        if let data = image.jpegData(compressionQuality: 0.9) {
            let digest = SHA256.hash(data: data)
            let short = digest.compactMap { String(format: "%02x", $0) }.prefix(8).joined()
            print("🧾 [MollyScreenshotIntent] image bytes=\(data.count) sha256=\(short) agentId=\(agentId)")
        }
#endif
        
        try context.save()

        // 通知主App：有新的聊天数据（跨进程）。这里先通知一次（出现 AI 占位气泡）
        postChatStorageUpdatedForIntent(agentMessageId: agentId)

        // ✅ 关键：不要在 AppIntent 内 await 网络流式完成（Shortcuts 会超时中断）
        // 这里快速返回；后台任务继续完成发送与落地 AI 回复，并通过 Live Activity/通知反馈结果。
        launchBackgroundSend(
            messages: history + [userMsg],
            mode: .work,
            thumbnailRelativePath: thumbnailPath,
            activity: activity,
            agentMessageId: agentId,
            placeholderTimestamp: placeholderTs
        )

        return .result()
    }

    // MARK: - Network/AI

    private func launchBackgroundSend(
        messages: [ChatMessage],
        mode: AppMode,
        thumbnailRelativePath: String?,
        activity: Activity<ScreenshotSendAttributes>?,
        agentMessageId: UUID,
        placeholderTimestamp: Date
    ) {
        // 发送逻辑在后台执行，避免阻塞 Intent（Shortcuts 有执行时限，超时就会显示“被中断”）。
        Task.detached(priority: .utility) {
            let bgTaskId: UIBackgroundTaskIdentifier = await MainActor.run {
                UIApplication.shared.beginBackgroundTask(withName: "yy.molly.screenshot.send")
            }
            defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskId) } }

            // ✅ 大幅放宽：原来 55s 的“任务组超时 + cancelAll”会直接取消 URLSession（表现为 -999 cancelled）
            // 这里改为：
            // - 超时更长（180s）
            // - 不主动 cancel 网络请求（让系统决定是否继续）
            // - 仅让第一条结果路径生效（完成/失败/超时）
            let timeoutNanos: UInt64 = 180 * 1_000_000_000
            let gate = BackgroundSendGate()

            // ✅ 把流式中间态实时写回 SwiftData（节流），让聊天室能边收边显示
            let persister = BackgroundAgentStreamPersister(
                agentMessageId: agentMessageId,
                placeholderTimestamp: placeholderTimestamp,
                initialContent: "正在思考..."
            )

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                guard await gate.tryFinish() else { return }
                await persister.fail(errorText: "发送超时：后台执行时间不足")
                await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送超时", thumbnailRelativePath: thumbnailRelativePath, lingerSeconds: 0.2)
                await ScreenshotSendNotifications.postResult(success: false, thumbnailRelativePath: thumbnailRelativePath)
            }

            await BackendChatService.sendMessageStream(
                messages: messages,
                mode: mode,
                includeShortcut: false,
                onStructuredOutput: { delta in
                    Task { await persister.receive(delta) }
                },
                onComplete: { finalText in
                    guard await gate.tryFinish() else { return }
                    await persister.complete(finalText: finalText)
                    await ScreenshotSendLiveActivity.finish(activity, status: .sent, message: "已发送", thumbnailRelativePath: thumbnailRelativePath, lingerSeconds: 0.2)
                    await ScreenshotSendNotifications.postResult(success: true, thumbnailRelativePath: thumbnailRelativePath)
                },
                onError: { error in
                    Task {
                        guard await gate.tryFinish() else { return }

                        let ns = error as NSError
                        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                            // -999：请求被取消（常见原因：系统收回后台时间、用户切前后台、或上层任务取消）
                            print("🛑 [MollyScreenshotIntent] 网络请求被取消(-999)：通常是后台时间不足或任务被系统/上层取消。")
                            await persister.fail(errorText: "发送中止：后台网络请求被系统取消（-999）")
                        } else {
                            await persister.fail(errorText: "发送失败：\(error.localizedDescription)")
                        }
                        await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败", thumbnailRelativePath: thumbnailRelativePath, lingerSeconds: 0.2)
                        await ScreenshotSendNotifications.postResult(success: false, thumbnailRelativePath: thumbnailRelativePath)
                    }
                    print("❌ [MollyScreenshotIntent] 后台发送失败: \(error)")
                }
            )

            timeoutTask.cancel()
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

