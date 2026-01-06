import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 人脉后端服务：/api/v1/contacts（列表）与 /api/v1/contacts/{id}（详情/更新/删除）
/// - 复用 BackendChatConfig.baseURL + X-Session-Id 等公共 header（与 ScheduleService 一致）
enum ContactService {
    enum ContactServiceError: LocalizedError {
        case invalidBaseURL
        case missingSessionId
        case invalidResponse
        case httpStatus(Int, String)
        case parseFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "无效的后端地址（baseURL）"
            case .missingSessionId: return "缺少登录态（X-Session-Id）"
            case .invalidResponse: return "无效的响应"
            case let .httpStatus(code, _): return "HTTP \(code)"
            case let .parseFailed(msg): return "解析失败：\(msg)"
            }
        }
    }
    
    struct ListParams: Equatable, Hashable {
        var page: Int? = nil
        var pageSize: Int? = nil
        var search: String? = nil
        /// 后端字段：relationship_type
        var relationshipType: String? = nil
    }
    
    // MARK: - Cache
    
    private struct AllPagesKey: Hashable {
        var base: ListParams
        var maxPages: Int
        var pageSize: Int
    }
    
    private static let listCache = ExpiringAsyncCache<ListParams, [ContactCard]>()
    private static let detailCache = ExpiringAsyncCache<String, ContactCard>()
    private static let allPagesCache = ExpiringAsyncCache<AllPagesKey, [ContactCard]>()
    
    /// 默认：列表 2 分钟、详情 10 分钟
    private static let defaultListTTL: TimeInterval = 120
    private static let defaultDetailTTL: TimeInterval = 600
    private static let defaultAllPagesTTL: TimeInterval = 120
    
    static func invalidateContactCaches() async {
        await listCache.invalidateAll()
        await detailCache.invalidateAll()
        await allPagesCache.invalidateAll()
    }
    
    static func peekContactList(params: ListParams = .init()) async -> (value: [ContactCard], isFresh: Bool)? {
        if let s = await listCache.peek(params) { return (s.value, s.isFresh) }
        return nil
    }
    
    static func peekContactDetail(remoteId: String) async -> (value: ContactCard, isFresh: Bool)? {
        let k = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        if let s = await detailCache.peek(k) { return (s.value, s.isFresh) }
        return nil
    }
    
    static func peekAllContacts(maxPages: Int = 5, pageSize: Int = 100, baseParams: ListParams = .init()) async -> (value: [ContactCard], isFresh: Bool)? {
        var base = baseParams
        base.page = nil
        base.pageSize = nil
        let k = AllPagesKey(base: base, maxPages: maxPages, pageSize: pageSize)
        if let s = await allPagesCache.peek(k) { return (s.value, s.isFresh) }
        return nil
    }
    
    private enum AuthKeys {
        static let sessionId = "yuanyuan_auth_session_id"
    }
    
    private static let listPath = "/api/v1/contacts"
    private static func detailPath(_ id: String) -> String { "/api/v1/contacts/\(id)" }
    
    private static func resolvedBaseURL() throws -> String {
        let candidate = BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = candidate.isEmpty ? BackendChatConfig.defaultBaseURL : candidate
        let normalized = BackendChatConfig.normalizeBaseURL(base)
        guard !normalized.isEmpty else { throw ContactServiceError.invalidBaseURL }
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
            throw ContactServiceError.missingSessionId
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
        // 默认关闭，避免联系人/日程列表刷爆控制台；需要时可在设置里打开 BackendChatConfig.debugLogFullResponse
        return BackendChatConfig.debugLogFullResponse
#else
        return false
#endif
    }

    /// 将完整原始日志落盘（避免 Xcode 控制台截断）
    private static var debugDumpLogsToFileEnabled: Bool {
#if DEBUG
        // 默认关闭；需要时可在设置里打开 BackendChatConfig.debugDumpResponseToFile
        return BackendChatConfig.debugDumpResponseToFile
#else
        return false
#endif
    }

    private static func debugLogsDirectoryURL() -> URL? {
        guard debugDumpLogsToFileEnabled else { return nil }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("MolyMemo-NetworkLogs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    private static func debugWriteLogFile(prefix: String, tag: String, text: String) {
        guard let dir = debugLogsDirectoryURL() else { return }
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeTag = tag.replacingOccurrences(of: "/", with: "_")
        let filename = "\(ts)_ContactService_\(safeTag)_\(prefix).log"
        let url = dir.appendingPathComponent(filename)
        do {
            try text.data(using: .utf8)?.write(to: url, options: [.atomic])
            if debugLogsEnabled {
            }
        } catch {
            if debugLogsEnabled {
            }
        }
    }
    
    private static func debugPrintRequest(_ request: URLRequest, tag: String) {
        guard debugLogsEnabled else { return }
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "(nil)"
        let headers = request.allHTTPHeaderFields ?? [:]

        if debugDumpLogsToFileEnabled {
            var lines: [String] = []
            lines.append("[REQUEST] \(method) \(url)")
            if !headers.isEmpty {
                lines.append("[REQUEST_HEADERS]")
                for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
                    if k.lowercased() == "x-session-id" {
                        lines.append("\(k): \(maskedSessionId(v))")
                    } else {
                        lines.append("\(k): \(v)")
                    }
                }
            }
            if let body = request.httpBody, !body.isEmpty {
                let raw = String(data: body, encoding: .utf8) ?? "<non-utf8 body: \(body.count) bytes>"
                lines.append("[REQUEST_BODY_UTF8]")
                lines.append(raw)
            } else {
                lines.append("[REQUEST_BODY] <empty>")
            }
            debugWriteLogFile(prefix: "request", tag: tag, text: lines.joined(separator: "\n"))
        }
    }
    
    private static func debugPrintResponse(data: Data, response: URLResponse?, error: Error?, tag: String) {
        guard debugLogsEnabled else { return }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"

        if debugDumpLogsToFileEnabled {
            var lines: [String] = []
            if let http = response as? HTTPURLResponse {
                lines.append("[RESPONSE] status=\(http.statusCode)")
                let pairs = http.allHeaderFields.compactMap { (k, v) -> (String, String)? in
                    let ks = String(describing: k)
                    let vs = String(describing: v)
                    return (ks, vs)
                }.sorted(by: { $0.0 < $1.0 })
                if !pairs.isEmpty {
                    lines.append("[RESPONSE_HEADERS]")
                    for (k, v) in pairs {
                        lines.append("\(k): \(v)")
                    }
                }
            } else {
                lines.append("[RESPONSE] status=(non-http)")
            }
            if let error {
                lines.append("[ERROR]")
                lines.append(String(describing: error))
            }
            lines.append("[RESPONSE_BODY_UTF8] (\(data.count) bytes)")
            lines.append(body)
            debugWriteLogFile(prefix: "response", tag: tag, text: lines.joined(separator: "\n"))
        }
    }

