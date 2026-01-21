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

    enum DeactivateError: LocalizedError {
        case invalidBaseURL
        case invalidResponse
        case httpError(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "后端 Base URL 为空或不合法，请先在「聊天后端」里配置"
            case .invalidResponse:
                return "注销失败：服务端返回异常"
            case let .httpError(code, message):
                if let message, !message.isEmpty { return "注销失败：\(message)（HTTP \(code)）" }
                return "注销失败（HTTP \(code)）"
            }
        }
    }

    enum SendCodeError: LocalizedError {
        case invalidBaseURL
        case invalidResponse
        case httpError(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "后端 Base URL 为空或不合法，请先在「聊天后端」里配置"
            case .invalidResponse:
                return "验证码发送失败：服务端返回异常"
            case let .httpError(code, message):
                if let message, !message.isEmpty { return "验证码发送失败：\(message)（HTTP \(code)）" }
                return "验证码发送失败（HTTP \(code)）"
            }
        }
    }
    
    enum UpdateUserInfoError: LocalizedError {
        case invalidBaseURL
        case invalidResponse
        case httpError(Int, String?)
        case parseFailed(String?)
        
        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "后端 Base URL 为空或不合法，请先在「聊天后端」里配置"
            case .invalidResponse:
                return "更新失败：服务端返回异常"
            case let .httpError(code, message):
                if let message, !message.isEmpty { return "更新失败：\(message)（HTTP \(code)）" }
                return "更新失败（HTTP \(code)）"
            case let .parseFailed(raw):
                if let raw, !raw.isEmpty { return "更新失败：解析响应异常（\(raw)）" }
                return "更新失败：解析响应异常"
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

    static func deactivateAccount(baseURL: String, sessionId: String) async throws {
        let normalizedBase = BackendChatConfig.normalizeBaseURL(baseURL)
        guard !normalizedBase.isEmpty else { throw DeactivateError.invalidBaseURL }
        guard let url = URL(string: normalizedBase + "/api/v1/auth/deactivate") else {
            throw DeactivateError.invalidBaseURL
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "DELETE"
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeactivateError.invalidResponse }

        let raw = String(data: data, encoding: .utf8) ?? ""
#if DEBUG || targetEnvironment(simulator)
        print("🧹 deactivate response: \(raw)")
#endif
        guard (200...299).contains(http.statusCode) else {
            throw DeactivateError.httpError(http.statusCode, raw)
        }
    }

    static func sendVerificationCode(baseURL: String, phone: String) async throws {
        let normalizedBase = BackendChatConfig.normalizeBaseURL(baseURL)
        guard !normalizedBase.isEmpty else { throw SendCodeError.invalidBaseURL }
        guard let url = URL(string: normalizedBase + "/api/v1/auth/send-verification-code") else {
            throw SendCodeError.invalidBaseURL
        }

        let body: [String: String] = [
            "phone": phone
        ]

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SendCodeError.invalidResponse }

        let raw = String(data: data, encoding: .utf8) ?? ""
#if DEBUG || targetEnvironment(simulator)
        print("📩 send-verification-code response: \(raw)")
#endif
        guard (200...299).contains(http.statusCode) else {
            throw SendCodeError.httpError(http.statusCode, raw)
        }
    }

    // MARK: - User Info

    /// 获取当前用户信息（原始返回字符串，便于你核对字段）
    static func fetchCurrentUserInfoRaw(baseURL: String, sessionId: String) async throws -> String {
        let normalizedBase = BackendChatConfig.normalizeBaseURL(baseURL)
        guard !normalizedBase.isEmpty else { throw AuthError.invalidBaseURL }
        guard let url = URL(string: normalizedBase + "/api/v1/user/info") else {
            throw AuthError.invalidBaseURL
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }

        let raw = String(data: data, encoding: .utf8) ?? ""
#if DEBUG || targetEnvironment(simulator)
        print("👤 user/info raw response: \(raw)")
#endif
        guard (200...299).contains(http.statusCode) else {
            throw AuthError.httpError(http.statusCode, raw)
        }
        return raw
    }
    
    /// 更新当前用户信息（最保守：复用 `/api/v1/user/info`，尝试 PUT）
    /// - Parameter patch: 仅包含需要更新的字段；值可为 `String` 或 `NSNull()`（用于清空）
    static func updateCurrentUserInfo(baseURL: String, sessionId: String, patch: [String: Any]) async throws -> UserInfo {
        let normalizedBase = BackendChatConfig.normalizeBaseURL(baseURL)
        guard !normalizedBase.isEmpty else { throw UpdateUserInfoError.invalidBaseURL }
        guard let url = URL(string: normalizedBase + "/api/v1/user/info") else {
            throw UpdateUserInfoError.invalidBaseURL
        }
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.httpBody = try JSONSerialization.data(withJSONObject: patch, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateUserInfoError.invalidResponse }
        
        let raw = String(data: data, encoding: .utf8) ?? ""
        
#if DEBUG || targetEnvironment(simulator)
        print("🧾 user/info update raw response: \(raw)")
#endif
        
        guard (200...299).contains(http.statusCode) else {
            throw UpdateUserInfoError.httpError(http.statusCode, raw)
        }
        
        // 约定沿用 UserInfoResponse 结构：{ code, message, data }
        do {
            let decoded = try JSONDecoder().decode(UserInfoResponse.self, from: data)
            return decoded.data
        } catch {
            throw UpdateUserInfoError.parseFailed(raw)
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


