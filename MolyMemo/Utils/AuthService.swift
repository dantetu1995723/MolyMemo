import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AuthService {
    enum AuthError: LocalizedError {
        case invalidBaseURL
        case invalidResponse
        case httpError(Int, String?)
        case missingToken(String?)
        
        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "后端 Base URL 为空或不合法，请先在「聊天后端」里配置"
            case .invalidResponse:
                return "登录失败：服务端返回异常"
            case let .httpError(code, message):
                if let message, !message.isEmpty { return "登录失败：\(message)（HTTP \(code)）" }
                return "登录失败（HTTP \(code)）"
            case let .missingToken(raw):
                if let raw, !raw.isEmpty {
                    return "登录失败：未返回 token（\(raw)）"
                }
                return "登录失败：未返回 token"
            }
        }
    }
    
    static func login(baseURL: String, phone: String, verificationCode: String) async throws -> String {
        let normalizedBase = BackendChatConfig.normalizeBaseURL(baseURL)
        guard !normalizedBase.isEmpty else { throw AuthError.invalidBaseURL }
        guard let url = URL(string: normalizedBase + "/api/v1/auth/login") else {
            throw AuthError.invalidBaseURL
        }
        
        let body: [String: String] = [
            "phone": phone,
            "verification_code": verificationCode
        ]
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        
        let raw = String(data: data, encoding: .utf8)
        
        guard (200...299).contains(http.statusCode) else {
            throw AuthError.httpError(http.statusCode, raw)
        }
        
        if let token = extractToken(from: data) {
            return token
        }
        
        throw AuthError.missingToken(raw)
    }

    static func logout(baseURL: String, sessionId: String) async throws {
        let normalizedBase = BackendChatConfig.normalizeBaseURL(baseURL)
        guard !normalizedBase.isEmpty else { throw AuthError.invalidBaseURL }
        guard let url = URL(string: normalizedBase + "/api/v1/auth/logout") else {
            throw AuthError.invalidBaseURL
        }
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        
        let raw = String(data: data, encoding: .utf8)
        
        guard (200...299).contains(http.statusCode) else {
            throw AuthError.httpError(http.statusCode, raw)
        }
    }
    
    private static func extractToken(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        
        func pick(_ value: Any?) -> String? {
            guard let s = value as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        
        // 常见字段名：token / access_token
        if let t = pick(obj["token"]) { return t }
        if let t = pick(obj["access_token"]) { return t }
        
        // 常见包一层：data.token / data.access_token / data.session_id
        if let data = obj["data"] as? [String: Any] {
            if let t = pick(data["token"]) { return t }
            if let t = pick(data["access_token"]) { return t }
            if let t = pick(data["session_id"]) { return t }
        }
        
        return nil
    }
}


