import Foundation
import UserNotifications

/// 灵动岛停止后给用户一个“立刻反馈”：已停止并开始后台上传。
enum RecordingStopNotifier {
    static func notifyStoppedAndUploading() {
        let content = UNMutableNotificationContent()
        content.title = "Moly录音已停止"
        content.body = "正在后台上传录音，稍后会自动生成会议记录。"
        content.sound = .default

        // 立即触发
        let request = UNNotificationRequest(
            identifier: "moly.recording.stopped.uploading.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

