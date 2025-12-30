import Foundation
import ActivityKit

@available(iOS 16.1, *)
enum ScreenshotSendLiveActivity {
    static func start() async -> Activity<ScreenshotSendAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ [ScreenshotSendLiveActivity] Live Activity 未启用")
            return nil
        }

        let attributes = ScreenshotSendAttributes(title: "发送截图")
        let state = ScreenshotSendAttributes.ContentState(status: .sending, message: "发送中…", thumbnailRelativePath: nil)
        do {
            let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100.0)
            let activity = try Activity<ScreenshotSendAttributes>.request(attributes: attributes, content: content, pushType: nil)
            print("✅ [ScreenshotSendLiveActivity] 已启动")
            return activity
        } catch {
            print("❌ [ScreenshotSendLiveActivity] 启动失败: \(error)")
            return nil
        }
    }

    static func update(
        _ activity: Activity<ScreenshotSendAttributes>?,
        status: ScreenshotSendAttributes.ContentState.Status,
        message: String,
        thumbnailRelativePath: String? = nil
    ) async {
        guard let activity else { return }
        let state = ScreenshotSendAttributes.ContentState(status: status, message: message, thumbnailRelativePath: thumbnailRelativePath)
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100.0)
        await activity.update(content)
    }

    static func finish(
        _ activity: Activity<ScreenshotSendAttributes>?,
        status: ScreenshotSendAttributes.ContentState.Status,
        message: String,
        thumbnailRelativePath: String? = nil,
        lingerSeconds: Double = 2.0
    ) async {
        guard let activity else { return }
        await update(activity, status: status, message: message, thumbnailRelativePath: thumbnailRelativePath)
        let ns = UInt64(max(0.1, lingerSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
        let state = ScreenshotSendAttributes.ContentState(status: status, message: message, thumbnailRelativePath: thumbnailRelativePath)
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100.0)
        if #available(iOS 16.2, *) {
            await activity.end(content, dismissalPolicy: .after(.now + 1.0))
        } else {
            await activity.end(dismissalPolicy: .after(.now + 1.0))
        }
    }
}


