import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 后端飞书授权相关接口（绑定/登录）
enum FeishuAuthService {
    enum VerifyError: LocalizedError {
        case invalidBaseURL
        case invalidResponse
        case httpError(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "后端 Base URL 为空或不合法，请先在「聊天后端」里配置"
            case .invalidResponse:
                return "飞书授权失败：服务端返回异常"
            case let .httpError(code, message):
                if let message, !message.isEmpty { return "飞书授权失败：\(message)（HTTP \(code)）" }
                return "飞书授权失败（HTTP \(code)）"
            }
        }
    }

    /// 验证飞书 OAuth 回调 code，并由后端完成账号绑定/登录。
    /// - Parameter externalUserId: 文档里的 `user_id`（可选）。不传则由后端使用当前登录用户。
    static func verifyLarkAuthCode(
        baseURL: String,
        sessionId: String,
        code: String,
        externalUserId: String? = nil
    ) async throws -> String {
        let normalizedBase = BackendChatConfig.normalizeBaseURL(baseURL)
        guard !normalizedBase.isEmpty else { throw VerifyError.invalidBaseURL }
        guard let url = URL(string: normalizedBase + "/api/v1/feishu/verify_lark_auth_code") else {
            throw VerifyError.invalidBaseURL
        }

        var body: [String: Any] = ["code": code]
        if let externalUserId, !externalUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["user_id"] = externalUserId as Any
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VerifyError.invalidResponse }

        let raw = String(data: data, encoding: .utf8) ?? ""
#if DEBUG || targetEnvironment(simulator)
        print("🔐 feishu/verify_lark_auth_code raw response: \(raw)")
#endif

        guard (200...299).contains(http.statusCode) else {
            throw VerifyError.httpError(http.statusCode, raw)
        }
        return raw
    }
}

