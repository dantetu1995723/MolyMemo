import Foundation
import EventKit
import UserNotifications

// 日历和提醒管理器
class CalendarManager {
    static let shared = CalendarManager()
    private let eventStore = EKEventStore()
    
    private init() {}
    
    // MARK: - 权限请求
    
    /// 请求日历访问权限
    func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                print("请求日历权限失败: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// 请求提醒事项访问权限
    func requestRemindersAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                print("请求提醒权限失败: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// 请求通知权限
    func requestNotificationPermission() async -> Bool {
        do {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                return try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
            }
            return settings.authorizationStatus == .authorized
        } catch {
            print("请求通知权限失败: \(error)")
            return false
        }
    }
    
    // MARK: - 日历事件管理
    
    /// 创建日历事件
    @discardableResult
    func createCalendarEvent(
        title: String,
        description: String?,
        startDate: Date,
        endDate: Date,
        alarmDate: Date?
    ) async -> String? {
        // 请求权限
        let hasAccess = await requestCalendarAccess()
        guard hasAccess else {
            print("没有日历访问权限")
            return nil
        }
        
        // 创建事件
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = description
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        // 添加提醒
        if let alarmDate = alarmDate {
            let alarm = EKAlarm(absoluteDate: alarmDate)
            event.addAlarm(alarm)
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            print("日历事件创建成功: \(event.eventIdentifier ?? "")")
            return event.eventIdentifier
        } catch {
            print("创建日历事件失败: \(error)")
            return nil
        }
    }
    
    /// 更新日历事件
    func updateCalendarEvent(
        eventIdentifier: String,
        title: String,
        description: String?,
        startDate: Date,
        endDate: Date,
        alarmDate: Date?
    ) async -> Bool {
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else {
            print("找不到日历事件")
            return false
        }
        
        event.title = title
        event.notes = description
        event.startDate = startDate
        event.endDate = endDate
        
        // 更新提醒
        event.alarms?.forEach { event.removeAlarm($0) }
        if let alarmDate = alarmDate {
            let alarm = EKAlarm(absoluteDate: alarmDate)
            event.addAlarm(alarm)
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            print("日历事件更新成功")
            return true
        } catch {
            print("更新日历事件失败: \(error)")
            return false
        }
    }
    
    /// 删除日历事件
    func deleteCalendarEvent(eventIdentifier: String) async -> Bool {
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else {
            print("找不到日历事件")
            return false
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            print("日历事件删除成功")
            return true
        } catch {
            print("删除日历事件失败: \(error)")
            return false
        }
    }
    
    // MARK: - 本地通知管理
    
    /// 创建本地通知
    func scheduleNotification(
        id: String,
        title: String,
        body: String?,
        date: Date
    ) async -> Bool {
        // 请求权限
        let hasPermission = await requestNotificationPermission()
        guard hasPermission else {
            print("没有通知权限")
            return false
        }
        
        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = title
        if let body = body {
            content.body = body
        }
        content.sound = .default
        
        // 创建触发器
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // 创建请求
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("本地通知创建成功")
            return true
        } catch {
            print("创建本地通知失败: \(error)")
            return false
        }
    }
    
    /// 取消本地通知
    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        print("本地通知已取消")
    }
    
    /// 更新本地通知
    func updateNotification(
        id: String,
        title: String,
        body: String?,
        date: Date
    ) async -> Bool {
        // 先取消旧的
        cancelNotification(id: id)
        // 再创建新的
        return await scheduleNotification(id: id, title: title, body: body, date: date)
    }
}

