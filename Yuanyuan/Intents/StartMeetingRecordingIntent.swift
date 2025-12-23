import Foundation
import AppIntents
import SwiftData

// MARK: - 录音跨进程通信（AppIntent/Widget ↔ 主App）
// AppIntent/灵动岛动作可能运行在独立进程里，NotificationCenter.default.post 无法跨进程触达主App。
// 这里使用 App Group UserDefaults + Darwin Notify 来触发主App。
private enum RecordingIPC {
    static let suite = "group.com.yuanyuan.shared"

    enum Key {
        static let shouldNavigateToMeeting = "recording.shouldNavigateToMeeting"
        static let autoMinimize = "recording.autoMinimize"
        static let shouldNavigateToChatRoom = "recording.shouldNavigateToChatRoom"
        static let publishTranscriptionToUI = "recording.publishTranscriptionToUI"
        static let commandTimestamp = "recording.commandTimestamp"
    }

    enum DarwinName {
        static let start = "group.com.yuanyuan.shared.recording.start"
        static let pause = "group.com.yuanyuan.shared.recording.pause"
        static let resume = "group.com.yuanyuan.shared.recording.resume"
        static let stop = "group.com.yuanyuan.shared.recording.stop"
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
    static var openAppWhenRun: Bool = true  // 必须打开App来初始化音频会话（系统限制）
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🎤 执行StartMeetingRecordingIntent - 快速启动模式")
        let defaults = RecordingIPC.defaults()
        // 新流程：快捷指令启动后进入聊天室插入“开始录音”气泡，不再跳转会议纪要页
        defaults?.set(false, forKey: RecordingIPC.Key.shouldNavigateToMeeting)
        defaults?.set(true, forKey: RecordingIPC.Key.shouldNavigateToChatRoom)
        defaults?.set(true, forKey: RecordingIPC.Key.autoMinimize)
        // 快捷指令/Widget 场景：不在 UI 上展示实时转写（避免自动弹出“蓝色球/歌词滚动”转写界面）
        defaults?.set(false, forKey: RecordingIPC.Key.publishTranscriptionToUI)
        defaults?.set(Date().timeIntervalSince1970, forKey: RecordingIPC.Key.commandTimestamp)
        defaults?.synchronize()
        RecordingIPC.postDarwin(RecordingIPC.DarwinName.start)
        
        print("✅ 已通知主App启动录音")
        
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
        print("⏸️ 执行PauseMeetingRecordingIntent - 从灵动岛暂停")
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
        print("▶️ 执行ResumeMeetingRecordingIntent - 从灵动岛继续")
        RecordingIPC.postDarwin(RecordingIPC.DarwinName.resume)
        
        return .result()
    }
}

// 停止会议录音 Intent
struct StopMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "停止录音"
    static var description = IntentDescription("停止录音并保存到会议纪要")
    static var openAppWhenRun: Bool = true  // 需要App上下文保存数据
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🛑 执行StopMeetingRecordingIntent - 从灵动岛停止")
        let defaults = RecordingIPC.defaults()
        defaults?.set(true, forKey: RecordingIPC.Key.shouldNavigateToChatRoom)
        defaults?.set(Date().timeIntervalSince1970, forKey: RecordingIPC.Key.commandTimestamp)
        defaults?.synchronize()
        RecordingIPC.postDarwin(RecordingIPC.DarwinName.stop)
        
        // 给主app一点时间来保存
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
        
        return .result()
    }
}