#if DEBUG
    /// 避免 Xcode 控制台截断超长 JSON：分段打印
    private static func debugPrintLongString(_ s: String, chunkSize: Int) {
        guard chunkSize > 0 else { return }
        guard !s.isEmpty else { return }
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let end = min(i + chunkSize, chars.count)
            print(String(chars[i..<end]))
            i = end
        }
    }

    /// 只用于“创建接口”：无视 debug 开关，强制打印后端原始 JSON + 返回字段（便于你核对字段）。
    private static func debugAlwaysPrintRawCreateJSON(data: Data, statusCode: Int?) {
        guard !data.isEmpty else { return }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        let statusPart = statusCode.map { "[status=\($0)]" } ?? ""

        var fieldSummary: [String] = []
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            func keysLine(_ dict: [String: Any], label: String) -> String {
                let keys = dict.keys.sorted()
                return "\(label) keys(\(keys.count)): " + keys.joined(separator: ", ")
            }

            if let dict = obj as? [String: Any] {
                fieldSummary.append(keysLine(dict, label: "[root]"))
                if let d = dict["data"] as? [String: Any] {
                    fieldSummary.append(keysLine(d, label: "[root.data]"))
                } else if let arr = dict["data"] as? [[String: Any]], let first = arr.first {
                    fieldSummary.append("[root.data] array count=\(arr.count)")
                    fieldSummary.append(keysLine(first, label: "[root.data[0]]"))
                }
            } else if let arr = obj as? [[String: Any]] {
                fieldSummary.append("[root] array count=\(arr.count)")
                if let first = arr.first {
                    fieldSummary.append(keysLine(first, label: "[root[0]]"))
                }
            }
        }

        let header = "[ContactCreate]\(statusPart) backend return fields:"
        let summary = fieldSummary.isEmpty ? "" : ("\n" + fieldSummary.joined(separator: "\n"))
        debugPrintLongString(header + summary + "\n\n" + body, chunkSize: 900)
        AppGroupDebugLog.append(header + summary + " " + body)
    }

    /// 只用于“详情接口”：无视 debug 开关，强制打印后端原始 JSON（便于你核对字段）。
    private static func debugAlwaysPrintRawDetailJSON(data: Data, remoteId: String) {
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        let header = "[ContactDetail][id=\(remoteId)] raw json:"
        debugPrintLongString(header + "\n" + body, chunkSize: 900)
        AppGroupDebugLog.append(header + " " + body)
    }

    /// 只用于“更新接口”：无视 debug 开关，强制打印后端原始 JSON（便于你核对字段）。
    private static func debugAlwaysPrintRawUpdateJSON(data: Data, remoteId: String, statusCode: Int?) {
        guard !data.isEmpty else { return }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        let statusPart = statusCode.map { "[status=\($0)]" } ?? ""
        let header = "[ContactUpdate][id=\(remoteId)]\(statusPart) raw json:"
        debugPrintLongString(header + "\n" + body, chunkSize: 900)
        AppGroupDebugLog.append(header + " " + body)
    }
