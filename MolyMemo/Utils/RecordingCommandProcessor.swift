import Foundation

/// 录音跨进程命令兜底处理：
/// - AppIntent / Widget 可能先写入 App Group defaults，再发 Darwin 通知；
/// - 但当 `openAppWhenRun = true` 时，Darwin 通知可能在主 App 监听注册前发出并丢失；
/// - 因此主 App 在启动/激活时主动拉取 pending command，并用时间戳去重，保证“一次点击就生效”。
final class RecordingCommandProcessor {
    static let shared = RecordingCommandProcessor()

    private init() {}

    private enum Command: String {
        case start
        case pause
        case resume
        case stop
    }

    /// 如果存在“比 lastHandled 更新”的 pending command，则执行一次并写入 lastHandledTimestamp。
    @MainActor
    func processIfNeeded(source: String = "unknown") {
        guard let defaults = UserDefaults(suiteName: RecordingSharedDefaults.suite) else { return }

        let ts = defaults.double(forKey: RecordingSharedDefaults.commandTimestampKey)
        let lastHandled = defaults.double(forKey: RecordingSharedDefaults.lastHandledTimestampKey)

        guard ts > 0, ts > lastHandled else { return }
        guard let raw = defaults.string(forKey: RecordingSharedDefaults.pendingCommandKey),
              let command = Command(rawValue: raw) else { return }

        // 先标记为已处理，避免触发两路（Darwin + onAppear / active）时重复执行。
        defaults.set(ts, forKey: RecordingSharedDefaults.lastHandledTimestampKey)
        defaults.synchronize()

        switch command {
        case .start:
            let shouldNavigateToChat = defaults.bool(forKey: RecordingSharedDefaults.shouldNavigateToChatRoomKey)
            let autoMinimize = defaults.bool(forKey: RecordingSharedDefaults.autoMinimizeKey)
            let publishTranscriptionToUI = defaults.object(forKey: RecordingSharedDefaults.publishTranscriptionToUIKey) == nil
                ? true
                : defaults.bool(forKey: RecordingSharedDefaults.publishTranscriptionToUIKey)

            NotificationCenter.default.post(
                name: NSNotification.Name("StartRecordingFromWidget"),
                object: nil,
                userInfo: [
                    "shouldNavigateToChatRoom": shouldNavigateToChat,
                    "autoMinimize": autoMinimize,
                    "publishTranscriptionToUI": publishTranscriptionToUI
                ]
            )

        case .pause:
            LiveRecordingManager.shared.pauseRecording()

        case .resume:
            LiveRecordingManager.shared.resumeRecording()

        case .stop:
            let shouldNavigateToChat = defaults.bool(forKey: RecordingSharedDefaults.shouldNavigateToChatRoomKey)
            NotificationCenter.default.post(
                name: NSNotification.Name("StopRecordingFromWidget"),
                object: nil,
                userInfo: [
                    "shouldNavigateToChatRoom": shouldNavigateToChat
                ]
            )
        }
    }
}


