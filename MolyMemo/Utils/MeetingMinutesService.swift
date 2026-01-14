import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 会议纪要后端服务 - 调用后端API生成会议纪要
class MeetingMinutesService {
    
    /// 后端服务器地址
    /// 优先使用「聊天后端」配置的 baseURL（与登录一致），否则回退到默认值
    private static let fallbackBaseURL = BackendChatConfig.defaultBaseURL
    
    /// API 端点
    private static let generateEndpoint = "/api/v1/meeting-minutes/generate"
    private static let listEndpoint = "/api/v1/meeting-minutes"
    private static let deleteSuffix = "/delete"

    // MARK: - Auth / Headers

    private enum AuthKeys {
        static let sessionId = "yuanyuan_auth_session_id"
    }

    private static func resolvedBaseURL() throws -> String {
        let candidate = BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = candidate.isEmpty ? fallbackBaseURL : candidate
        return BackendChatConfig.normalizeBaseURL(base)
    }

    private static func currentSessionId() -> String? {
        // 1) 与登录后写入保持一致：BackendChatConfig.apiKey
        let fromConfig = BackendChatConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromConfig.isEmpty { return fromConfig }
        // 2) 兜底：AuthStore 写入的 UserDefaults
        let fromDefaults = (UserDefaults.standard.string(forKey: AuthKeys.sessionId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fromDefaults.isEmpty ? nil : fromDefaults
    }

    #if DEBUG
    private static var didPrintSessionHeaderOnce: Bool = false
    #endif

    private static func applyCommonHeaders(to request: inout URLRequest) throws {
        guard let sessionId = currentSessionId(), !sessionId.isEmpty else {
            throw MeetingMinutesError.serverError("缺少登录态（X-Session-Id）")
        }

        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")

        // 其余 header（后端若不要求，可忽略；这里尽量补齐，便于后端排查）
        #if canImport(UIKit)
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        let osVersion = UIDevice.current.systemVersion
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let appId = Bundle.main.bundleIdentifier ?? ""
        request.setValue(appId, forHTTPHeaderField: "X-App-Id")
        request.setValue(appVersion.isEmpty ? "" : "\(appVersion) (\(build))", forHTTPHeaderField: "X-App-Version")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-OS-Type")
        request.setValue(osVersion, forHTTPHeaderField: "X-OS-Version")

        // 地理信息：当前工程未接入定位，先留空（与聊天请求保持一致）
        request.setValue("", forHTTPHeaderField: "X-Longitude")
        request.setValue("", forHTTPHeaderField: "X-Latitude")
        request.setValue("", forHTTPHeaderField: "X-Address")
        request.setValue("", forHTTPHeaderField: "X-City")
        request.setValue("", forHTTPHeaderField: "X-Country")
        #endif

        #if DEBUG
        if !didPrintSessionHeaderOnce {
            didPrintSessionHeaderOnce = true
            let masked = sessionId.count <= 8 ? "***" : "\(sessionId.prefix(4))...\(sessionId.suffix(4))"
            AppGroupDebugLog.append("[MeetingMinutesService] sessionId=\(masked)")
        }
        #endif
    }
    
    /// 会议纪要生成结果
    struct MeetingMinutesResult: Codable {
        let success: Bool?
        let summary: String?
        let transcriptions: [TranscriptionItem]?
        let error: String?
        let message: String?
        
        struct TranscriptionItem: Codable {
            let speaker: String?
            let time: String?
            let content: String?
        }
    }

    // 后端常见通用包裹：{ code, message, success, data, ... }
    private struct APIEnvelope<T: Decodable>: Decodable {
        let code: Int?
        let message: String?
        let success: Bool?
        let data: T?
        let error: String?
        let total: Int?
        let page: Int?
        let pageSize: Int?

        enum CodingKeys: String, CodingKey {
            case code, message, success, data, error, total, page
            case pageSize = "page_size"
        }
    }

    /// 列表分页包裹：后端可能返回 { data: { items: [...], page, page_size, total } }
    private struct PagedList<T: Decodable>: Decodable {
        let items: [T]?
        let list: [T]?
        let rows: [T]?
        let records: [T]?
        let total: Int?
        let page: Int?
        let pageSize: Int?

        enum CodingKeys: String, CodingKey {
            case items, list, rows, records, total, page
            case pageSize = "page_size"
        }

        var resolvedItems: [T] {
            items ?? list ?? rows ?? records ?? []
        }
    }

    private struct EmptyData: Decodable {}
    private struct SimpleResponse: Decodable {
        let success: Bool?
        let code: Int?
        let message: String?
        let error: String?
    }

    // POST /generate 返回的异步任务信息（你截图里的结构）
    private struct GenerateJob: Decodable {
        let id: String
        let status: String?
        let audioUrl: String?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, status
            case audioUrl = "audio_url"
            case createdAt = "created_at"
        }
    }

    struct GeneratedMinutes {
        let id: String?
        let title: String?
        let date: Date?
        let summary: String
        let transcriptions: [MeetingTranscription]?
        /// 后端返回的录音时长（秒），对应 audio_duration
        let audioDuration: Double?
        /// 后端返回的录音文件 URL（audio_url）
        let audioUrl: String?
    }
    
    /// 会议纪要列表项
    struct MeetingMinutesItem: Codable, Identifiable {
        let id: String?
        let title: String?
        /// 兼容不同后端字段：summary / meeting_summary
        let summary: String?
        let meetingSummary: String?
        /// 兼容不同后端字段：date / meeting_date
        let date: String?
        let meetingDate: String?
        /// 旧字段（不再使用，仅用于排查后端返回）
        let duration: Double?
        let audioDuration: Double?
        let audioPath: String?
        /// 兼容不同后端字段：transcriptions / meeting_details
        let transcriptions: [MeetingMinutesResult.TranscriptionItem]?
        let meetingDetails: [MeetingDetail]?
        let status: String?
        let audioUrl: String?
        let createdAt: String?
        let updatedAt: String?
        
        // 注意：按需求“不搞回退机制”，业务上只使用 audio_duration
        
        struct MeetingDetail: Codable {
            let speakerId: String?
            let speakerName: String?
            let text: String?
            let startTime: Double?
            let endTime: Double?

            enum CodingKeys: String, CodingKey {
                case speakerId = "speaker_id"
                case speakerName = "speaker_name"
                case text
                case startTime = "start_time"
                case endTime = "end_time"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case summary
            case meetingSummary = "meeting_summary"
            case date
            case meetingDate = "meeting_date"
            case duration
            case audioDuration = "audio_duration"
            case audioPath = "audio_path"
            case transcriptions
            case meetingDetails = "meeting_details"
            case status
            case audioUrl = "audio_url"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }
    
    /// 会议纪要列表响应
    struct MeetingMinutesListResponse: Codable {
        let success: Bool?
        let data: [MeetingMinutesItem]?
        let total: Int?
        let page: Int?
        let pageSize: Int?
        let error: String?
        let message: String?
        
        enum CodingKeys: String, CodingKey {
            case success
            case data
            case total
            case page
            case pageSize = "page_size"
            case error
            case message
        }
    }

    /// 会议纪要列表响应（v2：data 为对象，内部含 items/分页字段）
    private struct MeetingMinutesListResponseV2: Decodable {
        let success: Bool?
        let data: PagedList<MeetingMinutesItem>?
        let error: String?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case success, data, error, message
        }
    }
    
    // MARK: - 获取会议纪要列表
    
    /// 获取会议纪要列表
    /// - Parameters:
    ///   - page: 页码（可选）
    ///   - pageSize: 每页数量（可选）
    ///   - search: 搜索关键词（可选）
    /// - Returns: 会议纪要列表
    static func getMeetingMinutesList(
        page: Int? = nil,
        pageSize: Int? = nil,
        search: String? = nil
    ) async throws -> [MeetingMinutesItem] {
        
        let base = try resolvedBaseURL()
        var urlString = "\(base)\(listEndpoint)"
        
        // 添加查询参数
        var queryItems: [String] = []
        if let page = page {
            queryItems.append("page=\(page)")
        }
        if let pageSize = pageSize {
            queryItems.append("page_size=\(pageSize)")
        }
        if let search = search, !search.isEmpty {
            // URL编码搜索关键词
            let encodedSearch = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            queryItems.append("search=\(encodedSearch)")
        }
        if !queryItems.isEmpty {
            urlString += "?\(queryItems.joined(separator: "&"))"
        }
        
        guard let url = URL(string: urlString) else {
            throw MeetingMinutesError.invalidURL
        }
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        try applyCommonHeaders(to: &request)
        
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingMinutesError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 else {
            if let errorResult = try? JSONDecoder().decode(MeetingMinutesListResponse.self, from: data) {
                let errorMsg = errorResult.error ?? errorResult.message ?? "未知错误"
                throw MeetingMinutesError.serverError(errorMsg)
            }
            throw MeetingMinutesError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        // 解析响应（兼容两种结构：直接 MeetingMinutesListResponse / 通用 APIEnvelope）
        do {
            // 1) 旧结构：{ success, data: [...] }
            if let result = try? JSONDecoder().decode(MeetingMinutesListResponse.self, from: data) {
                if let success = result.success, !success {
                    let errorMsg = result.error ?? result.message ?? "获取列表失败"
                    throw MeetingMinutesError.serverError(errorMsg)
                }
                let items = result.data ?? []
                return items
            }

            // 2) 结构：{ success, data: { items: [...], page, page_size, total } }
            if let resultV2 = try? JSONDecoder().decode(MeetingMinutesListResponseV2.self, from: data) {
                if let success = resultV2.success, !success {
                    let msg = resultV2.error ?? resultV2.message ?? "获取列表失败"
                    throw MeetingMinutesError.serverError(msg)
                }
                let items = resultV2.data?.resolvedItems ?? []
                return items
            }

            // 3) 新结构：{ code, message, data: [...] }
            if let env = try? JSONDecoder().decode(APIEnvelope<[MeetingMinutesItem]>.self, from: data) {
                if let success = env.success, !success {
                    let msg = env.error ?? env.message ?? "获取列表失败"
                    throw MeetingMinutesError.serverError(msg)
                }
                if let code = env.code, !(200...299).contains(code) {
                    let msg = env.error ?? env.message ?? "获取列表失败（code=\(code)）"
                    throw MeetingMinutesError.serverError(msg)
                }
                let items = env.data ?? []
                return items
            }

            // 4) 结构：{ code, message, data: { items: [...], page, page_size, total } }
            let envV2 = try JSONDecoder().decode(APIEnvelope<PagedList<MeetingMinutesItem>>.self, from: data)
            if let success = envV2.success, !success {
                let msg = envV2.error ?? envV2.message ?? "获取列表失败"
                throw MeetingMinutesError.serverError(msg)
            }
            if let code = envV2.code, !(200...299).contains(code) {
                let msg = envV2.error ?? envV2.message ?? "获取列表失败（code=\(code)）"
                throw MeetingMinutesError.serverError(msg)
            }
            let items = envV2.data?.resolvedItems ?? []
            return items
        } catch let decodingError as DecodingError {
            #if DEBUG
            switch decodingError {
            case .typeMismatch(let type, let context),
                 .valueNotFound(let type, let context):
                debugPrint("DecodingError: \(decodingError) type=\(type) context=\(context)")
            case .keyNotFound(let key, let context):
                debugPrint("DecodingError: \(decodingError) key=\(key) context=\(context)")
            case .dataCorrupted(let context):
                debugPrint("DecodingError: \(decodingError) context=\(context)")
            @unknown default:
                break
            }
            #endif
            throw decodingError
        }
    }
    
    // MARK: - 获取单个会议纪要详情
    
    /// 获取单个会议纪要详情
    /// - Parameter id: 会议纪要ID
    /// - Returns: 会议纪要详情
    static func getMeetingMinutesDetail(id: String) async throws -> MeetingMinutesItem {
        #if DEBUG
        // Debug 下强制打印请求与解析摘要，便于验证“是否触发了 GET”
        return try await getMeetingMinutesDetail(id: id, verbose: true)
        #else
        return try await getMeetingMinutesDetail(id: id, verbose: false)
        #endif
    }

    // MARK: - 删除会议纪要

    /// 删除会议纪要（后端接口：POST /api/v1/meeting-minutes/{id}/delete）
    static func deleteMeetingMinutes(id: String) async throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { throw MeetingMinutesError.serverError("缺少会议ID") }

        let base = try resolvedBaseURL()
        let urlString = "\(base)\(listEndpoint)/\(trimmedId)\(deleteSuffix)"

        guard let url = URL(string: urlString) else {
            throw MeetingMinutesError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        try applyCommonHeaders(to: &request)

        #if DEBUG
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MeetingMinutesError.invalidResponse
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            #if DEBUG
            #endif
        } else {
            #if DEBUG
            #endif
        }

        guard (200...299).contains(http.statusCode) else {
            // 尽量从响应里提取错误信息
            if let resp = try? JSONDecoder().decode(SimpleResponse.self, from: data) {
                let msg = resp.error ?? resp.message ?? "HTTP \(http.statusCode)"
                throw MeetingMinutesError.serverError(msg)
            }
            if let env = try? JSONDecoder().decode(APIEnvelope<EmptyData>.self, from: data) {
                let msg = env.error ?? env.message ?? "HTTP \(http.statusCode)"
                throw MeetingMinutesError.serverError(msg)
            }
            throw MeetingMinutesError.serverError("HTTP \(http.statusCode)")
        }

        // 兼容业务层 success/code
        if let resp = try? JSONDecoder().decode(SimpleResponse.self, from: data) {
            if let success = resp.success, !success {
                let msg = resp.error ?? resp.message ?? "删除失败"
                throw MeetingMinutesError.serverError(msg)
            }
            if let code = resp.code, !(200...299).contains(code) {
                let msg = resp.error ?? resp.message ?? "删除失败（code=\(code)）"
                throw MeetingMinutesError.serverError(msg)
            }
        } else if let env = try? JSONDecoder().decode(APIEnvelope<EmptyData>.self, from: data) {
            if let success = env.success, !success {
                let msg = env.error ?? env.message ?? "删除失败"
                throw MeetingMinutesError.serverError(msg)
            }
            if let code = env.code, !(200...299).contains(code) {
                let msg = env.error ?? env.message ?? "删除失败（code=\(code)）"
                throw MeetingMinutesError.serverError(msg)
            }
        }
    }

    private static func getMeetingMinutesDetail(id: String, verbose: Bool) async throws -> MeetingMinutesItem {
        
        let base = try resolvedBaseURL()
        let urlString = "\(base)\(listEndpoint)/\(id)"
        
        guard let url = URL(string: urlString) else {
            throw MeetingMinutesError.invalidURL
        }
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        try applyCommonHeaders(to: &request)
        
        if verbose {
        }
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingMinutesError.invalidResponse
        }
        
        if verbose {
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MeetingMinutesError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        // 解析响应（兼容：直接 item / 通用包裹）
        let item: MeetingMinutesItem
        if let direct = try? JSONDecoder().decode(MeetingMinutesItem.self, from: data) {
            // 注意：MeetingMinutesItem 字段全是可选，decode 很可能“成功但全是nil”。
            // 另外：有些后端会返回 status，但把 summary 放在其它字段（如 meeting_minutes/minutes 等），
            // 若仅以 “summary+status 都为空” 作为触发条件，会导致 summary 永远取不到，轮询直到超时。
            let directSummary = (direct.summary ?? direct.meetingSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let directStatus = (direct.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if directSummary.isEmpty {
                let loose = try parseDetailLoose(data: data, fallbackId: id)
                // 用 loose 补齐关键字段（其余字段保持 direct，避免把已解析出的字段覆盖成 nil）
                item = MeetingMinutesItem(
                    id: direct.id ?? loose.id,
                    title: direct.title ?? loose.title,
                    // summary/meetingSummary：优先拿到非空的那一个
                    summary: {
                        let s = (direct.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? loose.summary : direct.summary
                    }(),
                    meetingSummary: {
                        let s = (direct.meetingSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? loose.meetingSummary : direct.meetingSummary
                    }(),
                    date: direct.date ?? loose.date,
                    meetingDate: direct.meetingDate ?? loose.meetingDate,
                    duration: direct.duration ?? loose.duration,
                    audioDuration: direct.audioDuration ?? loose.audioDuration,
                    audioPath: direct.audioPath ?? loose.audioPath,
                    transcriptions: direct.transcriptions ?? loose.transcriptions,
                    meetingDetails: direct.meetingDetails ?? loose.meetingDetails,
                    // status：若 direct 已有值，保留；否则用 loose 补齐
                    status: directStatus.isEmpty ? (direct.status ?? loose.status) : direct.status,
                    audioUrl: direct.audioUrl ?? loose.audioUrl,
                    createdAt: direct.createdAt ?? loose.createdAt,
                    updatedAt: direct.updatedAt ?? loose.updatedAt
                )
            } else {
                item = direct
            }
        } else {
            // 1) 先尝试通用包裹 decode
            if let env = try? JSONDecoder().decode(APIEnvelope<MeetingMinutesItem>.self, from: data) {
                if let success = env.success, !success {
                    throw MeetingMinutesError.serverError(env.error ?? env.message ?? "获取详情失败")
                }
                if let code = env.code, !(200...299).contains(code) {
                    throw MeetingMinutesError.serverError(env.error ?? env.message ?? "获取详情失败（code=\(code)）")
                }
                if let dataItem = env.data {
                    item = dataItem
                } else {
                    // 2) 包裹里 data 为空时，走宽松解析
                    item = try parseDetailLoose(data: data, fallbackId: id)
                }
            } else {
                // 3) decode 不过：走宽松解析
                item = try parseDetailLoose(data: data, fallbackId: id)
            }
        }
        
        // 🔍 调试：打印详情的时长字段（业务只用 audio_duration）
        
        #if DEBUG
        if verbose {
            let sumLen = (item.summary ?? item.meetingSummary)?.count ?? 0
            let detailCount = item.meetingDetails?.count ?? 0
            let titleDesc = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"
            AppGroupDebugLog.append("[MeetingMinutesDetail] id=\(id) title=\(titleDesc) sumLen=\(sumLen) detailCount=\(detailCount)")
        }
        #endif
        
        return item
    }
    
    // MARK: - 生成会议纪要
    
    /// 生成会议纪要
    /// - Parameters:
    ///   - audioFileURL: 音频文件的本地URL
    ///   - speakerCount: 说话人数量（可选，默认为空）
    ///   - enableTranslation: 是否启用翻译（默认 false）
    ///   - targetLanguages: 目标语言（可选）
    ///   - onJobCreated: 若后端走“异步任务”模式，会先返回 jobId。此回调用于调用方尽早持久化 remoteId，便于 App 退出/重进后继续轮询。
    /// - Returns: 会议纪要内容和转写记录
    static func generateMeetingMinutes(
        audioFileURL: URL,
        speakerCount: Int? = nil,
        enableTranslation: Bool = false,
        targetLanguages: String? = nil,
        onJobCreated: ((String) -> Void)? = nil
    ) async throws -> GeneratedMinutes {
        
        
        let base = try resolvedBaseURL()
        guard let url = URL(string: "\(base)\(generateEndpoint)") else {
            throw MeetingMinutesError.invalidURL
        }
        
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw MeetingMinutesError.fileNotFound
        }
        
        // 读取音频文件数据
        let audioData = try Data(contentsOf: audioFileURL)
        let fileName = audioFileURL.lastPathComponent
        
        
        // 创建 multipart/form-data 请求
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url, timeoutInterval: 300) // 5分钟超时（处理长音频）
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try applyCommonHeaders(to: &request)
        
        // 构建 multipart body
        var body = Data()
        
        // 1. 添加音频文件
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio_file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 2. 添加 speaker_count（可选）
        if let count = speakerCount {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"speaker_count\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(count)\r\n".data(using: .utf8)!)
        }
        
        // 3. 添加 enable_translation
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"enable_translation\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(enableTranslation)\r\n".data(using: .utf8)!)
        
        // 4. 添加 target_languages（可选）
        if let languages = targetLanguages, !languages.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"target_languages\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(languages)\r\n".data(using: .utf8)!)
        }
        
        // 结束边界
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        
        let startTime = Date()
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        _ = startTime
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingMinutesError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 else {
            // 尝试解析错误信息
            if let errorResult = try? JSONDecoder().decode(MeetingMinutesResult.self, from: data) {
                let errorMsg = errorResult.error ?? errorResult.message ?? "未知错误"
                throw MeetingMinutesError.serverError(errorMsg)
            }
            throw MeetingMinutesError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        // 解析响应：后端可能是“同步返回 summary”或“异步返回 jobId”

        // 1) 兼容同步结构（旧）
        if let sync = try? JSONDecoder().decode(MeetingMinutesResult.self, from: data),
           let summary = sync.summary, !summary.isEmpty {
            let transcriptions: [MeetingTranscription]? = sync.transcriptions?.compactMap { item in
                guard let content = item.content, !content.isEmpty else { return nil }
                return MeetingTranscription(
                    speaker: item.speaker ?? "说话人",
                    time: item.time ?? "00:00:00",
                    content: content,
                    startTime: parseHMSSeconds(item.time ?? "")
                )
            }
            return GeneratedMinutes(id: nil, title: nil, date: nil, summary: summary, transcriptions: transcriptions, audioDuration: nil, audioUrl: nil)
        }

        // 2) 异步结构：{ code/message/data: { id, status: pending } }
        let env = try JSONDecoder().decode(APIEnvelope<GenerateJob>.self, from: data)
        if let code = env.code, !(200...299).contains(code) {
            throw MeetingMinutesError.serverError(env.error ?? env.message ?? "生成失败（code=\(code)）")
        }
        if let success = env.success, !success {
            throw MeetingMinutesError.serverError(env.error ?? env.message ?? "生成失败")
        }
        guard let job = env.data else {
            throw MeetingMinutesError.emptyResult
        }

        // 关键：尽早把 jobId 告诉调用方（例如写回 MeetingCard.remoteId 并持久化），
        // 这样就算用户在生成过程中退出 App，也能在下次进入详情页时继续 GET 详情轮询。
        onJobCreated?(job.id)

        let item = try await pollMeetingMinutesResult(id: job.id, timeoutSeconds: 600)
        let finalSummary = (item.summary ?? item.meetingSummary)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !finalSummary.isEmpty else {
            throw MeetingMinutesError.emptyResult
        }

        // 优先使用 meeting_details（你的样例），其次使用 transcriptions
        let transcriptions: [MeetingTranscription]? = {
            if let details = item.meetingDetails, !details.isEmpty {
                return details.compactMap { d in
                    guard let text = d.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let speaker = (d.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? d.speakerName!
                        : ("说话人" + (d.speakerId ?? ""))
                    let time = formatHMS(d.startTime ?? 0)
                    return MeetingTranscription(speaker: speaker, time: time, content: text, startTime: d.startTime, endTime: d.endTime)
                }
            }
            if let ts = item.transcriptions, !ts.isEmpty {
                return ts.compactMap { t in
                    guard let content = t.content, !content.isEmpty else { return nil }
                    return MeetingTranscription(
                        speaker: t.speaker ?? "说话人",
                        time: t.time ?? "00:00:00",
                        content: content,
                        startTime: parseHMSSeconds(t.time ?? "")
                    )
                }
            }
            return nil
        }()

        let resolvedTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDate = parseMeetingDate(item: item)
        return GeneratedMinutes(
            id: item.id,
            title: (resolvedTitle?.isEmpty == false) ? resolvedTitle : nil,
            date: resolvedDate,
            summary: finalSummary,
            transcriptions: transcriptions,
            audioDuration: item.audioDuration,
            audioUrl: item.audioUrl
        )
    }

    // MARK: - Polling

    private static func pollMeetingMinutesResult(id: String, timeoutSeconds: TimeInterval) async throws -> MeetingMinutesItem {
        let start = Date()
        var attempt = 0
        var delayMs: UInt64 = 800
        var lastKey: String? = nil
        var consecutiveErrors = 0
        var firstErrorAt: Date? = nil
        var lastError: Error? = nil

        while Date().timeIntervalSince(start) < timeoutSeconds {
            attempt += 1
            do {
                let item = try await getMeetingMinutesDetail(id: id, verbose: attempt == 1)
                consecutiveErrors = 0
                firstErrorAt = nil
                lastError = nil
                let status = (item.status ?? "").lowercased()
                let hasSummary = !((item.summary ?? item.meetingSummary) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty

                // 控制台降噪：只在状态/hasSummary 变化或每 12 次打印一次
                let key = "\(status.isEmpty ? "nil" : status)|\(hasSummary)"
                if lastKey != key || attempt % 12 == 0 {
                    lastKey = key
                }

                if status.contains("fail") || status.contains("error") {
                    throw MeetingMinutesError.serverError("后端任务失败（status=\(item.status ?? "nil")）")
                }
                if hasSummary && (status.isEmpty || status.contains("done") || status.contains("complete") || status.contains("success")) {
                    return item
                }
            } catch {
                // 轮询期间的偶发错误不立刻终止（例如网络波动），打印后继续
                lastError = error
                consecutiveErrors += 1
                if firstErrorAt == nil { firstErrorAt = Date() }
                
                // 如果持续失败太久，直接把“真实错误”抛给上层，避免用户只看到 600 秒超时
                if let firstErrorAt, consecutiveErrors >= 8, Date().timeIntervalSince(firstErrorAt) > 20 {
                    throw error
                }
            }

            try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            delayMs = min(delayMs + 400, 2_500) // 0.8s -> 2.5s
        }

        if let lastError {
            throw MeetingMinutesError.serverError("等待会议纪要生成超时（\(Int(timeoutSeconds))秒）。最后一次错误：\(lastError.localizedDescription)")
        }
        throw MeetingMinutesError.serverError("等待会议纪要生成超时（\(Int(timeoutSeconds))秒）")
    }

    // MARK: - Loose parsing for detail endpoint

    private static func parseDetailLoose(data: Data, fallbackId: String) throws -> MeetingMinutesItem {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data, options: []),
            let root = obj as? [String: Any]
        else {
            throw MeetingMinutesError.emptyResult
        }

        // 若是 envelope，就优先取 data
        let payload: [String: Any] = (root["data"] as? [String: Any]) ?? root
        
        func pickString(_ keys: [String]) -> String? {
            for k in keys {
                if let s = payload[k] as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
            return nil
        }

        func pickNestedString(_ path: [String]) -> String? {
            var cur: Any = payload
            for key in path {
                guard let dict = cur as? [String: Any], let next = dict[key] else { return nil }
                cur = next
            }
            if let s = cur as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return nil
        }

        let id = pickString(["id"]) ?? fallbackId
        let title = pickString(["title", "meeting_title", "name"])
        let status = pickString(["status", "state", "job_status", "processing_status"])
        let summary =
            pickString(["summary", "meeting_summary", "meeting_minutes", "meetingMinutes", "meeting_minutes_text", "minutes_text", "content", "minutes"]) ??
            pickNestedString(["minutes", "summary"]) ??
            pickNestedString(["result", "summary"]) ??
            pickNestedString(["data", "summary"])

        let transcriptionsRaw =
            (payload["transcriptions"] as? [[String: Any]]) ??
            (payload["transcript"] as? [[String: Any]]) ??
            (payload["segments"] as? [[String: Any]])

        let meetingDetailsRaw = (payload["meeting_details"] as? [[String: Any]])

        let transcriptions: [MeetingMinutesResult.TranscriptionItem]? = transcriptionsRaw?.map { seg in
            let speaker = (seg["speaker"] as? String) ?? (seg["spk"] as? String)
            let time = (seg["time"] as? String) ?? (seg["timestamp"] as? String)
            let content = (seg["content"] as? String) ?? (seg["text"] as? String)
            return MeetingMinutesResult.TranscriptionItem(speaker: speaker, time: time, content: content)
        }

        let meetingDetails: [MeetingMinutesItem.MeetingDetail]? = meetingDetailsRaw?.map { seg in
            let speakerId = seg["speaker_id"] as? String
            let speakerName = seg["speaker_name"] as? String
            let text = seg["text"] as? String
            let startTime = seg["start_time"] as? Double
            let endTime = seg["end_time"] as? Double
            return MeetingMinutesItem.MeetingDetail(
                speakerId: speakerId,
                speakerName: speakerName,
                text: text,
                startTime: startTime,
                endTime: endTime
            )
        }

        // 尽量兼容其它字段，但这里主要为轮询提供 status/summary
        // 录音时长：只使用 audio_duration（不做回退），但把 raw duration 打印出来便于排查
        let audioDuration: Double? = {
            if let d = payload["audio_duration"] as? Double { return d }
            if let n = payload["audio_duration"] as? NSNumber { return n.doubleValue }
            if let s = payload["audio_duration"] as? String { return Double(s) }
            return nil
        }()
        let duration: Double? = {
            if let d = payload["duration"] as? Double { return d }
            if let n = payload["duration"] as? NSNumber { return n.doubleValue }
            if let s = payload["duration"] as? String { return Double(s) }
            return nil
        }()

        
        return MeetingMinutesItem(
            id: id,
            title: title,
            summary: summary,
            meetingSummary: pickString(["meeting_summary"]),
            date: pickString(["date"]),
            meetingDate: pickString(["meeting_date"]),
            duration: duration,
            audioDuration: audioDuration,
            audioPath: pickString(["audio_path", "audioPath"]),
            transcriptions: transcriptions,
            meetingDetails: meetingDetails,
            status: status,
            audioUrl: pickString(["audio_url", "audioUrl"]),
            createdAt: pickString(["created_at", "createdAt"]),
            updatedAt: pickString(["updated_at", "updatedAt"])
        )
    }

    private static func formatHMS(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    
    private static func parseHMSSeconds(_ raw: String) -> TimeInterval? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ":").map { String($0) }
        if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let sec = Double(parts[2]) ?? 0
            return max(0, h * 3600 + m * 60 + sec)
        }
        if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let sec = Double(parts[1]) ?? 0
            return max(0, m * 60 + sec)
        }
        if let v = Double(s) { return max(0, v) }
        return nil
    }

