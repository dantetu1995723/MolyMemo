import Foundation
import UserNotifications

/// “今日日程”系统通知调度器
///
/// 目标：
/// - 只对“今天的日程”创建本地通知
/// - 触发时间严格按 reminder_time（相对/绝对）计算
/// - 内容仅显示：标题 + 备注（description）
/// - 通知条使用 App 图标（iOS 默认行为，无需额外设置）
/// - 去重：多次刷新不会重复创建；日程变化会自动重排
actor TodayScheduleLocalNotificationScheduler {
    static let shared = TodayScheduleLocalNotificationScheduler()
    
    private let idPrefix = "today_schedule:"
    private var lastPlannedDayKey: String? = nil
    private var lastPlan: [String: Date] = [:] // id -> fireDate
    
    func sync(events: [ScheduleEvent], now: Date = Date()) async {
        let cal = Calendar.current
        let dayKey = Self.dayKey(for: now, calendar: cal)
        
        if lastPlannedDayKey != dayKey {
            lastPlannedDayKey = dayKey
            lastPlan = [:]
        }
        
        // 1) 生成“今天且未过期”的计划
        var plan: [String: Date] = [:]
        plan.reserveCapacity(events.count)
        
        for ev in events {
            // 只处理“今日日程”
            guard cal.isDate(ev.startTime, inSameDayAs: now) else { continue }
            
            guard let raw = ev.reminderTime?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { continue }
            
            guard let fireDate = ScheduleReminderTime.resolveReminderDate(startTime: ev.startTime, reminderTimeRaw: raw) else {
                continue
            }
            
            // 只发“今天且未来”的提醒（避免跨天/已过期提醒制造噪音）
            guard fireDate > now, cal.isDate(fireDate, inSameDayAs: now) else { continue }
            
            let id = makeNotificationId(event: ev)
            // 若同一 id 触发时间冲突，取更早的（更保守，不会漏提醒）
            if let existing = plan[id] {
                plan[id] = min(existing, fireDate)
            } else {
                plan[id] = fireDate
            }
        }
        
        // 2) 若计划没变，直接跳过（避免每分钟刷新都重排系统通知）
        if plan == lastPlan {
            return
        }
        lastPlan = plan
        
        // 3) 先清理旧的“今日日程”通知，再按计划重新创建
        let idsToRemove = await pendingNotificationIds(withPrefix: idPrefix)
        if !idsToRemove.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: idsToRemove)
        }
        
        // 4) 创建通知
        for (id, fireDate) in plan {
            // 从 id 里提取出 remoteId/uuid 只是为了稳定，不强依赖
            // 通知内容：标题 + 备注（description）
            // iOS 通知条使用 App 图标：默认即为 App icon
            let parts = id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true)
            let key = parts.first.map(String.init) ?? id
            
            // 根据 key 反查 event：O(n) 但数据量很小（今日日程通常 < 50），可读性更重要
            let ev = events.first { makeNotificationId(event: $0) == id }
            
            let title = (ev?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (ev?.title ?? "日程提醒")
            : "日程提醒"
            
            let bodyRaw = (ev?.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = bodyRaw.isEmpty ? nil : bodyRaw
            
            _ = key // 保留，方便以后需要把 identifier 拆出来做跳转等
            _ = await CalendarManager.shared.scheduleNotification(
                id: id,
                title: title,
                body: body,
                badge: 1,
                date: fireDate
            )
        }
    }
    
    private func makeNotificationId(event: ScheduleEvent) -> String {
        let stable = (event.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        ? (event.remoteId ?? "")
        : event.id.uuidString
        return "\(idPrefix)\(stable)"
    }
    
    private func pendingNotificationIds(withPrefix prefix: String) async -> [String] {
        let requests = await pendingNotificationRequests()
        return requests
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
    }
    
    private func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
    
    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return "\(y)-\(m)-\(d)"
    }
}

