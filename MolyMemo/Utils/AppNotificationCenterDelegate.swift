import Foundation
import UserNotifications

/// 让 App 在前台时也能展示系统通知横幅。
///
/// 默认行为：App 在前台时，本地通知不会弹横幅/声音；
/// 这里通过实现 UNUserNotificationCenterDelegate 来允许展示。
final class AppNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationCenterDelegate()
    
    private override init() {
        super.init()
    }
    
    /// 前台展示策略：允许 banner + 声音（与用户预期一致）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 目前不做点击跳转；后续如需跳到具体日程，可在这里解析 identifier/userInfo
        completionHandler()
    }
}

