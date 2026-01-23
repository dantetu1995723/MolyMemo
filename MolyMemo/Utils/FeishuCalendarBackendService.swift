import Foundation

/// 后端"飞书日历"同步相关接口
/// - GET  /api/v1/feishu/calendar/list
/// - POST /api/v1/feishu/calendar/sync  { "calendar_id": "..." }
/// - Note: 统一复用 `ScheduleService` 的 baseURL 与公共 header（含 X-Session-Id）
enum FeishuCalendarBackendService {
    struct CalendarItem: Identifiable, Hashable {
        let calendarId: String
        let name: String
        let description: String?
        let color: Int?
        let type: String?
        let permission: String?
        
        var id: String { calendarId }
    }
    
    /// 同步结果：只关心是否成功与提示文案（不拉回日程列表）
    struct SyncAck: Hashable {
        let message: String
    }
    
    enum ServiceError: LocalizedError {
        case invalidResponse
        case httpStatus(Int, String)
        case parseFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "飞书同步失败：服务端返回异常"
            case let .httpStatus(code, body):
                let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { return "飞书同步失败（HTTP \(code)）" }
                return "飞书同步失败（HTTP \(code)）：\(t)"
            case let .parseFailed(msg):
                return "飞书同步失败：解析失败（\(msg)）"
            }
        }
    }

    private enum TimeoutError: LocalizedError {
        case timeout(seconds: Int)
        var errorDescription: String? {
            switch self {
            case let .timeout(seconds):
                return "请求超时（\(seconds)s）"
            }
        }
    }

    private static func withTimeout<T>(_ seconds: Int, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds)) * 1_000_000_000)
                throw TimeoutError.timeout(seconds: seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ServiceError.invalidResponse
            }
            return first
        }
    }

    // MARK: - Debug logs

    private static func maskedSessionId(_ any: Any?) -> String {
        guard let s = any as? String else { return "(nil)" }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 8 else { return "***" }
        return "\(t.prefix(4))***\(t.suffix(4))"
    }

    private static func summarizeBody(_ raw: String, maxLen: Int = 900) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxLen else { return t }
        return "\(t.prefix(maxLen))…(\(t.count))"
    }

    private static func debugPrintRequest(_ request: URLRequest, tag: String) {
#if DEBUG
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "(nil)"
        let sid = request.value(forHTTPHeaderField: "X-Session-Id")
        print("🗓️ [FeishuCalendarBackend][\(tag)] \(method) \(url)")
        print("🗓️ [FeishuCalendarBackend][\(tag)] X-Session-Id=\(maskedSessionId(sid))")
#endif
    }

    private static func debugPrintResponse(data: Data, response: URLResponse?, tag: String) {
#if DEBUG
        if let http = response as? HTTPURLResponse {
            print("🗓️ [FeishuCalendarBackend][\(tag)] status=\(http.statusCode)")
        } else {
            print("🗓️ [FeishuCalendarBackend][\(tag)] status=(non-http)")
        }
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        print("🗓️ [FeishuCalendarBackend][\(tag)] body=\(summarizeBody(raw))")
#endif
    }
    
    // MARK: - API
    
    static func fetchCalendars() async throws -> [CalendarItem] {
        let base = try ScheduleService.resolvedBaseURLForNetworking()
        guard let url = URL(string: base + "/api/v1/feishu/calendar/list") else {
            throw ServiceError.invalidResponse
        }
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        try ScheduleService.applyCommonHeadersForNetworking(to: &request)
        debugPrintRequest(request, tag: "calendar_list")
        
        let (data, response) = try await withTimeout(15) {
            try await URLSession.shared.data(for: request)
        }
        debugPrintResponse(data: data, response: response, tag: "calendar_list")
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpStatus(http.statusCode, body)
        }
        
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let root = json as? [String: Any] else { throw ServiceError.parseFailed("root not dict") }
        let dataDict = (root["data"] as? [String: Any]) ?? root
        guard let calendars = dataDict["calendars"] as? [[String: Any]] else { return [] }
        
        return calendars.compactMap { dict in
            guard let cid = (dict["calendar_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cid.isEmpty
            else { return nil }
            let name = ((dict["name"] as? String) ?? (dict["summary"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            
            return CalendarItem(
                calendarId: cid,
                name: name,
                description: (dict["description"] as? String),
                color: dict["color"] as? Int,
                type: dict["type"] as? String,
                permission: (dict["permission"] as? String) ?? (dict["permissions"] as? String)
            )
        }
    }
    
    static func sync(calendarId: String) async throws -> SyncAck {
        let cid = calendarId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { throw ServiceError.parseFailed("calendar_id empty") }
        
        let base = try ScheduleService.resolvedBaseURLForNetworking()
        guard let url = URL(string: base + "/api/v1/feishu/calendar/sync") else {
            throw ServiceError.invalidResponse
        }
        
        // 不设置超时限制
        var request = URLRequest(url: url, timeoutInterval: .infinity)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try ScheduleService.applyCommonHeadersForNetworking(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["calendar_id": cid], options: [])
        debugPrintRequest(request, tag: "calendar_sync")
        
        #if DEBUG
        print("🗓️ [FeishuCalendarBackend][calendar_sync] 开始同步，不设置超时限制...")
        #endif
        
        // 直接请求，不使用 withTimeout
        let (data, response) = try await URLSession.shared.data(for: request)
        
        debugPrintResponse(data: data, response: response, tag: "calendar_sync")
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.httpStatus(http.statusCode, raw)
        }
        
        #if DEBUG
        print("🗓️ [FeishuCalendarBackend][calendar_sync] ===== 完整响应内容 =====")
        print(raw)
        print("🗓️ [FeishuCalendarBackend][calendar_sync] ===== 响应内容结束 =====")
        #endif
        
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let root = json as? [String: Any] else { throw ServiceError.parseFailed("root not dict") }
        
        let message = (root["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "同步完成"
        let code = (root["code"] as? Int) ?? 200
        if code != 200 {
            throw ServiceError.httpStatus(code, message)
        }
        
        #if DEBUG
        print("🗓️ [FeishuCalendarBackend][calendar_sync] 同步完成：code=\(code), message=\(message)")
        #endif
        
        return SyncAck(message: message)
    }
}
