import SwiftUI
import SwiftData
import Foundation

// 待办事项数据模型
@Model
final class TodoItem {
    var id: UUID
    var title: String
    var taskDescription: String
    var startTime: Date
    var endTime: Date
    var reminderTime: Date
    var isCompleted: Bool
    var createdAt: Date
    
    // 日历和提醒集成
    var calendarEventId: String?
    var notificationId: String?
    var syncToCalendar: Bool = true
    
    // 关联的报销项目ID
    var linkedExpenseId: UUID?
    
    // 附件数据
    @Attribute(.externalStorage) var imageData: [Data]?
    var textAttachments: [String]? // 支持多个文本附件（如会议纪要、备注等）
    
    init(
        title: String,
        taskDescription: String = "",
        startTime: Date,
        endTime: Date,
        reminderTime: Date? = nil,
        imageData: [Data]? = nil,
        textAttachments: [String]? = nil,
        syncToCalendar: Bool = true
    ) {
        self.id = UUID()
        self.title = title
        self.taskDescription = taskDescription
        self.startTime = startTime
        self.endTime = endTime
        // 默认提前15分钟提醒
        self.reminderTime = reminderTime ?? startTime.addingTimeInterval(-15 * 60)
        self.isCompleted = false
        self.createdAt = Date()
        self.imageData = imageData
        self.textAttachments = textAttachments
        self.syncToCalendar = syncToCalendar
        self.calendarEventId = nil
        self.notificationId = nil
    }
    
    // 是否过期
    var isOverdue: Bool {
        !isCompleted && endTime < Date()
    }
    
    // 是否即将到来（24小时内）
    var isUpcoming: Bool {
        !isCompleted && startTime > Date() && startTime < Date().addingTimeInterval(24 * 60 * 60)
    }
    
    // 格式化时间显示
    var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        
        let dateStr = formatter.string(from: startTime)
        let weekdayStr = weekdayFormatter.string(from: startTime)
        
        return "\(dateStr) \(weekdayStr)"
    }
}

