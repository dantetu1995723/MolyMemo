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
    static let start = "\(AppIdentifiers.appGroupId).recording.start"
    static let pause = "\(AppIdentifiers.appGroupId).recording.pause"
    static let resume = "\(AppIdentifiers.appGroupId).recording.resume"
    static let stop = "\(AppIdentifiers.appGroupId).recording.stop"
}

enum RecordingSharedDefaults {
    static let suite = AppIdentifiers.appGroupId
    static let shouldNavigateToMeetingKey = "recording.shouldNavigateToMeeting"
    static let autoMinimizeKey = "recording.autoMinimize"
    static let shouldNavigateToChatRoomKey = "recording.shouldNavigateToChatRoom"
    /// 是否使用“后台上传器”（background URLSession），用于灵动岛/快捷指令场景避免依赖前台 UI。
    static let useBackgroundUploaderKey = "recording.useBackgroundUploader"
    /// 是否在 UI（Live Activity / 灵动岛）展示实时转写。
    /// - true: 展示（默认）
    /// - false: 只录音/内部转写，但不把转写文本推到 UI（避免出现“蓝色球/歌词滚动”）
    static let publishTranscriptionToUIKey = "recording.publishTranscriptionToUI"
    /// 最近一次来自 Widget/AppIntent 的命令类型（start/pause/resume/stop），用于兜底处理。
    static let pendingCommandKey = "recording.pendingCommand"
    static let commandTimestampKey = "recording.commandTimestamp"
    /// 主App已处理的最后一次命令时间戳，用于去重（避免 Darwin + onAppear 重复执行）。
    static let lastHandledTimestampKey = "recording.lastHandledTimestamp"
}

// MARK: - Chat (Darwin)

enum ChatDarwinNames {
    static let chatUpdated = "\(AppIdentifiers.appGroupId).chat.updated"
    /// AppIntent 写入一条“待发送截图”（由主App前台按 App 内发送链路发出）
    static let pendingScreenshot = "\(AppIdentifiers.appGroupId).chat.pendingScreenshot"
}

enum ChatSharedDefaults {
    static let suite = AppIdentifiers.appGroupId
    /// AppIntent 后台写入 AI 回复后，记录最后一条“新插入的 AI 消息 id”
    static let lastInsertedAgentMessageIdKey = "chat.lastInsertedAgentMessageId"
    /// AppIntent 写入后更新时间戳（用于主App去重处理）
    static let lastUpdateTimestampKey = "chat.lastUpdateTimestamp"
    /// 主App已处理的最后一次更新时间戳（用于去重）
    static let lastHandledUpdateTimestampKey = "chat.lastHandledUpdateTimestamp"

    // MARK: - Pending screenshot (AppIntent -> App)
    /// AppIntent 写入待发送截图的相对路径（相对于 App Group 根目录）
    static let pendingScreenshotRelativePathKey = "chat.pendingScreenshotRelativePath"
    /// AppIntent 写入待发送截图的时间戳（用于主App去重）
    static let pendingScreenshotTimestampKey = "chat.pendingScreenshotTimestamp"
    /// 主App已处理的最后一次“待发送截图”时间戳（用于去重）
    static let lastHandledPendingScreenshotTimestampKey = "chat.lastHandledPendingScreenshotTimestamp"
}


