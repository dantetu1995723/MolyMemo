import Foundation

/// 日程语音更新（流式）：WebSocket `/api/v1/schedule/voice-update?session_id=...&schedule_id=...`
/// - 客户端：流式发送 WAV（16kHz/16bit/mono）
/// - 服务端：推送 asr_result / processing / update_result / cancelled / error
enum ScheduleVoiceUpdateService {
    enum ServiceError: LocalizedError {
        case invalidScheduleId
        case invalidBaseURL
        case missingSessionId
        case invalidWebSocketURL
        case invalidMessageShape
        case serverError(code: Int?, message: String)
        case parseScheduleFailed

        var errorDescription: String? {
            switch self {
            case .invalidScheduleId: return "无效的日程 id"
            case .invalidBaseURL: return "无效的后端地址（baseURL）"
            case .missingSessionId: return "缺少登录态（X-Session-Id）"
            case .invalidWebSocketURL: return "无效的 WebSocket 地址"
            case .invalidMessageShape: return "服务端消息格式不正确"
            case let .serverError(code, message):
                if let code { return "服务端错误（\(code)）：\(message)" }
                return "服务端错误：\(message)"
            case .parseScheduleFailed: return "解析更新后的日程失败"
            }
        }
    }

    enum Event {
        case asrResult(text: String, isFinal: Bool)
        case processing(message: String?)
        case updateResult(event: ScheduleEvent, message: String?)
        case cancelled(message: String?)
        case error(code: Int?, message: String)
    }

    final class Session {
        private let urlSession: URLSession
        private let task: URLSessionWebSocketTask
        private let keepLocalId: UUID?
        private let debugTag: String

        init(request: URLRequest, keepLocalId: UUID?) {
            self.urlSession = URLSession(configuration: .default)
            self.task = urlSession.webSocketTask(with: request)
            self.keepLocalId = keepLocalId
            self.debugTag = request.url?.absoluteString ?? "(nil url)"
        }

        func start() {
            task.resume()
            debugLogOnce("[ScheduleVoiceUpdate] ✅ WS connected -> \(debugTag)")
        }

        func close() async {
            task.cancel(with: .normalClosure, reason: nil)
            urlSession.invalidateAndCancel()
        }

        func sendWavHeaderOnce(sampleRate: Int = 16_000, channels: Int = 1, bitsPerSample: Int = 16) async throws {
            let header = Self.wavHeader(sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample, dataSize: 0)
            try await sendBinary(header)
        }

        func sendPCMChunk(_ pcmBytes: Data) async throws {
            guard !pcmBytes.isEmpty else { return }
            try await sendBinary(pcmBytes)
        }

        func sendAudioRecordDone() async throws {
            let payload: [String: Any] = ["action": "audio_record_done"]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let text = String(data: data, encoding: .utf8) ?? #"{"action":"audio_record_done"}"#
            try await sendText(text)
            debugLogOnce("[ScheduleVoiceUpdate] 📩 client -> audio_record_done")
        }

        func sendCancel() async throws {
            let payload: [String: Any] = ["action": "cancel"]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let text = String(data: data, encoding: .utf8) ?? #"{"action":"cancel"}"#
            try await sendText(text)
            debugLogOnce("[ScheduleVoiceUpdate] 📩 client -> cancel")
        }

        func receiveEvent() async throws -> Event {
            let msg = try await task.receive()
            switch msg {
            case let .string(text):
                return try Self.parseServerEvent(text: text, keepLocalId: keepLocalId)
            case let .data(data):
                // 兼容：某些后端可能用 data 下发 JSON
                if let text = String(data: data, encoding: .utf8) {
                    return try Self.parseServerEvent(text: text, keepLocalId: keepLocalId)
                }
                throw ServiceError.invalidMessageShape
            @unknown default:
                throw ServiceError.invalidMessageShape
            }
        }

        // MARK: - Private

        private func sendBinary(_ data: Data) async throws {
            try await task.send(.data(data))
        }

        private func sendText(_ text: String) async throws {
            try await task.send(.string(text))
        }

