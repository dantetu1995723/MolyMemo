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
    
    struct ListParams: Equatable {
        var page: Int? = nil
        var pageSize: Int? = nil
        var search: String? = nil
        /// 后端字段：relationship_type
        var relationshipType: String? = nil
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
            print("❌ [ContactService] 缺少 X-Session-Id：请先登录，或检查 AuthStore 是否成功保存 sessionId")
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
    
    private static func debugPrintRequest(_ request: URLRequest, tag: String) {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "(nil)"
        print("🌐 [ContactService:\(tag)] \(method) \(url)")
        let headers = request.allHTTPHeaderFields ?? [:]
        if headers.isEmpty { return }
        print("🌐 [ContactService:\(tag)] headers:")
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
            if k.lowercased() == "x-session-id" {
                print("  \(k): \(maskedSessionId(v))")
            } else {
                print("  \(k): \(v)")
            }
        }
    }
    
    private static func debugPrintResponse(data: Data, response: URLResponse?, error: Error?, tag: String) {
        if let error {
            print("❌ [ContactService:\(tag)] error=\(error)")
        }
        if let http = response as? HTTPURLResponse {
            print("🌐 [ContactService:\(tag)] status=\(http.statusCode)")
        } else {
            print("🌐 [ContactService:\(tag)] status=(non-http)")
        }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        print("🌐 [ContactService:\(tag)] raw body:\n\(body)")
    }
    
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
        for k in keys {
            if let v = dict[k] as? String {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
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
    
    static func fetchContactList(params: ListParams = .init()) async throws -> [ContactCard] {
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
            print("❌ [ContactService:list] threw error=\(error)")
            throw error
        }
    }
    
    static func fetchContactDetail(remoteId: String, keepLocalId: UUID? = nil) async throws -> ContactCard {
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
            print("❌ [ContactService:detail] threw error=\(error)")
            throw error
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
            
            guard let http = response as? HTTPURLResponse else { throw ContactServiceError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ContactServiceError.httpStatus(http.statusCode, body)
            }
            
            guard !data.isEmpty else { return nil }
            let json = try decodeJSON(data)
            if let dict = json as? [String: Any] {
                if let d = dict["data"] as? [String: Any] { return parseContactCard(d, keepLocalId: keepLocalId) }
                return parseContactCard(dict, keepLocalId: keepLocalId)
            }
            if let arr = json as? [[String: Any]], let first = arr.first { return parseContactCard(first, keepLocalId: keepLocalId) }
            return nil
        } catch {
            print("❌ [ContactService:update] threw error=\(error)")
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
        } catch {
            print("❌ [ContactService:delete] threw error=\(error)")
            throw error
        }
    }
}


