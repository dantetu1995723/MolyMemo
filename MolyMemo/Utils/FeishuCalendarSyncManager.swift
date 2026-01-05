import Foundation
import EventKit

/// 飞书日历同步管理器
class FeishuCalendarSyncManager: ObservableObject {
    static let shared = FeishuCalendarSyncManager()
    
    private let feishuAPI = FeishuAPIService.shared
    private let calendarManager = CalendarManager.shared
    
    // 同步配置
    private let syncIntervalKey = "feishu_sync_interval"
    private let lastSyncTimeKey = "feishu_last_sync_time"
    private let enabledCalendarsKey = "feishu_enabled_calendars"
    
    private init() {}
    
    // MARK: - 同步配置
    
    /// 同步间隔（分钟）
    var syncInterval: Int {
        get {
            let interval = UserDefaults.standard.integer(forKey: syncIntervalKey)
            return interval > 0 ? interval : 30  // 默认30分钟
        }
        set {
            UserDefaults.standard.set(newValue, forKey: syncIntervalKey)
        }
    }
    
    /// 上次同步时间
    var lastSyncTime: Date? {
        get {
            UserDefaults.standard.object(forKey: lastSyncTimeKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastSyncTimeKey)
        }
    }
    
    /// 已启用的日历ID列表
    var enabledCalendars: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: enabledCalendarsKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledCalendarsKey)
        }
    }
    
    /// 是否需要同步
    var needsSync: Bool {
        guard let lastSync = lastSyncTime else { return true }
        let timeInterval = Date().timeIntervalSince(lastSync)
        return timeInterval >= TimeInterval(syncInterval * 60)
    }
    
    // MARK: - 同步方法
    
    /// 同步飞书日历到本地
    func syncCalendars() async throws {
        guard feishuAPI.isLoggedIn else {
            throw FeishuError.notLoggedIn
        }
        
        
        // 1. 获取飞书日历列表
        let feishuCalendars = try await feishuAPI.fetchCalendars()
        
        // 2. 过滤已启用的日历
        let calendarsToSync = feishuCalendars.filter { calendar in
            enabledCalendars.isEmpty || enabledCalendars.contains(calendar.id)
        }
        
        
        // 3. 同步每个日历的事件
        var totalSynced = 0
        let startDate = Date()  // 从今天开始
        let endDate = Calendar.current.date(byAdding: .month, value: 3, to: startDate) ?? startDate
        
        for calendar in calendarsToSync {
            do {
                let synced = try await syncCalendarEvents(
                    calendarId: calendar.id,
                    calendarName: calendar.summary,
                    startDate: startDate,
                    endDate: endDate
                )
                totalSynced += synced
            } catch {
            }
        }
        
        // 4. 更新同步时间
        lastSyncTime = Date()
    }
    
    /// 同步单个日历的事件
    private func syncCalendarEvents(
        calendarId: String,
        calendarName: String,
        startDate: Date,
        endDate: Date
    ) async throws -> Int {
        // 1. 获取飞书事件
        let feishuEvents = try await feishuAPI.fetchEvents(
            calendarId: calendarId,
            startTime: startDate,
            endTime: endDate
        )
        
        // 2. 请求日历权限
        let hasAccess = await calendarManager.requestCalendarAccess()
        guard hasAccess else {
            throw CalendarSyncError.noCalendarPermission
        }
        
        // 3. 同步每个事件到本地
        var syncedCount = 0
        for event in feishuEvents {
            do {
                // 检查是否已经存在（通过标题和时间判断）
                let eventId = try await createOrUpdateLocalEvent(
                    title: event.summary,
                    description: event.description,
                    startDate: event.startTime,
                    endDate: event.endTime,
                    location: event.location,
                    feishuEventId: event.id
                )
                
                if eventId != nil {
                    syncedCount += 1
                }
            } catch {
            }
        }
        
        return syncedCount
    }
    
    /// 创建或更新本地日历事件
    private func createOrUpdateLocalEvent(
        title: String,
        description: String?,
        startDate: Date,
        endDate: Date,
        location: String?,
        feishuEventId: String
    ) async throws -> String? {
        // 构建完整描述，包含飞书事件ID用于后续同步
        var fullDescription = description ?? ""
        fullDescription += "\n\n[飞书事件ID: \(feishuEventId)]"
        
        // 创建本地事件（简单实现，不检查重复）
        // TODO: 可以通过notes字段存储飞书ID，避免重复创建
        let eventId = await calendarManager.createCalendarEvent(
            title: title,
            description: fullDescription,
            startDate: startDate,
            endDate: endDate,
            alarmDate: startDate.addingTimeInterval(-15 * 60)  // 提前15分钟提醒
        )
        
        return eventId
    }
    
    // MARK: - 双向同步
    
    /// 将本地事件同步到飞书
    func syncLocalEventToFeishu(
        calendarId: String,
        title: String,
        description: String?,
        startDate: Date,
        endDate: Date,
        location: String?
    ) async throws -> FeishuEvent {
        let eventCreate = FeishuEventCreate(
            summary: title,
            description: description,
            startTime: startDate.timeIntervalSince1970,
            endTime: endDate.timeIntervalSince1970,
            location: location,
            reminders: [15]  // 提前15分钟提醒
        )
        
        return try await feishuAPI.createEvent(
            calendarId: calendarId,
            event: eventCreate
        )
    }
    
    // MARK: - 自动同步
    
    /// 启动自动同步
    func startAutoSync() {
        Timer.scheduledTimer(withTimeInterval: TimeInterval(syncInterval * 60), repeats: true) { [weak self] _ in
            Task {
                try? await self?.syncCalendars()
            }
        }
    }
}

// MARK: - 错误类型

enum CalendarSyncError: LocalizedError {
    case noCalendarPermission
    case eventNotFound
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .noCalendarPermission:
            return "没有日历访问权限"
        case .eventNotFound:
            return "事件不存在"
        case .syncFailed:
            return "同步失败"
        }
    }
}

