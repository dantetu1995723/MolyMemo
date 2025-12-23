import Foundation

/// 用于 App / Widget / AppIntent 之间跨进程通信（Darwin Notify）。
/// 注意：Darwin 通知不携带 payload，需要配合 App Group UserDefaults 存储参数。
enum DarwinNotificationCenter {
    static func post(_ name: String) {
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), cfName, nil, nil, true)
    }

    static func addObserver(_ observer: UnsafeRawPointer,
                            name: String,
                            callback: @escaping CFNotificationCallback) {
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        observer,
                                        callback,
                                        cfName.rawValue,
                                        nil,
                                        .deliverImmediately)
    }

    static func removeObserver(_ observer: UnsafeRawPointer) {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, nil, nil)
    }
}

enum RecordingDarwinNames {
    static let start = "group.com.yuanyuan.shared.recording.start"
    static let pause = "group.com.yuanyuan.shared.recording.pause"
    static let resume = "group.com.yuanyuan.shared.recording.resume"
    static let stop = "group.com.yuanyuan.shared.recording.stop"
}

enum RecordingSharedDefaults {
    static let suite = "group.com.yuanyuan.shared"
    static let shouldNavigateToMeetingKey = "recording.shouldNavigateToMeeting"
    static let autoMinimizeKey = "recording.autoMinimize"
    static let shouldNavigateToChatRoomKey = "recording.shouldNavigateToChatRoom"
    /// 是否在 UI（Live Activity / 灵动岛）展示实时转写。
    /// - true: 展示（默认）
    /// - false: 只录音/内部转写，但不把转写文本推到 UI（避免出现“蓝色球/歌词滚动”）
    static let publishTranscriptionToUIKey = "recording.publishTranscriptionToUI"
    static let commandTimestampKey = "recording.commandTimestamp"
}


