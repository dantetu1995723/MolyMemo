import Foundation
import AppIntents
import SwiftData

// 开始会议录音 Intent
struct StartMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始会议录音"
    static var description = IntentDescription("启动录音并显示灵动岛")
    static var openAppWhenRun: Bool = true  // 必须打开App来初始化音频会话（系统限制）
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🎤 执行StartMeetingRecordingIntent - 快速启动模式")
        
        // 发送通知给主App，让主App快速启动录音并自动挂到后台
        NotificationCenter.default.post(
            name: NSNotification.Name("StartRecordingFromWidget"),
            object: nil,
            userInfo: [
                "shouldNavigateToMeeting": true,  // 进入会议界面
                "autoMinimize": true  // 启动后自动挂后台
            ]
        )
        
        print("✅ 已通知主App启动录音")
        
        return .result()
    }
}

// 暂停会议录音 Intent
struct PauseMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "暂停会议录音"
    static var description = IntentDescription("暂停录音")
    static var openAppWhenRun: Bool = false  // 后台执行即可
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("⏸️ 执行PauseMeetingRecordingIntent - 从灵动岛暂停")
        LiveRecordingManager.shared.pauseRecording()
        return .result()
    }
}

// 继续会议录音 Intent
struct ResumeMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "继续会议录音"
    static var description = IntentDescription("继续录音")
    static var openAppWhenRun: Bool = false  // 后台执行即可
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("▶️ 执行ResumeMeetingRecordingIntent - 从灵动岛继续")
        LiveRecordingManager.shared.resumeRecording()
        return .result()
    }
}

// 停止会议录音 Intent
struct StopMeetingRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "停止会议录音"
    static var description = IntentDescription("停止录音并保存到会议纪要")
    static var openAppWhenRun: Bool = true  // 需要App上下文保存数据
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🛑 执行StopMeetingRecordingIntent - 从灵动岛停止")
        
        // 通知App停止录音并保存
        NotificationCenter.default.post(
            name: NSNotification.Name("StopRecordingFromWidget"),
            object: nil
        )
        
        // 给主app一点时间来保存
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
        
        return .result()
    }
}

