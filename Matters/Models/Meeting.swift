import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var title: String
    var content: String  // 会议纪要文字内容
    var audioFilePath: String?  // 音频文件路径
    var createdAt: Date
    var duration: TimeInterval  // 录音时长（秒）
    
    init(
        title: String,
        content: String = "",
        audioFilePath: String? = nil,
        createdAt: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.audioFilePath = audioFilePath
        self.createdAt = createdAt
        self.duration = duration
    }
    
    // 格式化日期
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter.string(from: createdAt)
    }
    
    // 格式化时长
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }
}

