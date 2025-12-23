import Foundation

/// 录音跨进程命令监听（Darwin Notify -> 主App）
///
/// 注意：Darwin 通知不携带 payload，需要配合 App Group UserDefaults 读取参数。
final class RecordingDarwinObserver {
    static let shared = RecordingDarwinObserver()

    private var token: UnsafeRawPointer?
    private var installed = false

    private init() {}

    func installIfNeeded() {
        guard !installed else { return }
        installed = true

        let t = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        token = t

        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer else { return }
            let obj = Unmanaged<RecordingDarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            obj.handleNotification(name: name)
        }

        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.start, callback: callback)
        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.pause, callback: callback)
        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.resume, callback: callback)
        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.stop, callback: callback)

        print("✅ RecordingDarwinObserver 已注册 Darwin 录音命令监听")
    }

    func uninstallIfNeeded() {
        guard installed, let t = token else { return }
        DarwinNotificationCenter.removeObserver(t)
        token = nil
        installed = false
        print("🧹 RecordingDarwinObserver 已移除 Darwin 录音命令监听")
    }

    private func handleNotification(name: CFNotificationName?) {
        guard let raw = name?.rawValue as String? else { return }
        let defaults = UserDefaults(suiteName: RecordingSharedDefaults.suite)
        let ts = defaults?.double(forKey: RecordingSharedDefaults.commandTimestampKey) ?? 0

        DispatchQueue.main.async {
            switch raw {
            case RecordingDarwinNames.start:
                let shouldNavigateToChat = defaults?.bool(forKey: RecordingSharedDefaults.shouldNavigateToChatRoomKey) ?? true
                let autoMinimize = defaults?.bool(forKey: RecordingSharedDefaults.autoMinimizeKey) ?? true
                let publishTranscriptionToUI = defaults?.bool(forKey: RecordingSharedDefaults.publishTranscriptionToUIKey) ?? true
                print("🏝️ Darwin start (\(ts)) shouldNavigateToChat=\(shouldNavigateToChat) autoMinimize=\(autoMinimize) publishTranscriptionToUI=\(publishTranscriptionToUI)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("StartRecordingFromWidget"),
                    object: nil,
                    userInfo: [
                        "shouldNavigateToChatRoom": shouldNavigateToChat,
                        "autoMinimize": autoMinimize,
                        "publishTranscriptionToUI": publishTranscriptionToUI
                    ]
                )

            case RecordingDarwinNames.pause:
                print("🏝️ Darwin pause (\(ts))")
                LiveRecordingManager.shared.pauseRecording()

            case RecordingDarwinNames.resume:
                print("🏝️ Darwin resume (\(ts))")
                LiveRecordingManager.shared.resumeRecording()

            case RecordingDarwinNames.stop:
                let shouldNavigateToChat = defaults?.bool(forKey: RecordingSharedDefaults.shouldNavigateToChatRoomKey) ?? true
                print("🏝️ Darwin stop (\(ts)) shouldNavigateToChat=\(shouldNavigateToChat)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("StopRecordingFromWidget"),
                    object: nil,
                    userInfo: [
                        "shouldNavigateToChatRoom": shouldNavigateToChat
                    ]
                )

            default:
                break
            }
        }
    }
}