    private static func parseMeetingDate(item: MeetingMinutesItem) -> Date? {
        // 目标：日期带时分秒。优先使用 created_at / updated_at（通常为 ISO8601 带时间）
        // 注意：后端可能返回 6 位微秒（例如 2025-12-24T11:27:54.499000），ISO8601DateFormatter 可能解析失败

        func parseBackendTimestamp(_ raw: String) -> Date? {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }

            // 1) ISO8601（带/不带毫秒）
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let d = iso2.date(from: s) { return d }

            // 2) 兜底：无时区、微秒（6位）/毫秒（3位）
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current

            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            if let d = df.date(from: s) { return d }
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            if let d = df.date(from: s) { return d }
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = df.date(from: s) { return d }

            return nil
        }

        if let updatedAt = item.updatedAt, let d = parseBackendTimestamp(updatedAt) {
            #if DEBUG
            #endif
            return d
        }
        if let createdAt = item.createdAt, let d = parseBackendTimestamp(createdAt) {
            #if DEBUG
            #endif
            return d
        }

        if let dateString = item.meetingDate ?? item.date {
            // 有些后端会把完整时间塞进 meeting_date/date
            if let d = parseBackendTimestamp(dateString) { return d }
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: dateString) { return d }
        }
        return nil
    }
}

/// 会议纪要服务错误
enum MeetingMinutesError: LocalizedError {
    case invalidURL
    case fileNotFound
    case invalidResponse
    case serverError(String)
    case emptyResult
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的服务器地址"
        case .fileNotFound:
            return "音频文件不存在"
        case .invalidResponse:
            return "服务器响应无效"
        case .serverError(let message):
            return "服务器错误: \(message)"
        case .emptyResult:
            return "会议纪要生成结果为空"
        case .networkError(let message):
            return "网络错误: \(message)"
        }
    }
}

