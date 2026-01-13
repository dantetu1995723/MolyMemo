import Foundation
import EventKit
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

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
            // 兼容：provisional 也可用于投递通知（系统会以“静默/摘要”形式展示）
            return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        } catch {
            return false
        }
    }

    /// 当前通知授权状态（用于 UI 做引导）
    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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
            return event.eventIdentifier
        } catch {
            return nil
        }
    }
    
    /// 更新日历事件
    @discardableResult
    func updateCalendarEvent(
        eventIdentifier: String,
        title: String,
        description: String?,
        startDate: Date,
        endDate: Date,
        alarmDate: Date?
    ) async -> Bool {
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else {
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
            return true
        } catch {
            return false
        }
    }
    
    /// 删除日历事件
    @discardableResult
    func deleteCalendarEvent(eventIdentifier: String) async -> Bool {
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else {
            return false
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - 本地通知管理
    
    /// 创建本地通知
    @discardableResult
    func scheduleNotification(
        id: String,
        title: String,
        body: String?,
        date: Date
    ) async -> Bool {
        return await scheduleNotification(id: id, title: title, body: body, badge: nil, date: date)
    }
    
    /// 创建本地通知（可选 badge）
    @discardableResult
    func scheduleNotification(
        id: String,
        title: String,
        body: String?,
        badge: NSNumber?,
        date: Date
    ) async -> Bool {
        // 请求权限
        let hasPermission = await requestNotificationPermission()
        guard hasPermission else {
            return false
        }
        
        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = title
        if let body = body {
            content.body = body
        }
        content.sound = .default
        if let badge {
            content.badge = badge
        }
        
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
            return true
        } catch {
            return false
        }
    }
    
    /// 取消本地通知
    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
    
    /// 更新本地通知
    @discardableResult
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
    
    /// 清空 App 图标红标（进入 App 后用）
    func clearAppBadge() async {
        if #available(iOS 16.0, *) {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            #if canImport(UIKit)
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
            #endif
        }
    }
}

