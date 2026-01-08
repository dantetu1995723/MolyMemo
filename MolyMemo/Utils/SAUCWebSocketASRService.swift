import Foundation
import AVFoundation
import Compression

/// SAUC（volc.bigasr.sauc.duration）WebSocket 客户端：按官方 demo 的二进制协议封包发送音频并接收结果
struct SAUCWebSocketASRService {
    struct Config {
        var appKey: String
        var accessKey: String
        var wsURL: URL
        var resourceId: String
        var segmentDurationMs: Int = 200
        var modelName: String = "bigmodel"
        var enableITN: Bool = true
        var enablePunc: Bool = true
        var enableDDC: Bool = true
        var showUtterances: Bool = true
        var enableNonstream: Bool = false
    }

    enum ServiceError: LocalizedError {
        case missingConfig(String)
        case invalidURL(String)
        case audioConvertFailed(String)
        case invalidWav(String)
        case websocketClosed
        case serverError(code: Int, message: String?)
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .missingConfig(let key):
                return "缺少配置：\(key)"
            case .invalidURL(let s):
                return "URL 不合法：\(s)"
            case .audioConvertFailed(let msg):
                return "音频转换失败：\(msg)"
            case .invalidWav(let msg):
                return "WAV 文件无效：\(msg)"
            case .websocketClosed:
                return "WebSocket 已关闭"
            case .serverError(let code, let message):
                if let message, !message.isEmpty { return "识别失败：\(code) \(message)" }
                return "识别失败：\(code)"
            case .emptyTranscript:
                return "识别结果为空"
            }
        }
    }

    // MARK: - Protocol constants (与 demo 对齐)

    private enum ProtocolVersion {
        static let v1: UInt8 = 0b0001
    }

    private enum MessageType {
        static let clientFullRequest: UInt8 = 0b0001
        static let clientAudioOnlyRequest: UInt8 = 0b0010
        static let serverFullResponse: UInt8 = 0b1001
        static let serverErrorResponse: UInt8 = 0b1111
    }

    private enum Flags {
        static let posSequence: UInt8 = 0b0001
        static let negSequence: UInt8 = 0b0010
        static let event: UInt8 = 0b0100
    }

    private enum SerializationType {
        static let json: UInt8 = 0b0001
    }

    private enum CompressionType {
        static let gzip: UInt8 = 0b0001
    }

    private let config: Config

    init(config: Config? = nil) throws {
        self.config = try config ?? Self.loadConfig()
    }

    // MARK: - Public

    func transcribeM4AFile(at m4aURL: URL) async throws -> String {
        print("[HoldToTalk] SAUC config: resourceId=\(config.resourceId) ws=\(config.wsURL.absoluteString)")

        // 1) m4a -> wav(16k/16bit/mono) -> 取 PCM data chunk
        let wavURL = try await AudioConversion.convertToWav16kMono(from: m4aURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let wavData = try Data(contentsOf: wavURL)
        let wav = try WavParser.parse(wavData)
        let pcm = wav.pcmData
        let segmentBytes = wav.bytesPerSample * wav.channels * wav.sampleRate * config.segmentDurationMs / 1000
        let segmentSize = max(1, segmentBytes)

        print("[HoldToTalk] SAUC wav: rate=\(wav.sampleRate)Hz bits=\(wav.bitsPerSample) ch=\(wav.channels) pcmBytes=\(pcm.count) seg=\(segmentSize)B")

        // 2) 建立 WS
        var request = URLRequest(url: config.wsURL)
        request.setValue(config.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(config.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(config.appKey, forHTTPHeaderField: "X-Api-App-Key")

        let ws = URLSession.shared.webSocketTask(with: request)
        ws.resume()
        defer { ws.cancel(with: .goingAway, reason: nil) }

        // 3) 并发：接收 + 发送
        let collector = TranscriptCollector()

        async let recvTask: Void = receiveLoop(ws: ws, collector: collector)
        try await sendFullClientRequest(ws: ws, seq: 1)
        try await sendAudioStream(ws: ws, startSeq: 2, pcm: pcm, segmentSize: segmentSize)

        // 等待接收线程结束（最后包或错误）
        _ = try await recvTask

        let final = collector.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else { throw ServiceError.emptyTranscript }
        return final
    }

    // MARK: - Send

    private func sendFullClientRequest(ws: URLSessionWebSocketTask, seq: Int32) async throws {
        var payload: [String: Any] = [
            "user": ["uid": "demo_uid"],
            "audio": [
                "format": "wav",
                "codec": "raw",
                "rate": 16000,
                "bits": 16,
                "channel": 1
            ],
            "request": [
                "model_name": config.modelName,
                "enable_itn": config.enableITN,
                "enable_punc": config.enablePunc,
                "enable_ddc": config.enableDDC,
                "show_utterances": config.showUtterances,
                "enable_nonstream": config.enableNonstream
            ]
        ]
        // 保持结构稳定（Any 编码顺序无所谓；服务端只看字段）
        let jsonBytes = try JSONSerialization.data(withJSONObject: payload, options: [])
        let gz = try gzipCompress(jsonBytes)

        let header = buildHeader(messageType: MessageType.clientFullRequest, flags: Flags.posSequence)
        var frame = Data()
        frame.append(header)
        frame.appendInt32BE(seq)
        frame.appendUInt32BE(UInt32(gz.count))
        frame.append(gz)

        print("[HoldToTalk] SAUC -> send full request seq=\(seq) payload=\(gz.count)B")
        try await ws.send(.data(frame))
    }

    private func sendAudioStream(ws: URLSessionWebSocketTask, startSeq: Int32, pcm: Data, segmentSize: Int) async throws {
        var seq = startSeq
        let segments = split(data: pcm, segmentSize: segmentSize)
        let total = segments.count
        print("[HoldToTalk] SAUC -> send audio segments count=\(total) startSeq=\(startSeq)")

        for (idx, segment) in segments.enumerated() {
            let isLast = (idx == total - 1)
            var flags: UInt8 = Flags.posSequence
            var sendSeq: Int32 = seq
            if isLast {
                flags = Flags.posSequence | Flags.negSequence
                sendSeq = -seq
            }

            let header = buildHeader(messageType: MessageType.clientAudioOnlyRequest, flags: flags)
            let gz = try gzipCompress(segment)

            var frame = Data()
            frame.append(header)
            frame.appendInt32BE(sendSeq)
            frame.appendUInt32BE(UInt32(gz.count))
            frame.append(gz)

            print("[HoldToTalk] SAUC -> send audio seq=\(sendSeq) last=\(isLast) bytes=\(segment.count) gz=\(gz.count)")
            try await ws.send(.data(frame))

            if !isLast {
                seq += 1
                // demo 用 sleep 模拟实时流；这里保持一致，避免服务端限速/拥塞策略
                try await Task.sleep(nanoseconds: UInt64(max(1, config.segmentDurationMs)) * 1_000_000)
            }
        }
    }

    // MARK: - Receive

    private func receiveLoop(ws: URLSessionWebSocketTask, collector: TranscriptCollector) async throws {
        while true {
            let msg = try await ws.receive()
            switch msg {
            case .data(let data):
                let resp = try parseResponseFrame(data)
                if resp.code != 0 {
                    throw ServiceError.serverError(code: resp.code, message: resp.message)
                }
                if let payload = resp.payloadJSON {
                    collector.ingest(payload)
                }
                if resp.isLastPackage {
                    print("[HoldToTalk] SAUC <- last package received")
                    return
                }
            case .string(let s):
                print("[HoldToTalk] SAUC <- unexpected text message: \(s)")
            @unknown default:
                throw ServiceError.websocketClosed
            }
        }
    }

    // MARK: - Response parsing

    private struct ParsedResponse {
        var code: Int = 0
        var isLastPackage: Bool = false
        var payloadSequence: Int32?
        var payloadJSON: Any?
        var message: String?
    }

    private func parseResponseFrame(_ msg: Data) throws -> ParsedResponse {
        guard msg.count >= 4 else { throw ServiceError.invalidWav("response too short") }
        var res = ParsedResponse()

        let headerSizeWords = Int(msg[0] & 0x0f)
        let messageType = msg[1] >> 4
        let flags = msg[1] & 0x0f
        let serializationMethod = msg[2] >> 4
        let compression = msg[2] & 0x0f

        var offset = headerSizeWords * 4
        guard msg.count >= offset else { throw ServiceError.invalidWav("response header_size overflow") }

        // flags: sequence?
        if (flags & Flags.posSequence) != 0 {
            guard msg.count >= offset + 4 else { throw ServiceError.invalidWav("response missing seq") }
            res.payloadSequence = msg.readInt32BE(at: offset)
            offset += 4
        }
        // flags: last?
        if (flags & Flags.negSequence) != 0 {
            res.isLastPackage = true
        }
        // flags: event?
        if (flags & Flags.event) != 0 {
            // demo 里 event 还有 4 字节，但我们当前不使用
            if msg.count >= offset + 4 { offset += 4 }
        }

        // message type: payload size / error code
        if messageType == MessageType.serverFullResponse {
            guard msg.count >= offset + 4 else { return res }
            let payloadSize = Int(msg.readUInt32BE(at: offset))
            offset += 4
            if payloadSize > 0, msg.count >= offset + payloadSize {
                let payloadBytes = msg.subdata(in: offset..<(offset + payloadSize))
                let decoded = try decodePayload(payloadBytes, compression: compression, serialization: serializationMethod)
                res.payloadJSON = decoded
            }
            return res
        }

        if messageType == MessageType.serverErrorResponse {
            guard msg.count >= offset + 8 else { throw ServiceError.serverError(code: -1, message: "server error response too short") }
            let code = Int(msg.readInt32BE(at: offset))
            let payloadSize = Int(msg.readUInt32BE(at: offset + 4))
            offset += 8
            res.code = code
            if payloadSize > 0, msg.count >= offset + payloadSize {
                let payloadBytes = msg.subdata(in: offset..<(offset + payloadSize))
                let decoded = try decodePayload(payloadBytes, compression: compression, serialization: serializationMethod)
                res.payloadJSON = decoded
                if let dict = decoded as? [String: Any] {
                    res.message = dict["message"] as? String ?? dict["msg"] as? String
                }
            }
            return res
        }

        return res
    }

    private func decodePayload(_ payload: Data, compression: UInt8, serialization: UInt8) throws -> Any? {
        var data = payload
        if compression == CompressionType.gzip {
            data = try gzipDecompress(data)
        }
        if serialization == SerializationType.json {
            return try JSONSerialization.jsonObject(with: data, options: [])
        }
        return nil
    }

    // MARK: - Config

    private static func loadConfig() throws -> Config {
        let env = ProcessInfo.processInfo.environment
        let envAppKey = env["SAUC_APP_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envAccessKey = env["SAUC_ACCESS_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envWsURL = env["SAUC_WS_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envResourceId = env["SAUC_RESOURCE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        let plistAppKey = Bundle.main.object(forInfoDictionaryKey: "SAUC_APP_KEY") as? String
        let plistAccessKey = Bundle.main.object(forInfoDictionaryKey: "SAUC_ACCESS_KEY") as? String
        let plistWsURL = Bundle.main.object(forInfoDictionaryKey: "SAUC_WS_URL") as? String
        let plistResourceId = Bundle.main.object(forInfoDictionaryKey: "SAUC_RESOURCE_ID") as? String

        let appKey = (envAppKey?.isEmpty == false ? envAppKey : plistAppKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accessKey = (envAccessKey?.isEmpty == false ? envAccessKey : plistAccessKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wsURLStr = (envWsURL?.isEmpty == false ? envWsURL : plistWsURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        let resourceId = (envResourceId?.isEmpty == false ? envResourceId : plistResourceId)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "volc.bigasr.sauc.duration"

        guard !appKey.isEmpty else { throw ServiceError.missingConfig("SAUC_APP_KEY") }
        guard !accessKey.isEmpty else { throw ServiceError.missingConfig("SAUC_ACCESS_KEY") }
        guard let wsURL = URL(string: wsURLStr) else { throw ServiceError.invalidURL(wsURLStr) }
        guard !resourceId.isEmpty else { throw ServiceError.missingConfig("SAUC_RESOURCE_ID") }

        return Config(appKey: appKey, accessKey: accessKey, wsURL: wsURL, resourceId: resourceId)
    }

    // MARK: - Helpers (frame/build)

    private func buildHeader(messageType: UInt8, flags: UInt8) -> Data {
        // 4 bytes header:
        // byte0: version(4bits) | header_size(4bits=1)
        // byte1: message_type(4) | flags(4)
        // byte2: serialization(4) | compression(4)
        // byte3: reserved
        return Data([
            (ProtocolVersion.v1 << 4) | 0b0001,
            (messageType << 4) | (flags & 0x0f),
            (SerializationType.json << 4) | (CompressionType.gzip & 0x0f),
            0x00
        ])
    }

    private func split(data: Data, segmentSize: Int) -> [Data] {
        guard segmentSize > 0 else { return [] }
        if data.isEmpty { return [] }
        var out: [Data] = []
        var i = 0
        while i < data.count {
            let end = min(i + segmentSize, data.count)
            out.append(data.subdata(in: i..<end))
            i = end
        }
        return out
    }

    // MARK: - gzip (严格 gzip：与 demo 的 gzip.compress / gzip.decompress 对齐)

    private func gzipCompress(_ data: Data) throws -> Data {
        let src = [UInt8](data)
        // gzip 最小头+尾；这里保守预分配
        var dst = [UInt8](repeating: 0, count: max(256, src.count + 64 * 1024))
        let size = compression_encode_buffer(&dst, dst.count, src, src.count, nil, COMPRESSION_ZLIB)
        guard size > 0 else { throw ServiceError.audioConvertFailed("compress failed") }
        // 用 zlib 产物 + gzip 包头/包尾（RFC1952）
        // 说明：Compression 框架不直接输出 gzip 容器，我们手动包一层 gzip header + zlib deflate + trailer(CRC32, ISIZE)。
        // header: 1f 8b 08 00 00 00 00 00 00 ff
        let header: [UInt8] = [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]
        let deflated = Array(dst.prefix(size))
        let crc = CRC32.compute(src)
        let isize = UInt32(src.count & 0xffff_ffff)
        var trailer = [UInt8]()
        trailer.reserveCapacity(8)
        trailer.append(contentsOf: withUnsafeBytes(of: crc.littleEndian, Array.init))
        trailer.append(contentsOf: withUnsafeBytes(of: isize.littleEndian, Array.init))
        return Data(header + deflated + trailer)
    }

    private func gzipDecompress(_ data: Data) throws -> Data {
        // 解析 gzip，取 deflate 主体（跳过 header + trailer），再用 zlib 解
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { throw ServiceError.audioConvertFailed("gzip too short") }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b else { throw ServiceError.audioConvertFailed("not gzip") }
        let flg = bytes[3]
        var idx = 10 // base header
        // extra
        if (flg & 0x04) != 0 {
            guard idx + 2 <= bytes.count else { throw ServiceError.audioConvertFailed("gzip extra overflow") }
            let xlen = Int(UInt16(bytes[idx]) | (UInt16(bytes[idx + 1]) << 8))
            idx += 2 + xlen
        }
        // name
        if (flg & 0x08) != 0 {
            while idx < bytes.count, bytes[idx] != 0 { idx += 1 }
            idx += 1
        }
        // comment
        if (flg & 0x10) != 0 {
            while idx < bytes.count, bytes[idx] != 0 { idx += 1 }
            idx += 1
        }
        // hcrc
        if (flg & 0x02) != 0 { idx += 2 }
        guard idx < bytes.count - 8 else { throw ServiceError.audioConvertFailed("gzip body overflow") }
        let deflated = Array(bytes[idx..<(bytes.count - 8)])

        // zlib decode buffer（与 encode 对应）
        var cap = max(1024, deflated.count * 10)
        while cap < 50 * 1024 * 1024 {
            var out = [UInt8](repeating: 0, count: cap)
            let n = compression_decode_buffer(&out, out.count, deflated, deflated.count, nil, COMPRESSION_ZLIB)
            if n > 0 {
                return Data(out.prefix(n))
            }
            cap *= 2
        }
        throw ServiceError.audioConvertFailed("decompress failed")
    }
}

// MARK: - WAV parsing (只取 data chunk 的 PCM)

private enum WavParser {
    struct ParsedWav {
        var channels: Int
        var sampleRate: Int
        var bitsPerSample: Int
        var bytesPerSample: Int
        var pcmData: Data
    }

    static func parse(_ data: Data) throws -> ParsedWav {
        guard data.count >= 44 else { throw SAUCWebSocketASRService.ServiceError.invalidWav("too short") }
        func s(_ r: Range<Int>) -> String { String(data: data.subdata(in: r), encoding: .ascii) ?? "" }
        guard s(0..<4) == "RIFF" else { throw SAUCWebSocketASRService.ServiceError.invalidWav("not RIFF") }
        guard s(8..<12) == "WAVE" else { throw SAUCWebSocketASRService.ServiceError.invalidWav("not WAVE") }

        let numChannels = Int(data.readUInt16LE(at: 22))
        let sampleRate = Int(data.readUInt32LE(at: 24))
        let bitsPerSample = Int(data.readUInt16LE(at: 34))
        let bytesPerSample = max(1, bitsPerSample / 8)

        var pos = 12
        while pos + 8 <= data.count {
            let chunkId = s(pos..<(pos + 4))
            let chunkSize = Int(data.readUInt32LE(at: pos + 4))
            let chunkDataStart = pos + 8
            let chunkDataEnd = min(chunkDataStart + chunkSize, data.count)
            if chunkId == "data" {
                guard chunkDataEnd > chunkDataStart else { throw SAUCWebSocketASRService.ServiceError.invalidWav("empty data chunk") }
                let pcm = data.subdata(in: chunkDataStart..<chunkDataEnd)
                return ParsedWav(
                    channels: numChannels,
                    sampleRate: sampleRate,
                    bitsPerSample: bitsPerSample,
                    bytesPerSample: bytesPerSample,
                    pcmData: pcm
                )
            }
            pos = chunkDataStart + chunkSize
        }
        throw SAUCWebSocketASRService.ServiceError.invalidWav("no data chunk")
    }
}

// MARK: - m4a -> wav(16k/mono/s16) conversion

private enum AudioConversion {
    static func convertToWav16kMono(from m4aURL: URL) async throws -> URL {
        // AVAudioFile 读 m4a（AAC），用 AVAudioConverter 转成 16k/mono/s16，然后写 wav 临时文件
        let input = try AVAudioFile(forReading: m4aURL)
        let inFormat = input.processingFormat

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw SAUCWebSocketASRService.ServiceError.audioConvertFailed("cannot create out format")
        }

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw SAUCWebSocketASRService.ServiceError.audioConvertFailed("cannot create converter")
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hold_to_talk_\(UUID().uuidString).wav")
        try? FileManager.default.removeItem(at: outURL)
        let output = try AVAudioFile(forWriting: outURL, settings: outFormat.settings)

        let inFrameCapacity: AVAudioFrameCount = 4096
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inFrameCapacity) else {
            throw SAUCWebSocketASRService.ServiceError.audioConvertFailed("cannot alloc in buffer")
        }

        let outFrameCapacity: AVAudioFrameCount = 4096
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrameCapacity) else {
            throw SAUCWebSocketASRService.ServiceError.audioConvertFailed("cannot alloc out buffer")
        }

        while true {
            try input.read(into: inBuffer, frameCount: inFrameCapacity)
            if inBuffer.frameLength == 0 { break }

            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inBuffer
            }
            if let error { throw error }
            guard status != .error else { throw SAUCWebSocketASRService.ServiceError.audioConvertFailed("convert status error") }

            try output.write(from: outBuffer)
        }

        return outURL
    }
}

// MARK: - Transcript collector (从 payload JSON 尽量抽出 text)

private final class TranscriptCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var finalText: String = ""

    func ingest(_ json: Any) {
        if let text = extractTranscript(from: json)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            lock.lock()
            // SAUC 会持续返回增量/分句；我们用“最新非空”覆盖即可
            finalText = text
            lock.unlock()
            print("[HoldToTalk] SAUC <- transcript update: \(text)")
        }
    }

    private func extractTranscript(from json: Any) -> String? {
        if let dict = json as? [String: Any] {
            if let result = dict["result"] as? [String: Any] {
                if let t = result["text"] as? String { return t }
                if let t = result["transcript"] as? String { return t }
            }
            if let t = dict["text"] as? String { return t }
            if let t = dict["transcript"] as? String { return t }
            if let utterances = dict["utterances"] as? [[String: Any]] {
                let parts = utterances.compactMap { $0["text"] as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !parts.isEmpty { return parts.joined(separator: "") }
            }
            for (_, v) in dict {
                if let found = extractTranscript(from: v) { return found }
            }
        } else if let arr = json as? [Any] {
            for v in arr {
                if let found = extractTranscript(from: v) { return found }
            }
        }
        return nil
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func appendInt32BE(_ v: Int32) {
        var x = v.bigEndian
        append(UnsafeBufferPointer(start: &x, count: 1))
    }
    mutating func appendUInt32BE(_ v: UInt32) {
        var x = v.bigEndian
        append(UnsafeBufferPointer(start: &x, count: 1))
    }
    func readUInt16LE(at i: Int) -> UInt16 {
        let b0 = UInt16(self[i])
        let b1 = UInt16(self[i + 1]) << 8
        return b0 | b1
    }
    func readUInt32LE(at i: Int) -> UInt32 {
        let b0 = UInt32(self[i])
        let b1 = UInt32(self[i + 1]) << 8
        let b2 = UInt32(self[i + 2]) << 16
        let b3 = UInt32(self[i + 3]) << 24
        return b0 | b1 | b2 | b3
    }
    func readUInt32BE(at i: Int) -> UInt32 {
        return (UInt32(self[i]) << 24) | (UInt32(self[i + 1]) << 16) | (UInt32(self[i + 2]) << 8) | UInt32(self[i + 3])
    }
    func readInt32BE(at i: Int) -> Int32 {
        let u = readUInt32BE(at: i)
        return Int32(bitPattern: u)
    }
}

// MARK: - CRC32 (gzip trailer)

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func compute(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            let idx = Int((crc ^ UInt32(b)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}



