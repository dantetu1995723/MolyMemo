import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 日程后端服务：/api/v1/schedules（列表）与 /api/v1/schedules/{id}（详情）
/// - 复用 BackendChatConfig.baseURL + X-Session-Id 等公共 header
/// - Debug：打印原始响应 body、HTTP 状态码、以及 error
enum ScheduleService {
    enum ScheduleServiceError: LocalizedError {
        case invalidBaseURL
        case missingSessionId
        case httpStatus(Int, String)
        case invalidResponse
        case parseFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "无效的后端地址（baseURL）"
            case .missingSessionId: return "缺少登录态（X-Session-Id）"
            case let .httpStatus(code, _): return "HTTP \(code)"
            case .invalidResponse: return "无效的响应"
            case let .parseFailed(msg): return "解析失败：\(msg)"
            }
        }
    }
    
    struct ListParams: Equatable, Hashable {
        var page: Int? = nil
        var pageSize: Int? = nil
        /// yyyy-MM-dd
        var startDate: String? = nil
        /// yyyy-MM-dd
        var endDate: String? = nil
        var search: String? = nil
        var category: String? = nil
        var relatedMeetingId: String? = nil
    }
    
    private enum AuthKeys {
        static let sessionId = "yuanyuan_auth_session_id"
    }
    
    private static let listPath = "/api/v1/schedules"
    private static func detailPath(_ id: String) -> String { "/api/v1/schedules/\(id)" }
    
    // MARK: - Cache
    
    private struct AllPagesKey: Hashable {
        var base: ListParams
        var maxPages: Int
        var pageSize: Int
    }
    
    private static let listCache = ExpiringAsyncCache<ListParams, [ScheduleEvent]>()
    private static let detailCache = ExpiringAsyncCache<String, ScheduleEvent>()
    private static let allPagesCache = ExpiringAsyncCache<AllPagesKey, [ScheduleEvent]>()
    
    /// 默认：列表 2 分钟、详情 10 分钟（只影响“是否复用缓存”，不改变后端数据）
    private static let defaultListTTL: TimeInterval = 120
    private static let defaultDetailTTL: TimeInterval = 600
    private static let defaultAllPagesTTL: TimeInterval = 120
    
    /// 统一从主线程广播远端日程变更，避免 `.onReceive(NotificationCenter.publisher)` 在后台线程回调导致 SwiftUI/ObservableObject 警告与卡顿。
    private static func postRemoteScheduleDidChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .remoteScheduleDidChange, object: nil, userInfo: nil)
        }
    }
    
    /// 统一入口：缓存失效 + 广播远端日程变更
    /// - Note: ChatView / TodoListView 会监听该通知并 `forceRefresh: true` 拉后端
    static func invalidateCachesAndNotifyRemoteScheduleDidChange() async {
        await invalidateScheduleCaches()
        await postRemoteScheduleDidChange()
    }
    
    static func invalidateScheduleCaches() async {
        // 只让缓存失效，不要取消进行中的请求：
        // - ChatView / TodoListView 可能同时收到通知并发刷新
        // - 如果这里 cancel in-flight，会造成 NSURLErrorDomain -999（cancelled）以及重复 GET
        await listCache.invalidateAll(cancelInFlight: false)
        await detailCache.invalidateAll(cancelInFlight: false)
        await allPagesCache.invalidateAll(cancelInFlight: false)
    }
    
    static func peekScheduleList(params: ListParams = .init()) async -> (value: [ScheduleEvent], isFresh: Bool)? {
        if let s = await listCache.peek(params) { return (s.value, s.isFresh) }
        return nil
    }
    
    static func peekScheduleDetail(remoteId: String) async -> (value: ScheduleEvent, isFresh: Bool)? {
        let k = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        if let s = await detailCache.peek(k) { return (s.value, s.isFresh) }
        return nil
    }
    
    static func peekAllSchedules(maxPages: Int = 5, pageSize: Int = 100, baseParams: ListParams = .init()) async -> (value: [ScheduleEvent], isFresh: Bool)? {
        var base = baseParams
        base.page = nil
        base.pageSize = nil
        let k = AllPagesKey(base: base, maxPages: maxPages, pageSize: pageSize)
        if let s = await allPagesCache.peek(k) { return (s.value, s.isFresh) }
        return nil
    }
    
    private static func resolvedBaseURL() throws -> String {
        let candidate = BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = candidate.isEmpty ? BackendChatConfig.defaultBaseURL : candidate
        let normalized = BackendChatConfig.normalizeBaseURL(base)
        guard !normalized.isEmpty else { throw ScheduleServiceError.invalidBaseURL }
        return normalized
    }
    
    private static func currentSessionId() -> String? {
        let fromConfig = BackendChatConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromConfig.isEmpty { return fromConfig }
        let fromDefaults = (UserDefaults.standard.string(forKey: AuthKeys.sessionId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fromDefaults.isEmpty ? nil : fromDefaults
    }
    
    private static func applyCommonHeaders(to request: inout URLRequest) throws {
        guard let sessionId = currentSessionId(), !sessionId.isEmpty else {
            if debugLogsEnabled {
            }
            throw ScheduleServiceError.missingSessionId
        }
        
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        
#if canImport(UIKit)
        let appId = Bundle.main.bundleIdentifier ?? ""
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        let osVersion = UIDevice.current.systemVersion
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        
        request.setValue(appId, forHTTPHeaderField: "X-App-Id")
        request.setValue(appVersion.isEmpty ? "" : "\(appVersion) (\(build))", forHTTPHeaderField: "X-App-Version")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-OS-Type")
        request.setValue(osVersion, forHTTPHeaderField: "X-OS-Version")
        
        // 地理信息：当前工程未接入定位，先留空
        request.setValue("", forHTTPHeaderField: "X-Longitude")
        request.setValue("", forHTTPHeaderField: "X-Latitude")
        request.setValue("", forHTTPHeaderField: "X-Address")
        request.setValue("", forHTTPHeaderField: "X-City")
        request.setValue("", forHTTPHeaderField: "X-Country")
#endif
    }
    
    private static func maskedSessionId(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 8 else { return "***" }
        return "\(t.prefix(4))***\(t.suffix(4))"
    }

    private static var debugLogsEnabled: Bool {
#if DEBUG
        // ✅ 工具箱「日程」时间问题排查：仅对 ScheduleService 单独开关（默认开启）
        // - 目的：打印 /api/v1/schedules 的原始 JSON，便于对照后端字段
        // - 关闭方式：把 BackendChatConfig.debugScheduleServiceRawLog 设为 false（可通过调试代码或 UserDefaults 修改）
        return BackendChatConfig.debugScheduleServiceRawLog
#else
        return false
#endif
    }
    
    private static func debugPrintRequest(_ request: URLRequest, tag: String) {
        guard debugLogsEnabled else { return }
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "(nil)"
        let headers = request.allHTTPHeaderFields ?? [:]
        print("[ScheduleService][\(tag)] \(method) \(url)")
        if headers.isEmpty { return }
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
            if k.lowercased() == "x-session-id" {
                print("[ScheduleService][\(tag)] \(k): \(maskedSessionId(v))")
            } else {
                print("[ScheduleService][\(tag)] \(k): \(v)")
            }
        }
    }
    
    private static func debugPrintResponse(data: Data, response: URLResponse?, error: Error?, tag: String) {
        guard debugLogsEnabled else { return }
        if let http = response as? HTTPURLResponse {
            print("[ScheduleService][\(tag)] status=\(http.statusCode)")
        } else {
            print("[ScheduleService][\(tag)] status=(non-http)")
        }
        if let error {
            print("[ScheduleService][\(tag)] error=\(error)")
        }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        printLongString(body, chunkSize: 900)
    }

    /// 避免 Xcode 控制台截断超长 JSON：分段打印
    private static func printLongString(_ s: String, chunkSize: Int) {
        guard chunkSize > 0 else {
            return
        }
        if s.isEmpty {
            return
        }
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let end = min(i + chunkSize, chars.count)
            print(String(chars[i..<end]))
            i = end
        }
    }

