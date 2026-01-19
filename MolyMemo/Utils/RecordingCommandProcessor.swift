import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
            let useBackgroundUploader = defaults.bool(forKey: RecordingSharedDefaults.useBackgroundUploaderKey)

            // 关键：当 App 仅在后台（无 SwiftUI Scene）时，Start/Stop 不能依赖 View 的 onReceive。
            // - 前台：维持原逻辑，让 UI 自己处理跳转/插入气泡等。
            // - 后台：直接启动录音，绕过 UI。
            #if canImport(UIKit)
            if UIApplication.shared.applicationState == .active {
                NotificationCenter.default.post(
                    name: NSNotification.Name("StartRecordingFromWidget"),
                    object: nil,
                    userInfo: [
                        "shouldNavigateToChatRoom": shouldNavigateToChat,
                        "autoMinimize": autoMinimize,
                        "publishTranscriptionToUI": publishTranscriptionToUI
                    ]
                )
            } else {
                LiveRecordingManager.shared.startRecording(
                    publishTranscriptionToUI: publishTranscriptionToUI,
                    uploadToChat: true,
                    updateMeetingList: false,
                    useBackgroundUploader: useBackgroundUploader
                )
            }
            #else
            // 无 UIKit 环境：直接走后台录音（通常不会发生在主 App 场景）
            LiveRecordingManager.shared.startRecording(
                publishTranscriptionToUI: publishTranscriptionToUI,
                uploadToChat: true,
                updateMeetingList: false,
                useBackgroundUploader: useBackgroundUploader
            )
            #endif

        case .pause:
            LiveRecordingManager.shared.pauseRecording()

        case .resume:
            LiveRecordingManager.shared.resumeRecording()

        case .stop:
            let shouldNavigateToChat = defaults.bool(forKey: RecordingSharedDefaults.shouldNavigateToChatRoomKey)
            // 先确保“立刻停止”生效（不依赖 UI）
            LiveRecordingManager.shared.stopRecording(modelContext: nil)

            // 仍然发送 UI 通知：如果 App 在前台，原有“跳转/生成气泡/刷新列表”逻辑保持不变。
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