#endif
    
    private static func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let base = try resolvedBaseURL()
        guard var comps = URLComponents(string: base + path) else {
            throw ContactServiceError.invalidBaseURL
        }
        if !queryItems.isEmpty {
            comps.queryItems = queryItems
        }
        guard let url = comps.url else { throw ContactServiceError.invalidBaseURL }
        return url
    }
    
    private static func decodeJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw ContactServiceError.parseFailed("json decode failed, raw=\(raw)")
        }
    }
    
    // MARK: - Parse
    
    private static func extractContactArray(_ json: Any) -> [[String: Any]] {
        if let arr = json as? [[String: Any]] { return arr }
        if let root = json as? [String: Any] {
            let candidates: [Any?] = [root["items"], root["results"], root["contacts"], root["list"], root["rows"]]
            for c in candidates {
                if let a = c as? [[String: Any]] { return a }
            }
            if let dataDict = root["data"] as? [String: Any] {
                let nested: [Any?] = [
                    dataDict["items"], dataDict["results"], dataDict["contacts"],
                    dataDict["list"], dataDict["rows"], dataDict["data"]
                ]
                for c in nested {
                    if let a = c as? [[String: Any]] { return a }
                }
            }
            if let dataArr = root["data"] as? [[String: Any]] { return dataArr }
        }
        return []
    }
    
    private static func parseRemoteId(_ dict: [String: Any]) -> String? {
        if let s = dict["id"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = dict["id"] as? Int { return String(n) }
        if let n = dict["id"] as? Double { return String(Int(n)) }
        if let s = dict["contact_id"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }
    
    private static func string(_ dict: [String: Any], _ keys: [String]) -> String? {
        func coerceToString(_ any: Any?) -> String? {
            guard let any else { return nil }
            if any is NSNull { return nil }
            if let s = any as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if let n = any as? Int { return String(n) }
            if let n = any as? Double {
                // 尽量避免 1.0 这种尾巴影响阅读
                if n.rounded() == n { return String(Int(n)) }
                return String(n)
            }
            if let b = any as? Bool { return b ? "true" : "false" }
            if let dict = any as? [String: Any] {
                // 常见：{ "text": "..." } / { "content": "..." } / { "value": "..." }
                let preferred = ["text", "content", "value", "impression", "notes", "note", "remark"]
                for k in preferred {
                    if let v = coerceToString(dict[k]) { return v }
                }
                return nil
            }
            if let arr = any as? [Any] {
                let parts = arr.compactMap { coerceToString($0) }.filter { !$0.isEmpty }
                if parts.isEmpty { return nil }
                return parts.joined(separator: "\n")
            }
            // 兜底：用描述字符串（避免直接丢字段）
            let s = String(describing: any).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        for k in keys {
            if let t = coerceToString(dict[k]) { return t }
        }
        return nil
    }
    
    private static func parseContactCard(_ dict: [String: Any], keepLocalId: UUID? = nil) -> ContactCard? {
        let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        
        var card = ContactCard(
            name: name,
            englishName: string(dict, ["english_name", "englishName"]),
            company: string(dict, ["company"]),
            title: string(dict, ["position", "title", "job_title"]),
            phone: string(dict, ["phone", "phone_number", "mobile"]),
            email: string(dict, ["email"]),
            birthday: string(dict, ["birthday", "birth", "birthday_text", "birthdayText"]),
            gender: string(dict, ["gender", "sex"]),
            industry: string(dict, ["industry"]),
            location: string(dict, ["location", "region", "city", "address"]),
            relationshipType: string(dict, ["relationship_type", "relationshipType", "relationship"]),
            notes: string(dict, ["notes", "note", "remark"]),
            impression: string(dict, ["impression"]),
            avatarData: nil,
            rawImage: nil
        )
        
        if let keepLocalId { card.id = keepLocalId }
        if let rid = parseRemoteId(dict) {
            card.remoteId = rid
            if keepLocalId == nil, let u = UUID(uuidString: rid) {
                card.id = u
            }
        }
        return card
    }
    
    // MARK: - API
    
    static func fetchContactList(params: ListParams = .init(), forceRefresh: Bool = false) async throws -> [ContactCard] {
        if forceRefresh {
            await listCache.invalidate(params)
        }
        return try await listCache.getOrFetch(params, ttl: defaultListTTL) {
            try await fetchContactListFromNetwork(params: params)
        }
    }
    
    private static func fetchContactListFromNetwork(params: ListParams = .init()) async throws -> [ContactCard] {
        var query: [URLQueryItem] = []
        if let page = params.page { query.append(URLQueryItem(name: "page", value: String(page))) }
        if let pageSize = params.pageSize { query.append(URLQueryItem(name: "page_size", value: String(pageSize))) }
        if let s = params.search?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            query.append(URLQueryItem(name: "search", value: s))
        }
        if let s = params.relationshipType?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            query.append(URLQueryItem(name: "relationship_type", value: s))
        }
        
        let url = try makeURL(path: listPath, queryItems: query)
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        try applyCommonHeaders(to: &request)
        debugPrintRequest(request, tag: "list")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "list")
            
            guard let http = response as? HTTPURLResponse else { throw ContactServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ContactServiceError.httpStatus(http.statusCode, body)
            }
            
            let json = try decodeJSON(data)
            let arr = extractContactArray(json)
            return arr.compactMap { parseContactCard($0, keepLocalId: nil) }
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }
    
    static func fetchContactDetail(remoteId: String, keepLocalId: UUID? = nil, forceRefresh: Bool = false) async throws -> ContactCard {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactServiceError.parseFailed("remoteId empty") }
        
        if forceRefresh {
            await detailCache.invalidate(trimmed)
        }
        
        let cached = try await detailCache.getOrFetch(trimmed, ttl: defaultDetailTTL) {
            try await fetchContactDetailFromNetwork(remoteId: trimmed, keepLocalId: keepLocalId)
        }
        
        if let keepLocalId, cached.id != keepLocalId {
            var v = cached
            v.id = keepLocalId
            return v
        }
        return cached
    }
    
    private static func fetchContactDetailFromNetwork(remoteId: String, keepLocalId: UUID? = nil) async throws -> ContactCard {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactServiceError.parseFailed("remoteId empty") }
        
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
            
            guard let http = response as? HTTPURLResponse else { throw ContactServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ContactServiceError.httpStatus(http.statusCode, body)
            }
            
            let json = try decodeJSON(data)
            if let dict = json as? [String: Any] {
                if let d = dict["data"] as? [String: Any], let c = parseContactCard(d, keepLocalId: keepLocalId) {
                    return c
                }
                if let c = parseContactCard(dict, keepLocalId: keepLocalId) {
                    return c
                }
            }
            if let arr = json as? [[String: Any]], let first = arr.first, let c = parseContactCard(first, keepLocalId: keepLocalId) {
                return c
            }
            throw ContactServiceError.parseFailed("unknown json shape")
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }
    
    /// 常用：拉“全量后端人脉（自动翻页）”并缓存（列表页目前就是这么做的）
    static func fetchContactListAllPages(
        maxPages: Int = 5,
        pageSize: Int = 100,
        baseParams: ListParams = .init(),
        forceRefresh: Bool = false
    ) async throws -> [ContactCard] {
        var base = baseParams
        base.page = nil
        base.pageSize = nil
        let k = AllPagesKey(base: base, maxPages: maxPages, pageSize: pageSize)
        
        if forceRefresh {
            await allPagesCache.invalidate(k)
        }
        
        return try await allPagesCache.getOrFetch(k, ttl: defaultAllPagesTTL) {
            var all: [ContactCard] = []
            for page in 1...maxPages {
                var p = base
                p.page = page
                p.pageSize = pageSize
                let list = try await fetchContactListFromNetwork(params: p)
                all.append(contentsOf: list)
                if list.count < pageSize { break }
            }
            return all
        }
    }
    
    /// 更新人脉：PUT /api/v1/contacts/{id}
    static func updateContact(remoteId: String, payload: [String: Any], keepLocalId: UUID? = nil) async throws -> ContactCard? {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactServiceError.parseFailed("remoteId empty") }
        
        let url = try makeURL(path: detailPath(trimmed), queryItems: [])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try applyCommonHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        debugPrintRequest(request, tag: "update")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "update")
            