#if DEBUG
    /// 只用于“详情接口”：无视 debug 开关，强制打印后端原始 JSON（便于你核对字段）。
    private static func debugAlwaysPrintRawDetailJSON(data: Data, remoteId: String) {
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        let header = "[ScheduleDetail][id=\(remoteId)] raw json:"
        printLongString(header + "\n" + body, chunkSize: 900)
        AppGroupDebugLog.append(header + " " + body)
    }
#endif

    private static func debugPrintParsedTimeFieldsIfNeeded(raw dict: [String: Any], parsed event: ScheduleEvent) {
        guard debugLogsEnabled else { return }
        func anyToString(_ any: Any?) -> String {
            guard let any else { return "nil" }
            if any is NSNull { return "null" }
            if let s = any as? String { return "\"\(s)\"" }
            if let n = any as? Int { return "\(n)" }
            if let n = any as? Double { return "\(n)" }
            if let b = any as? Bool { return b ? "true" : "false" }
            return "\(any)"
        }
        let fullDayRaw = dict["full_day"] ?? dict["fullDay"]
        let startRaw = dict["start_time"] ?? dict["startTime"] ?? dict["start_date"] ?? dict["startDate"]
        let endRaw = dict["end_time"] ?? dict["endTime"] ?? dict["end_date"] ?? dict["endDate"]
        let tzName = TimeZone.current.identifier
        print("[ScheduleService][parse] tz=\(tzName) fullDayRaw=\(anyToString(fullDayRaw)) startRaw=\(anyToString(startRaw)) endRaw=\(anyToString(endRaw)) -> start=\(event.startTime) end=\(event.endTime) endProvided=\(event.endTimeProvided)")
    }
    
    private static func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let base = try resolvedBaseURL()
        guard var comps = URLComponents(string: base + path) else {
            throw ScheduleServiceError.invalidBaseURL
        }
        if !queryItems.isEmpty {
            comps.queryItems = queryItems
        }
        guard let url = comps.url else { throw ScheduleServiceError.invalidBaseURL }
        return url
    }
    
    private static func decodeJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw ScheduleServiceError.parseFailed("json decode failed, raw=\(raw)")
        }
    }

    /// 统一：把 Date 按“本地时间语义”序列化给后端（不带时区）。
    /// 目标：后端返回什么时间，前端就显示什么时间，避免 iOS/后端双方因时区标记产生偏移。
    private static func localDateTimeStringNoTimeZone(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.string(from: date)
    }
    
    private static func stripTimeZoneSuffixIfPresent(_ s: String) -> String {
        var base = s
        if base.hasSuffix("Z") {
            base.removeLast()
            return base
        }
        // ±HH:mm
        if let r = base.range(of: "[+-]\\d{2}:\\d{2}$", options: .regularExpression) {
            base.removeSubrange(r)
            return base
        }
        return base
    }
    
    private static func normalizeISO8601FractionalSecondsToMillis(_ s: String) -> String {
        var base = s
        var tzSuffix = ""
        
        if base.hasSuffix("Z") {
            tzSuffix = "Z"
            base.removeLast()
        } else if let r = base.range(of: "[+-]\\d{2}:\\d{2}$", options: .regularExpression) {
            tzSuffix = String(base[r])
            base.removeSubrange(r)
        }
        
        guard let dot = base.firstIndex(of: ".") else { return s }
        let fracStart = base.index(after: dot)
        guard fracStart < base.endIndex else { return s }
        let frac = String(base[fracStart..<base.endIndex])
        guard !frac.isEmpty, frac.allSatisfy({ $0.isNumber }) else { return s }
        
        let millis: String = {
            if frac.count == 3 { return frac }
            if frac.count > 3 { return String(frac.prefix(3)) }
            return frac.padding(toLength: 3, withPad: "0", startingAt: 0)
        }()
        
        let head = String(base[..<dot])
        return head + "." + millis + tzSuffix
    }
    
    private static func parseDate(_ any: Any?) -> Date? {
        guard let any else { return nil }
        if let d = any as? Date { return d }
        if let n = any as? Double { return Date(timeIntervalSince1970: n) }
        if let n = any as? Int { return Date(timeIntervalSince1970: Double(n)) }
        if let s0 = any as? String {
            let s = s0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            
            // 统一策略：不论后端是否带 Z/±HH:mm，都按“本地时间语义”解析（忽略时区后缀）
            // 这样“后端返回什么时间，前端就显示什么时间”，避免列表/详情/卡片出现小时偏移。
            let normalized = normalizeISO8601FractionalSecondsToMillis(s)
            let withoutTZ = stripTimeZoneSuffixIfPresent(normalized)

            // ✅ 后端常见：不带时区的 ISO 字符串（如 2025-12-26T21:00:00）
            // 使用 POSIX locale，避免 12/24 小时制、地区设置导致解析失败
            let posix = Locale(identifier: "en_US_POSIX")
            // 约定：当后端返回“不带时区”的时间串时，按“本地时间语义”理解（例如 14:00 就是本地 14:00）。
            // 否则会出现中国时区常见的 +8 小时偏移（14:00 -> 22:00）。
            let tz = TimeZone.current

            let f5 = DateFormatter()
            f5.locale = posix
            f5.timeZone = tz
            f5.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            if let d = f5.date(from: withoutTZ) { return d }

            let f6 = DateFormatter()
            f6.locale = posix
            f6.timeZone = tz
            f6.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = f6.date(from: withoutTZ) { return d }
            
            let f7 = DateFormatter()
            f7.locale = posix
            f7.timeZone = tz
            f7.dateFormat = "yyyy-MM-dd'T'HH:mm"
            if let d = f7.date(from: withoutTZ) { return d }
            
            // yyyy-MM-dd（列表常见）
            let f3 = DateFormatter()
            f3.locale = Locale(identifier: "zh_CN")
            f3.dateFormat = "yyyy-MM-dd"
            if let d = f3.date(from: withoutTZ) { return d }
            
            // yyyy-MM-dd HH:mm:ss（部分后端）
            let f4 = DateFormatter()
            f4.locale = Locale(identifier: "zh_CN")
            f4.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let d = f4.date(from: withoutTZ) { return d }
        }
        return nil
    }
    
    private static func parseEventDict(_ dict: [String: Any], keepLocalId: UUID? = nil) -> ScheduleEvent? {
        func str(_ keys: [String]) -> String? {
            for k in keys {
                if let v = dict[k] as? String {
                    let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
            return nil
        }
        
        let title = str(["title", "name", "summary"]) ?? ""
        guard !title.isEmpty else { return nil }
        
        let description = str(["description", "desc", "content", "detail"]) ?? ""
        
        // ✅ full_day 优先：按本地时区 00:00~24:00 语义落地（endTime 存次日 00:00，但 UI 展示为 24:00）
        if let fullDayStart = parseFullDayStart(dict["full_day"] ?? dict["fullDay"]) {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: fullDayStart) ?? fullDayStart.addingTimeInterval(86_400)
            var event = ScheduleEvent(title: title, description: description, startTime: fullDayStart, endTime: end)
            event.isFullDay = true
            event.endTimeProvided = true

            if let keepLocalId { event.id = keepLocalId }

            if let rid = str(["id", "schedule_id", "remote_id", "remoteId"]) {
                event.remoteId = rid
                if keepLocalId == nil, let u = UUID(uuidString: rid) {
                    event.id = u
                }
            } else if let idInt = dict["id"] as? Int {
                event.remoteId = String(idInt)
            } else if let idDouble = dict["id"] as? Double {
                event.remoteId = String(Int(idDouble))
            }

            if let c = dict["has_conflict"] as? Bool { event.hasConflict = c }
            if let c = dict["hasConflict"] as? Bool { event.hasConflict = c }
            if let s = dict["is_synced"] as? Bool { event.isSynced = s }
            if let s = dict["isSynced"] as? Bool { event.isSynced = s }

            debugPrintParsedTimeFieldsIfNeeded(raw: dict, parsed: event)
            return event
        }

        // ✅ 关键：start_time 解析失败时不要用 Date() 兜底，否则会把“当前时间/消息时间”误当成日程时间展示
        guard let start =
            parseDate(dict["start_time"])
            ?? parseDate(dict["startTime"])
            ?? parseDate(dict["start_date"])
            ?? parseDate(dict["startDate"])
        else {
#if DEBUG
            let raw = (dict["start_time"] ?? dict["startTime"] ?? dict["start_date"] ?? dict["startDate"])
            if debugLogsEnabled {
                print("[ScheduleService][parse] start_time parse failed raw=\(String(describing: raw))")
            }
#endif
            return nil
        }

        // end_time 可能为 null：不要再“默认 +1h”误导展示
        let endAny: Any? =
            dict["end_time"] ?? dict["endTime"] ?? dict["end_date"] ?? dict["endDate"]
        let parsedEnd = parseDate(endAny)
        let endProvided = (parsedEnd != nil)
        let end = parsedEnd ?? start

        var event = ScheduleEvent(title: title, description: description, startTime: start, endTime: end)
        event.endTimeProvided = endProvided
        
        if let keepLocalId { event.id = keepLocalId }
        
        if let rid = str(["id", "schedule_id", "remote_id", "remoteId"]) {
            event.remoteId = rid
            if keepLocalId == nil, let u = UUID(uuidString: rid) {
                event.id = u
            }
        } else if let idInt = dict["id"] as? Int {
            event.remoteId = String(idInt)
        } else if let idDouble = dict["id"] as? Double {
            event.remoteId = String(Int(idDouble))
        }
        
        if let c = dict["has_conflict"] as? Bool { event.hasConflict = c }
        if let c = dict["hasConflict"] as? Bool { event.hasConflict = c }
        if let s = dict["is_synced"] as? Bool { event.isSynced = s }
        if let s = dict["isSynced"] as? Bool { event.isSynced = s }
        
        debugPrintParsedTimeFieldsIfNeeded(raw: dict, parsed: event)
        return event
    }

    private static func parseFullDayStart(_ any: Any?) -> Date? {
        guard let any else { return nil }
        if let d = any as? Date { return Calendar.current.startOfDay(for: d) }
        guard let s0 = any as? String else { return nil }
        let s = s0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let posix = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = posix
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        guard let d = df.date(from: s) else { return nil }
        return Calendar.current.startOfDay(for: d)
    }
    
    private static func extractEventArray(_ json: Any) -> [[String: Any]] {
        if let arr = json as? [[String: Any]] { return arr }
        if let root = json as? [String: Any] {
            // 1) root 直接就是数组字段
            let candidates: [Any?] = [root["items"], root["results"], root["schedules"], root["list"], root["rows"]]
            for c in candidates {
                if let a = c as? [[String: Any]] { return a }
            }
            
            // 2) 常见：{ data: { items: [...] } }
            if let dataDict = root["data"] as? [String: Any] {
                let nested: [Any?] = [
                    dataDict["items"], dataDict["results"], dataDict["schedules"],
                    dataDict["list"], dataDict["rows"], dataDict["data"]
                ]
                for c in nested {
                    if let a = c as? [[String: Any]] { return a }
                }
            }
            
            // 3) 少数：{ data: [...] }
            if let dataArr = root["data"] as? [[String: Any]] {
                return dataArr
            }
        }
        return []
    }
    
    static func fetchScheduleList(params: ListParams = .init(), forceRefresh: Bool = false) async throws -> [ScheduleEvent] {
        if forceRefresh {
            // 强刷只需让缓存过期即可；如果已有同 key 的 in-flight，直接复用，避免互相取消
            await listCache.invalidate(params, cancelInFlight: false)
        }
        return try await listCache.getOrFetch(params, ttl: defaultListTTL) {
            try await fetchScheduleListFromNetwork(params: params)
        }
    }
    
    private static func fetchScheduleListFromNetwork(params: ListParams = .init()) async throws -> [ScheduleEvent] {
        var query: [URLQueryItem] = []
        if let page = params.page { query.append(URLQueryItem(name: "page", value: String(page))) }
        if let pageSize = params.pageSize { query.append(URLQueryItem(name: "page_size", value: String(pageSize))) }
        if let s = params.startDate?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            query.append(URLQueryItem(name: "start_date", value: s))
        }
        if let s = params.endDate?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            query.append(URLQueryItem(name: "end_date", value: s))
        }
        if let s = params.search?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            query.append(URLQueryItem(name: "search", value: s))
        }
        if let s = params.category?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            query.append(URLQueryItem(name: "category", value: s))
        }
        if let s = params.relatedMeetingId?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            query.append(URLQueryItem(name: "related_meeting_id", value: s))
        }
        
        let url = try makeURL(path: listPath, queryItems: query)
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        try applyCommonHeaders(to: &request)
        debugPrintRequest(request, tag: "list")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "list")
            
            guard let http = response as? HTTPURLResponse else { throw ScheduleServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ScheduleServiceError.httpStatus(http.statusCode, body)
            }
            
            let json = try decodeJSON(data)
            let arr = extractEventArray(json)
            let events = arr.compactMap { parseEventDict($0, keepLocalId: nil) }
            return events
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }
    
    static func fetchScheduleDetail(remoteId: String, keepLocalId: UUID? = nil, forceRefresh: Bool = false) async throws -> ScheduleEvent {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScheduleServiceError.parseFailed("remoteId empty") }
        
        if forceRefresh {
            await detailCache.invalidate(trimmed, cancelInFlight: false)
        }
        
        let cached = try await detailCache.getOrFetch(trimmed, ttl: defaultDetailTTL) {
            try await fetchScheduleDetailFromNetwork(remoteId: trimmed, keepLocalId: keepLocalId)
        }
        
        // 维持 keepLocalId：缓存里可能是不同 local id 的版本，这里对外保证调用方想保留的 id
        if let keepLocalId, cached.id != keepLocalId {
            var v = cached
            v.id = keepLocalId
            return v
        }
        return cached
    }
    
    private static func fetchScheduleDetailFromNetwork(remoteId: String, keepLocalId: UUID? = nil) async throws -> ScheduleEvent {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScheduleServiceError.parseFailed("remoteId empty") }
        
        let url = try makeURL(path: detailPath(trimmed), queryItems: [])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        try applyCommonHeaders(to: &request)
        debugPrintRequest(request, tag: "detail")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "detail")