        private static func parseServerEvent(text: String, keepLocalId: UUID?) throws -> Event {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { throw ServiceError.invalidMessageShape }

            let data = raw.data(using: .utf8) ?? Data()
            let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dict = any as? [String: Any] else { throw ServiceError.invalidMessageShape }

            let type = (dict["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch type {
            case "asr_result":
                let text = (dict["text"] as? String) ?? ""
                let isFinal = (dict["is_final"] as? Bool) ?? false
                return .asrResult(text: text, isFinal: isFinal)
            case "processing":
                let msg = dict["message"] as? String
                return .processing(message: msg)
            case "update_result":
                debugLogUpdateResultOnce(rawJSONText: raw)
                let msg = dict["message"] as? String
                let scheduleAny = dict["schedule"]
                guard let scheduleDict = scheduleAny as? [String: Any] else {
                    throw ServiceError.parseScheduleFailed
                }
                guard let ev = ScheduleService.parseScheduleEventFromServerDict(scheduleDict, keepLocalId: keepLocalId) else {
                    throw ServiceError.parseScheduleFailed
                }
                return .updateResult(event: ev, message: msg)
            case "cancelled":
                debugLogOnce("[ScheduleVoiceUpdate] ⚠️ server -> cancelled: \(raw)")
                let msg = dict["message"] as? String
                return .cancelled(message: msg)
            case "error":
                debugLogOnce("[ScheduleVoiceUpdate] ❌ server -> error: \(raw)")
                let code: Int? = {
                    if let c = dict["code"] as? Int { return c }
                    if let c = dict["code"] as? Double { return Int(c) }
                    if let s = dict["code"] as? String, let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
                    return nil
                }()
                let msg = (dict["message"] as? String) ?? "未知错误"
                return .error(code: code, message: msg)
            default:
                throw ServiceError.invalidMessageShape
            }
        }

        private static func wavHeader(sampleRate: Int, channels: Int, bitsPerSample: Int, dataSize: Int) -> Data {
            let byteRate = sampleRate * channels * bitsPerSample / 8
            let blockAlign = channels * bitsPerSample / 8
            let chunkSize = 36 + dataSize

            var data = Data()
            data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
            data.append(UInt32(chunkSize).littleEndianData)
            data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
            data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
            data.append(UInt32(16).littleEndianData) // PCM header size
            data.append(UInt16(1).littleEndianData) // AudioFormat = PCM
            data.append(UInt16(channels).littleEndianData)
            data.append(UInt32(sampleRate).littleEndianData)
            data.append(UInt32(byteRate).littleEndianData)
            data.append(UInt16(blockAlign).littleEndianData)
            data.append(UInt16(bitsPerSample).littleEndianData)
            data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
            data.append(UInt32(dataSize).littleEndianData)
            return data
        }
    }

    static func makeSession(scheduleId: String, keepLocalId: UUID?) throws -> Session {
        let sid = scheduleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { throw ServiceError.invalidScheduleId }

        let base = try ScheduleService.resolvedBaseURLForNetworking()
        guard var comps = URLComponents(string: base + "/api/v1/schedule/voice-update") else {
            throw ServiceError.invalidBaseURL
        }

        let sessionId = try ScheduleService.currentSessionIdForNetworking()
        comps.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "schedule_id", value: sid)
        ]

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
        try ScheduleService.applyCommonHeadersForNetworking(to: &request)

        return Session(request: request, keepLocalId: keepLocalId)
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<Self>.size)
    }
}

// MARK: - Debug log (avoid repeated printing)

private enum ScheduleVoiceUpdateDebugLog {
    static let key = "backend_chat_debug_schedule_voice_update_log"
    static var enabled: Bool {
#if DEBUG
        if UserDefaults.standard.object(forKey: key) == nil {
            // 开发期默认开启（只在 Debug 生效），便于你联调排查
            UserDefaults.standard.set(true, forKey: key)
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
#else
        return false
#endif
    }

    private static var didPrintOnceKeys = Set<String>()
    private static let lock = NSLock()

    static func printOnce(_ key: String, _ message: String) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !didPrintOnceKeys.contains(key) else { return }
        didPrintOnceKeys.insert(key)
        print(message)
    }

    static func printLong(_ message: String, chunkSize: Int = 900) {
        guard enabled else { return }
        guard chunkSize > 0 else { return }
        if message.isEmpty { return }
        let chars = Array(message)
        var i = 0
        while i < chars.count {
            let end = min(i + chunkSize, chars.count)
            print(String(chars[i..<end]))
            i = end
        }
    }
}

private func debugLogOnce(_ message: String) {
    // 按消息内容去重，避免同一条被多处重复触发
    ScheduleVoiceUpdateDebugLog.printOnce(message, message)
}

private func debugLogUpdateResultOnce(rawJSONText: String) {
    let header = "[ScheduleVoiceUpdate] ✅ server -> update_result (raw json):"
    ScheduleVoiceUpdateDebugLog.printOnce(header, header)
    ScheduleVoiceUpdateDebugLog.printLong(rawJSONText)
}

