import Foundation
import ActivityKit

// Live Activity 属性定义
struct MeetingRecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var transcribedText: String  // 实时转写的文字
        var duration: TimeInterval   // 录音时长
        var isRecording: Bool        // 是否正在录音
        var isPaused: Bool           // 是否已暂停
        var isCompleted: Bool = false // 是否已完成（用于展示完成态 UI）
        var wavePhase: Int = 0       // 音浪动画相位（通过 state 更新驱动灵动岛刷新）
    }
    
    var meetingTitle: String  // 会议标题（可选）
}

