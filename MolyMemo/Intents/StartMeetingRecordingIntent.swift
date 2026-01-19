import Foundation
import AppIntents
import SwiftData

// MARK: - 录音跨进程通信（AppIntent/Widget ↔ 主App）
// AppIntent/灵动岛动作可能运行在独立进程里，NotificationCenter.default.post 无法跨进程触达主App。
// 这里使用 App Group UserDefaults + Darwin Notify 来触发主App。
private enum RecordingIPC {
    static let suite = AppIdentifiers.appGroupId

    enum Key {
        static let shouldNavigateToMeeting = "recording.shouldNavigateToMeeting"
        static let autoMinimize = "recording.autoMinimize"
        static let shouldNavigateToChatRoom = "recording.shouldNavigateToChatRoom"
        static let publishTranscriptionToUI = "recording.publishTranscriptionToUI"
        static let pendingCommand = "recording.pendingCommand"
        static let commandTimestamp = "recording.commandTimestamp"
    }

    enum DarwinName {
        static let start = "\(AppIdentifiers.appGroupId).recording.start"
        static let pause = "\(AppIdentifiers.appGroupId).recording.pause"
        static let resume = "\(AppIdentifiers.appGroupId).recording.resume"
        static let stop = "\(AppIdentifiers.appGroupId).recording.stop"
    }

    static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: suite)
    }

    static func postDarwin(_ name: String) {
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            cfName,
            nil,
            nil,
            true
        )
    }
}

// 开始会议录音 Intent
struct StartMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Moly录音"
    static var description = IntentDescription("启动 Moly录音 并显示灵动岛")
    static var openAppWhenRun: Bool = true  // 必须启动主 App 进程才能录音（Widget/AppIntent 扩展进程无法录音）
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let defaults = RecordingIPC.defaults()
        // 目标：尽量不打扰 UI（不强制跳转），但确保主 App 进程被启动后能立刻开始录音并创建灵动岛。
        defaults?.set(false, forKey: RecordingIPC.Key.shouldNavigateToMeeting)
        defaults?.set(false, forKey: RecordingIPC.Key.shouldNavigateToChatRoom)
        // 快捷指令触发：启动后自动缩回灵动岛/回到桌面（由主 App 执行）
        defaults?.set(true, forKey: RecordingIPC.Key.autoMinimize)
        // 快捷指令/Widget 场景：不在 UI 上展示实时转写（避免自动弹出“蓝色球/歌词滚动”转写界面）
        defaults?.set(false, forKey: RecordingIPC.Key.publishTranscriptionToUI)
        // 灵动岛录音：停止后走后台上传器（background URLSession），避免依赖前台 UI 的上传链路
        defaults?.set(true, forKey: "recording.useBackgroundUploader")
        defaults?.set("start", forKey: RecordingIPC.Key.pendingCommand)
        defaults?.set(Date().timeIntervalSince1970, forKey: RecordingIPC.Key.commandTimestamp)
        defaults?.synchronize()

        // 关键：发 Darwin 通知给主 App，让它在启动后执行 start（避免“启动后没录上”）
        RecordingIPC.postDarwin(RecordingIPC.DarwinName.start)

        return .result()
    }
}

// 暂停会议录音 Intent
struct PauseMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "暂停录音"
    static var description = IntentDescription("暂停录音")
    static var openAppWhenRun: Bool = false  // 后台执行即可
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let defaults = RecordingIPC.defaults()
        defaults?.set("pause", forKey: RecordingIPC.Key.pendingCommand)
        defaults?.set(Date().timeIntervalSince1970, forKey: RecordingIPC.Key.commandTimestamp)
        defaults?.synchronize()
        RecordingIPC.postDarwin(RecordingIPC.DarwinName.pause)
        
        return .result()
    }
}

// 继续会议录音 Intent
struct ResumeMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "继续录音"
    static var description = IntentDescription("继续录音")
    static var openAppWhenRun: Bool = false  // 后台执行即可
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let defaults = RecordingIPC.defaults()
        defaults?.set("resume", forKey: RecordingIPC.Key.pendingCommand)
        defaults?.set(Date().timeIntervalSince1970, forKey: RecordingIPC.Key.commandTimestamp)
        defaults?.synchronize()
        RecordingIPC.postDarwin(RecordingIPC.DarwinName.resume)
        
        return .result()
    }
}

// 停止会议录音 Intent
struct StopMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "停止录音"
    static var description = IntentDescription("停止录音并保存到会议记录")
    static var openAppWhenRun: Bool = false  // 后台执行即可：录音正在进行时主App必然存活（后台音频），无需拉起前台
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let defaults = RecordingIPC.defaults()
        // 停止动作默认不强制拉起/跳转界面，避免出现“转圈加载后才跳回App”的感觉
        defaults?.set(false, forKey: RecordingIPC.Key.shouldNavigateToChatRoom)
        defaults?.set("stop", forKey: RecordingIPC.Key.pendingCommand)
        defaults?.set(Date().timeIntervalSince1970, forKey: RecordingIPC.Key.commandTimestamp)
        defaults?.synchronize()
        RecordingIPC.postDarwin(RecordingIPC.DarwinName.stop)

        return .result()
    }
}