#if DEBUG
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            debugAlwaysPrintRawUpdateJSON(data: data, remoteId: trimmed, statusCode: statusCode)
#endif
            
            guard let http = response as? HTTPURLResponse else { throw ContactServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ContactServiceError.httpStatus(http.statusCode, body)
            }
            
            guard !data.isEmpty else {
                await detailCache.invalidate(trimmed)
                await listCache.invalidateAll()
                await allPagesCache.invalidateAll()
                return nil
            }
            let json = try decodeJSON(data)
            if let dict = json as? [String: Any] {
                if let d = dict["data"] as? [String: Any], let c = parseContactCard(d, keepLocalId: keepLocalId) {
                    // ⚠️ update 接口的返回体可能是“部分字段”，不要把它当作“详情”写进 detailCache，
                    // 否则详情页命中缓存时会把缺失字段清空（applyRemoteDetailCard 以详情为真相）。
                    await detailCache.invalidate(trimmed)
                    await listCache.invalidateAll()
                    await allPagesCache.invalidateAll()
                    return c
                }
                if let c = parseContactCard(dict, keepLocalId: keepLocalId) {
                    await detailCache.invalidate(trimmed)
                    await listCache.invalidateAll()
                    await allPagesCache.invalidateAll()
                    return c
                }
                await detailCache.invalidate(trimmed)
                await listCache.invalidateAll()
                await allPagesCache.invalidateAll()
                return nil
            }
            if let arr = json as? [[String: Any]], let first = arr.first, let c = parseContactCard(first, keepLocalId: keepLocalId) {
                await detailCache.invalidate(trimmed)
                await listCache.invalidateAll()
                await allPagesCache.invalidateAll()
                return c
            }
            await detailCache.invalidate(trimmed)
            await listCache.invalidateAll()
            await allPagesCache.invalidateAll()
            return nil
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }

    /// 创建人脉：POST /api/v1/contacts
    /// - Returns: 若后端返回 body，则解析为 ContactCard；若 body 为空则返回 nil（但会视为创建成功）。
    static func createContact(payload: [String: Any], keepLocalId: UUID? = nil) async throws -> ContactCard? {
        let url = try makeURL(path: listPath, queryItems: [])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try applyCommonHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        debugPrintRequest(request, tag: "create")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "create")

