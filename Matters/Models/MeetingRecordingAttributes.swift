import Foundation
import ActivityKit

// Live Activity 属性定义
struct MeetingRecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var transcribedText: String  // 实时转写的文字
        var duration: TimeInterval   // 录音时长
        var isRecording: Bool        // 是否正在录音
        var isPaused: Bool           // 是否已暂停
    }
    
    var meetingTitle: String  // 会议标题（可选）
}

