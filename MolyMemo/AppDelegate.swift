import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 用于承接 background URLSession 的回调（SwiftUI App 也需要 UIApplicationDelegate 才能被系统唤起处理完成事件）。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 兜底：尽早安装录音 Darwin 监听
        RecordingDarwinObserver.shared.installIfNeeded()
        // 兜底：初始化后台上传器（确保 session delegate 常驻）
        _ = MeetingMinutesBackgroundUploader.shared

        // 飞书移动端 SSO SDK 初始化（如果已集成）
        FeishuSSOBridge.setupIfPossible()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == MeetingMinutesBackgroundUploader.backgroundSessionIdentifier {
            MeetingMinutesBackgroundUploader.shared.backgroundSessionCompletionHandler = completionHandler
        } else {
            completionHandler()
        }
    }
}