#if DEBUG
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            debugAlwaysPrintRawCreateJSON(data: data, statusCode: statusCode)
#endif

            guard let http = response as? HTTPURLResponse else { throw ContactServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ContactServiceError.httpStatus(http.statusCode, body)
            }

            // 后端可能返回空 body（例如 204/200 with empty）——仍视为成功，但需要调用方决定是否再拉详情
            guard !data.isEmpty else {
                await listCache.invalidateAll()
                await allPagesCache.invalidateAll()
                return nil
            }

            let json = try decodeJSON(data)
            if let dict = json as? [String: Any] {
                if let d = dict["data"] as? [String: Any], let c = parseContactCard(d, keepLocalId: keepLocalId) {
                    // ⚠️ create 接口返回体可能是“部分字段”，不要污染详情缓存；
                    // 让详情页首次打开直接 GET /contacts/{id} 拿全量。
                    if let rid = c.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
                        await detailCache.invalidate(rid)
                    }
                    await listCache.invalidateAll()
                    await allPagesCache.invalidateAll()
                    return c
                }
                if let c = parseContactCard(dict, keepLocalId: keepLocalId) {
                    if let rid = c.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
                        await detailCache.invalidate(rid)
                    }
                    await listCache.invalidateAll()
                    await allPagesCache.invalidateAll()
                    return c
                }
            }
            if let arr = json as? [[String: Any]], let first = arr.first, let c = parseContactCard(first, keepLocalId: keepLocalId) {
                if let rid = c.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
                    await detailCache.invalidate(rid)
                }
                await listCache.invalidateAll()
                await allPagesCache.invalidateAll()
                return c
            }

            await listCache.invalidateAll()
            await allPagesCache.invalidateAll()
            return nil
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }
    
    /// 删除人脉：DELETE /api/v1/contacts/{id}
    static func deleteContact(remoteId: String) async throws {
        let trimmed = remoteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactServiceError.parseFailed("remoteId empty") }
        
        let url = try makeURL(path: detailPath(trimmed), queryItems: [])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "DELETE"
        try applyCommonHeaders(to: &request)
        debugPrintRequest(request, tag: "delete")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugPrintResponse(data: data, response: response, error: nil, tag: "delete")
            
            guard let http = response as? HTTPURLResponse else { throw ContactServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ContactServiceError.httpStatus(http.statusCode, body)
            }
            
            await detailCache.invalidate(trimmed)
            await listCache.invalidateAll()
            await allPagesCache.invalidateAll()
        } catch {
            if debugLogsEnabled {
            }
            throw error
        }
    }
}


