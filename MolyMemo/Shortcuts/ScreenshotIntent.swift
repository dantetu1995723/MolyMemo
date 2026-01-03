import AppIntents
import ActivityKit
import UIKit

private let yyPendingLogPrefix = "🧩 [PendingScreenshot]"

/// Moly截图：截图后由主App按“App内发送链路”发送到聊天室（不走输入框预览步骤）
struct MollyScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Moly截图"
    static var description = IntentDescription("仅接收快捷指令传入的截图，并直接发送到Moly聊天室（不读取系统相册）")
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
        Summary("发送截图到Moly聊天室") {
            \.$screenshot
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        print("📸➡️💬 MollyScreenshotIntent 触发")
        #if DEBUG
        AppGroupDebugLog.append("MollyScreenshotIntent start")
        #endif

        let activity = await ScreenshotSendLiveActivity.start()
        await ScreenshotSendLiveActivity.update(activity, status: .sending, message: "准备截图…", thumbnailRelativePath: nil)

        // ✅ 只使用快捷指令传入的截图：不读取系统相册，不做任何兜底
        guard let image = loadUIImage(from: screenshot) else {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：截图数据无效（请把截屏输出连接到本动作的「截图」参数）", thumbnailRelativePath: nil, lingerSeconds: 0.2)
            #if DEBUG
            AppGroupDebugLog.append("invalid screenshot input (UIImage decode failed)")
            #endif
            throw MollyScreenshotError.invalidScreenshotInput
        }

        let pendingRelPath = PendingScreenshotQueue.enqueue(image: image) ?? ""
        let thumbRelPath = saveThumbnailToAppGroup(image)
        guard !pendingRelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await ScreenshotSendLiveActivity.finish(activity, status: .failed, message: "发送失败：无法写入共享空间", thumbnailRelativePath: nil, lingerSeconds: 0.2)
            #if DEBUG
            AppGroupDebugLog.append("pendingRelPath empty (cannot write App Group)")
            #endif
            throw BackendChatError.invalidConfig("无法访问 App Group 容器")
        }
        await ScreenshotSendLiveActivity.update(activity, status: .sending, message: "已交给Moly发送…", thumbnailRelativePath: thumbRelPath)
        await ScreenshotSendNotifications.postSending(thumbnailRelativePath: thumbRelPath)

        #if DEBUG
        print("\(yyPendingLogPrefix) enqueue file rel=\(pendingRelPath) thumb=\(thumbRelPath ?? "nil")")
        AppGroupDebugLog.append("enqueue rel=\(pendingRelPath) thumb=\(thumbRelPath ?? "nil")")
        #endif

        DarwinNotificationCenter.post(ChatDarwinNames.pendingScreenshot)
        #if DEBUG
        print("\(yyPendingLogPrefix) posted darwin=\(ChatDarwinNames.pendingScreenshot)")
        AppGroupDebugLog.append("post darwin \(ChatDarwinNames.pendingScreenshot)")
        #endif

        await ScreenshotSendLiveActivity.finish(activity, status: .sent, message: "已交给Moly", thumbnailRelativePath: thumbRelPath, lingerSeconds: 0.2)
        #if DEBUG
        AppGroupDebugLog.append("finish intent")
        #endif

        return .result()
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
            return "截图数据无效。请在快捷指令里把“截屏/拍摄屏幕截图”的输出连接到「Moly→Moly截图→截图」参数。"
        }
    }
}

// App 快捷指令提供器
struct YuanyuanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MollyScreenshotIntent(),
            phrases: [
                "\(.applicationName)Moly截图",
                "用\(.applicationName)Moly截图",
                "在\(.applicationName)Moly截图",
                // 兼容旧叫法，避免已有快捷指令短语失效
                "\(.applicationName)Molly截图",
                "用\(.applicationName)Molly截图",
                "在\(.applicationName)Molly截图"
            ],
            shortTitle: "Moly截图",
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

