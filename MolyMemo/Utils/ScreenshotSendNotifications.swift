import Foundation
import UserNotifications

/// “截图发送”桌面展示：用通知横幅（带缩略图附件）提示发送中/结果。
/// - 目的：满足“截图后桌面可看见刚才截图”的体验；不依赖系统相册。
enum ScreenshotSendNotifications {
    private static let threadId = "molymemo.screenshot_send"
    private static let sendingId = "molymemo.screenshot_send.sending"
    private static let resultId = "molymemo.screenshot_send.result"

    static func postSending(thumbnailRelativePath: String?) async {
        await post(
            id: sendingId,
            title: "正在发送给MolyMemo",
            body: "已截屏，发送到MolyMemo中…",
            thumbnailRelativePath: thumbnailRelativePath
        )
    }

    static func postResult(success: Bool, thumbnailRelativePath: String?) async {
        await postResult(success: success, thumbnailRelativePath: thumbnailRelativePath, id: resultId)
    }

    /// 发送“结果通知”（可自定义 identifier，用于多张截图时不互相覆盖）
    static func postResult(success: Bool, thumbnailRelativePath: String?, id: String) async {
        await post(
            id: id,
            title: success ? "截图已发送" : "截图发送失败",
            body: success ? "已发送到MolyMemo聊天室" : "请稍后重试",
            thumbnailRelativePath: thumbnailRelativePath
        )
    }

    private static func post(id: String, title: String, body: String, thumbnailRelativePath: String?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // 不在这里强弹授权（避免打断自动化）；未授权就静默跳过。
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = threadId
        content.sound = .default

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        // 附带缩略图（展示“刚才那张截图”）
        if let url = ScreenshotSendAttributes.thumbnailURL(relativePath: thumbnailRelativePath) {
            if let attachment = makeAttachment(from: url) {
                content.attachments = [attachment]
            }
        }

        // 立即展示（走系统通知横幅/锁屏）
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await center.add(request)
    }

    private static func makeAttachment(from url: URL) -> UNNotificationAttachment? {
        // UNNotificationAttachment 需要本地文件 URL；App Group 下的 jpg 文件满足要求
        return try? UNNotificationAttachment(identifier: "thumb", url: url, options: nil)
    }
}


