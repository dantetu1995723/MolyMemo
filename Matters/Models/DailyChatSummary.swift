import Foundation
import SwiftData

// 每日聊天总结模型 - 用于存储每天的聊天主体总结
@Model
final class DailyChatSummary {
    var date: Date
    var summary: String
    var messageCount: Int
    var lastUpdated: Date
    
    init(
        date: Date,
        summary: String,
        messageCount: Int,
        lastUpdated: Date
    ) {
        self.date = date
        self.summary = summary
        self.messageCount = messageCount
        self.lastUpdated = lastUpdated
    }
}

// 扩展：辅助方法和计算属性
extension DailyChatSummary {
    // 获取日期的开始时间（00:00:00）
    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
    
    // 格式化显示日期
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter.string(from: date)
    }
    
    // 相对日期显示（今天、昨天等）
    var relativeDateString: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let messageDay = calendar.startOfDay(for: date)
        
        let dayDifference = calendar.dateComponents([.day], from: messageDay, to: today).day ?? 0
        
        switch dayDifference {
        case 0:
            return "今天"
        case 1:
            return "昨天"
        case 2...6:
            return "\(dayDifference)天前"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MM月dd日"
            return formatter.string(from: date)
        }
    }
}


