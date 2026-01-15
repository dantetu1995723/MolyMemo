import Foundation
import UIKit

/// 聊天室语音输入（流式）：WebSocket `/api/v1/chat/voice?session_id=...&contact_id=...`
/// - 客户端：流式发送 PCM（16kHz/16bit/mono，binary）
/// - 服务端：推送 asr_result / asr_complete / task_id / markdown/tool/card / done / error / cancelled / stopped
enum ChatVoiceInputService {
    enum ServiceError: LocalizedError {
        case invalidBaseURL
        case missingSessionId
        case invalidWebSocketURL
        case invalidMessageShape
        case serverError(code: Int?, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "无效的后端地址（baseURL）"
            case .missingSessionId: return "缺少登录态（session_id）"
            case .invalidWebSocketURL: return "无效的 WebSocket 地址"
            case .invalidMessageShape: return "服务端消息格式不正确"
            case let .serverError(code, message):
                if let code { return "服务端错误（\(code)）：\(message)" }
                return "服务端错误：\(message)"
            }
        }
    }

    enum Event {
        case asrResult(text: String, isFinal: Bool)
        case asrComplete(text: String, message: String?)
        case taskId(String)
        case done(message: String?)
        case cancelled(message: String?)
        case stopped(message: String?)
        case error(code: Int?, message: String)
        /// 其它消息（例如 assistant 的 markdown/tool/card），客户端可按需接管。
        case other(payload: [String: Any])
    }

    final class Session {
        private let urlSession: URLSession
        private let task: URLSessionWebSocketTask
        private let debugTag: String

        init(request: URLRequest) {
            self.urlSession = URLSession(configuration: .default)
            self.task = urlSession.webSocketTask(with: request)
            self.debugTag = request.url?.absoluteString ?? "(nil url)"
        }

        func start() {
            task.resume()
            debugLog("[ChatVoice] ✅ WS connected -> \(debugTag)")
        }

        func close() async {
            debugLog("[ChatVoice] 🔌 WS closing...")
            task.cancel(with: .normalClosure, reason: nil)
            urlSession.invalidateAndCancel()
        }

        func sendPCMChunk(_ pcmBytes: Data) async throws {
            guard !pcmBytes.isEmpty else { return }
            debugLog("[ChatVoice] 📤 client -> PCM chunk (\(pcmBytes.count) bytes)")
            try await task.send(.data(pcmBytes))
        }

        /// 正常结束录音：通知后端“音频发送完毕”，并可选携带客户端侧缓存的 asr_result（用于后端兜底解析）。
        func sendAudioRecordDone(asrText: String?, isFinal: Bool?) async throws {
            var payload: [String: Any] = ["action": "audio_record_done"]

            let t = (asrText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                payload["asr_result"] = [
                    "text": t,
                    "is_final": isFinal ?? true
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let text = String(data: data, encoding: .utf8) ?? #"{"action":"audio_record_done"}"#
            debugLog("[ChatVoice] 📤 client -> \(text)")
            try await task.send(.string(text))
        }

        func sendCancel() async throws {
            let payload: [String: Any] = ["action": "cancel"]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let text = String(data: data, encoding: .utf8) ?? #"{"action":"cancel"}"#
            debugLog("[ChatVoice] 📤 client -> \(text)")
            try await task.send(.string(text))
        }

        func receiveEvent() async throws -> Event {
            let msg = try await task.receive()
            switch msg {
            case let .string(text):
                debugLog("[ChatVoice] 📥 RAW server message (string): \(text)")
                return try Self.parseServerEvent(text: text)
            case let .data(data):
                if let text = String(data: data, encoding: .utf8) {
                    debugLog("[ChatVoice] 📥 RAW server message (data->string): \(text)")
                    return try Self.parseServerEvent(text: text)
                }
                debugLog("[ChatVoice] ❌ RAW server message (binary, \(data.count) bytes) - cannot decode as UTF8")
                throw ServiceError.invalidMessageShape
            @unknown default:
                debugLog("[ChatVoice] ❌ RAW server message (unknown type)")
                throw ServiceError.invalidMessageShape
            }
        }

        private static func parseServerEvent(text: String) throws -> Event {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { throw ServiceError.invalidMessageShape }

            guard let data = raw.data(using: .utf8) else { throw ServiceError.invalidMessageShape }
            let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dict = any as? [String: Any] else { throw ServiceError.invalidMessageShape }

            // 1) 优先按 `type` 分发（asr_result/asr_complete/task_id/done/error/...）
            if let typeAny = dict["type"] as? String {
                let type = typeAny.trimmingCharacters(in: .whitespacesAndNewlines)
                switch type {
                case "asr_result":
                    let text = (dict["text"] as? String) ?? ""
                    let isFinal = (dict["is_final"] as? Bool) ?? false
                    debugLog("[ChatVoice] 📥 server -> asr_result: \"\(text)\" (isFinal=\(isFinal))")
                    return .asrResult(text: text, isFinal: isFinal)

                case "asr_complete":
                    let text = (dict["text"] as? String) ?? ""
                    let msg = dict["message"] as? String
                    debugLog("[ChatVoice] 📥 server -> asr_complete: \"\(text)\"")
                    return .asrComplete(text: text, message: msg)

                case "task_id":
                    let tid = (dict["task_id"] as? String) ?? ""
                    if !tid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        debugLog("[ChatVoice] 📥 server -> task_id: \(tid)")
                        return .taskId(tid)
                    }
                    return .other(payload: dict)

                case "done":
                    let msg = dict["message"] as? String
                    debugLog("[ChatVoice] ✅ server -> done: \(msg ?? "(nil)")")
                    return .done(message: msg)

                case "cancelled":
                    let msg = dict["message"] as? String
                    debugLog("[ChatVoice] ⚠️ server -> cancelled: \(msg ?? "(nil)")")
                    return .cancelled(message: msg)

                case "stopped":
                    let msg = dict["message"] as? String
                    debugLog("[ChatVoice] ⚠️ server -> stopped: \(msg ?? "(nil)")")
                    return .stopped(message: msg)

                case "error":
                    let code: Int? = {
                        if let c = dict["code"] as? Int { return c }
                        if let c = dict["code"] as? Double { return Int(c) }
                        if let s = dict["code"] as? String, let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
                        return nil
                    }()
                    let msg = (dict["message"] as? String) ?? "未知错误"
                    debugLog("[ChatVoice] ❌ server -> error: \(raw)")
                    return .error(code: code, message: msg)

                default:
                    // 例如后端可能发 processing / 其它中间态
                    return .other(payload: dict)
                }
            }

            // 2) assistant 的流式消息通常是：{"role":"assistant","type":"markdown|tool|card",...}
            return .other(payload: dict)
        }
    }

    static func makeSession(contactId: String? = nil) throws -> Session {
        let base = BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw ServiceError.invalidBaseURL }

        let sessionId = (currentSessionId() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty else { throw ServiceError.missingSessionId }

        guard var comps = URLComponents(string: BackendChatConfig.normalizeBaseURL(base) + "/api/v1/chat/voice") else {
            throw ServiceError.invalidBaseURL
        }

        var items: [URLQueryItem] = [
            URLQueryItem(name: "session_id", value: sessionId)
        ]
        if let cid = contactId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty {
            items.append(URLQueryItem(name: "contact_id", value: cid))
        }
        comps.queryItems = items

        guard let httpURL = comps.url else { throw ServiceError.invalidWebSocketURL }
        guard var wsComps = URLComponents(url: httpURL, resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidWebSocketURL
        }
        let scheme = (wsComps.scheme ?? "").lowercased()
        if scheme == "https" { wsComps.scheme = "wss" }
        else if scheme == "http" { wsComps.scheme = "ws" }

        guard let wsURL = wsComps.url else { throw ServiceError.invalidWebSocketURL }

        var request = URLRequest(url: wsURL, timeoutInterval: 30)
        request.httpMethod = "GET"
        applyDefaultHeaders(to: &request, sessionId: sessionId)
        return Session(request: request)
    }

    // MARK: - Headers / Session

    private enum AuthKeys {
        static let sessionId = "yuanyuan_auth_session_id"
    }

    private static func currentSessionId() -> String? {
        let fromConfig = BackendChatConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromConfig.isEmpty { return fromConfig }
        let fromDefaults = (UserDefaults.standard.string(forKey: AuthKeys.sessionId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fromDefaults.isEmpty ? nil : fromDefaults
    }

    private static func applyDefaultHeaders(to request: inout URLRequest, sessionId: String) {
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-App-Id")
        request.setValue(appVersionString(), forHTTPHeaderField: "X-App-Version")
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-OS-Type")
        request.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-OS-Version")

        // 地理信息：当前工程未接入定位，先留空
        request.setValue("", forHTTPHeaderField: "X-Longitude")
        request.setValue("", forHTTPHeaderField: "X-Latitude")
        request.setValue("", forHTTPHeaderField: "X-Address")
        request.setValue("", forHTTPHeaderField: "X-City")
        request.setValue("", forHTTPHeaderField: "X-Country")
    }

    private static func appVersionString() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if short.isEmpty { return build }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }
}

// MARK: - Debug log

private enum ChatVoiceDebugLog {
    static let key = "backend_chat_debug_chat_voice_log"
    static var enabled: Bool {
#if DEBUG
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(true, forKey: key)
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
#elseif targetEnvironment(simulator)
        return true
#else
        return false
#endif
    }

    static func log(_ message: String) {
        guard enabled else { return }
        let ts = String(format: "%.3f", Date().timeIntervalSince1970)
        print("[\(ts)] \(message)")
    }
}

private func debugLog(_ message: String) {
    ChatVoiceDebugLog.log(message)
}