#if DEBUG
            debugAlwaysPrintRawDetailJSON(data: data, remoteId: trimmed)
#endif
            
            guard let http = response as? HTTPURLResponse else { throw ScheduleServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ScheduleServiceError.httpStatus(http.statusCode, body)
            }
            
            let json = try decodeJSON(data)
            if let dict = json as? [String: Any] {
                // 有些后端会包一层 data
                if let d = dict["data"] as? [String: Any], let ev = parseEventDict(d, keepLocalId: keepLocalId) {
                    return ev
                }
                if let ev = parseEventDict(dict, keepLocalId: keepLocalId) {
                    return ev
                }
            }
            if let arr = json as? [[String: Any]], let first = arr.first, let ev = parseEventDict(first, keepLocalId: keepLocalId) {
                return ev
            }
            throw ScheduleServiceError.parseFailed("unknown json shape")
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }
    
    /// 常用：拉"全量后端日程（自动翻页）”并缓存，适合前端再做日期过滤（TodoListView 目前就是这么做的）
    /// 注意：会循环获取直到没有更多数据，不限制页数
    static func fetchScheduleListAllPages(
        maxPages: Int = Int.max, // 默认不限制，但缓存 key 仍需要这个参数
        pageSize: Int = 100,
        baseParams: ListParams = .init(),
        forceRefresh: Bool = false
    ) async throws -> [ScheduleEvent] {
        var base = baseParams
        base.page = nil
        base.pageSize = nil
        // 使用一个固定的很大的 maxPages 值作为缓存 key，实际获取时会循环直到没有更多数据
        let cacheKeyMaxPages = 10000 // 缓存 key 使用固定值
        let k = AllPagesKey(base: base, maxPages: cacheKeyMaxPages, pageSize: pageSize)
        
        if forceRefresh {
            await allPagesCache.invalidate(k, cancelInFlight: false)
        }
        
        return try await allPagesCache.getOrFetch(k, ttl: defaultAllPagesTTL) {
            var all: [ScheduleEvent] = []
            var page = 1
            while true {
                var p = base
                p.page = page
                p.pageSize = pageSize
                let list = try await fetchScheduleListFromNetwork(params: p)
                all.append(contentsOf: list)
                // 如果返回的数据少于 pageSize，说明已经是最后一页了
                if list.count < pageSize { break }
                page += 1
                // 安全限制：防止无限循环（理论上不应该超过这个值）
                if page > 10000 {
                    break
                }
            }
            return all
        }
    }

    /// 更新日程：PUT /api/v1/schedules/{id}
    /// - Note: 目前客户端只维护 title/description/start_time/end_time；其它字段若后端有默认值，可由后端补齐
    static func updateSchedule(remoteId: String, event: ScheduleEvent) async throws -> ScheduleEvent {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScheduleServiceError.parseFailed("remoteId empty") }

        let url = try makeURL(path: detailPath(trimmed), queryItems: [])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try applyCommonHeaders(to: &request)

        let payload: [String: Any] = [
            "title": event.title,
            "description": event.description,
            "start_time": localDateTimeStringNoTimeZone(event.startTime),
            "end_time": localDateTimeStringNoTimeZone(event.endTime)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        debugPrintRequest(request, tag: "update")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "update")

            guard let http = response as? HTTPURLResponse else { throw ScheduleServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ScheduleServiceError.httpStatus(http.statusCode, body)
            }

            // 有些后端会返回更新后的实体；若返回体不是实体形状，至少返回本地 event
            if data.isEmpty {
                await detailCache.set(trimmed, value: event, ttl: defaultDetailTTL)
                await listCache.invalidateAll(cancelInFlight: false)
                await allPagesCache.invalidateAll(cancelInFlight: false)
                await postRemoteScheduleDidChange()
                return event
            }
            let json = try decodeJSON(data)
            if let dict = json as? [String: Any] {
                if let d = dict["data"] as? [String: Any], let ev = parseEventDict(d, keepLocalId: event.id) {
                    await detailCache.set(trimmed, value: ev, ttl: defaultDetailTTL)
                    await listCache.invalidateAll(cancelInFlight: false)
                    await allPagesCache.invalidateAll(cancelInFlight: false)
                    await postRemoteScheduleDidChange()
                    return ev
                }
                if let ev = parseEventDict(dict, keepLocalId: event.id) {
                    await detailCache.set(trimmed, value: ev, ttl: defaultDetailTTL)
                    await listCache.invalidateAll(cancelInFlight: false)
                    await allPagesCache.invalidateAll(cancelInFlight: false)
                    await postRemoteScheduleDidChange()
                    return ev
                }
            }
            await detailCache.set(trimmed, value: event, ttl: defaultDetailTTL)
            await listCache.invalidateAll(cancelInFlight: false)
            await allPagesCache.invalidateAll(cancelInFlight: false)
            await postRemoteScheduleDidChange()
            return event
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }

    /// 删除日程：DELETE /api/v1/schedules/{id}
    static func deleteSchedule(remoteId: String) async throws {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScheduleServiceError.parseFailed("remoteId empty") }

        let url = try makeURL(path: detailPath(trimmed), queryItems: [])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "DELETE"
        try applyCommonHeaders(to: &request)
        debugPrintRequest(request, tag: "delete")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "delete")

            guard let http = response as? HTTPURLResponse else { throw ScheduleServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                if debugLogsEnabled {
                }
                throw ScheduleServiceError.httpStatus(http.statusCode, body)
            }
            
            await detailCache.invalidate(trimmed)
            await listCache.invalidateAll(cancelInFlight: false)
            await allPagesCache.invalidateAll(cancelInFlight: false)
            await postRemoteScheduleDidChange()
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }
}



