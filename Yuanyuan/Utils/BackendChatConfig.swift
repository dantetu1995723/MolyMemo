import Foundation

/// 自有后端聊天配置（存储在 UserDefaults，避免引入额外依赖/复杂度）
enum BackendChatConfig {
    /// 当前后端默认地址（统一入口，避免散落多处导致漏改）
    static let defaultBaseURL = "http://110.16.193.170:58000"

    private enum Keys {
        static let enabled = "backend_chat_enabled"
        static let baseURL = "backend_chat_base_url"
        static let apiKey = "backend_chat_api_key"
        static let model = "backend_chat_model"
        static let shortcut = "backend_chat_shortcut"
#if DEBUG
        static let debugFullResponseLog = "backend_chat_debug_full_response_log"
        static let debugDumpResponseToFile = "backend_chat_debug_dump_response_to_file"
        static let debugLogStreamEvents = "backend_chat_debug_log_stream_events"
        static let debugLogChunkSummary = "backend_chat_debug_log_chunk_summary"
#endif
    }
    
    /// 规范化 baseURL：
    /// - 自动补全 scheme（默认 http://）
    /// - 自动消除重复 scheme（例如 http://http://xx）
    /// - 统一去掉结尾的 `/`
    static func normalizeBaseURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // 常见手滑：粘贴成 http://http://...
        while s.hasPrefix("http://http://") || s.hasPrefix("https://https://") {
            if s.hasPrefix("http://http://") {
                s = "http://" + String(s.dropFirst("http://http://".count))
            } else {
                s = "https://" + String(s.dropFirst("https://https://".count))
            }
        }

        // 如果像 http://https://... 或 https://http://... 这种重复 scheme，保留后一个（更贴近用户最后一次输入）
        if s.hasPrefix("http://https://") {
            s = "https://" + String(s.dropFirst("http://https://".count))
        } else if s.hasPrefix("https://http://") {
            s = "http://" + String(s.dropFirst("https://http://".count))
        }

        // 没有 scheme 的情况：自动补 http://
        if !s.contains("://") {
            s = "http://" + s
        }

        // 统一去掉结尾 /
        if s.hasSuffix("/") {
            s = String(s.dropLast())
        }
        return s
    }

    static var isEnabled: Bool {
        get {
            // 正式接入后端：如果用户从未设置过，默认开启（并写入一次）
            if UserDefaults.standard.object(forKey: Keys.enabled) == nil {
                UserDefaults.standard.set(true, forKey: Keys.enabled)
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.enabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }
    
    static var baseURL: String {
        get {
            let existing = UserDefaults.standard.string(forKey: Keys.baseURL) ?? ""
            if !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                #if DEBUG
                // 如果之前自动写入过旧的联调地址，这里自动迁移到新的联调地址，避免每次手动改
                if existing == "http://192.168.2.12:8000"
                    || existing == "http://192.168.2.12:8000/"
                    || existing == "http://192.168.106.108:8000"
                    || existing == "http://192.168.106.108:8000/"
                {
                    let migrated = defaultBaseURL
                    UserDefaults.standard.set(migrated, forKey: Keys.baseURL)
                    return migrated
                }
                #endif
                let normalized = normalizeBaseURL(existing)
                if normalized != existing {
                    UserDefaults.standard.set(normalized, forKey: Keys.baseURL)
                }
                return normalized
            }
            
            // 默认指向你提供的本地服务地址；用户之后可在设置里覆盖
            if UserDefaults.standard.object(forKey: Keys.baseURL) == nil || existing.isEmpty {
                let fallback = defaultBaseURL
                UserDefaults.standard.set(fallback, forKey: Keys.baseURL)
                return fallback
            }
            
            return existing
        }
        set { UserDefaults.standard.set(normalizeBaseURL(newValue), forKey: Keys.baseURL) }
    }
    
    /// 正式接口固定为 `/api/v1/chat`（不允许切换，避免误连 mock/兼容接口）
    static var path: String { "/api/v1/chat" }
    
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: Keys.apiKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.apiKey) }
    }
    
    /// 可选：如果后端需要 model 字段；不填则不带 model（由后端默认）
    static var model: String {
        get { UserDefaults.standard.string(forKey: Keys.model) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.model) }
    }
    
    /// 可选：对应后端 content 数组里的 shortcut
    static var shortcut: String {
        get { UserDefaults.standard.string(forKey: Keys.shortcut) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.shortcut) }
    }
    
    static var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    static func endpointURL() -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBase = normalizeBaseURL(trimmedBase)
        guard !normalizedBase.isEmpty else { return nil }
        
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = p.hasPrefix("/") ? p : "/" + p
        
        return URL(string: normalizedBase + normalizedPath)
    }

#if DEBUG
    /// Debug：是否在控制台打印完整后端响应（可能很长，默认关闭）
    static var debugLogFullResponse: Bool {
        get {
            // 默认策略：
            // - 模拟器：默认开启（便于联调看“原始后端输出”）
            // - 真机：默认关闭（避免刷爆控制台/泄漏敏感信息）
            if UserDefaults.standard.object(forKey: Keys.debugFullResponseLog) == nil {
#if targetEnvironment(simulator)
                UserDefaults.standard.set(true, forKey: Keys.debugFullResponseLog)
                return true
#else
                UserDefaults.standard.set(false, forKey: Keys.debugFullResponseLog)
                return false
#endif
            }
            return UserDefaults.standard.bool(forKey: Keys.debugFullResponseLog)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.debugFullResponseLog) }
    }

    /// Debug：是否将完整后端响应落盘到 Documents（避免 Xcode 控制台截断，默认开启）
    static var debugDumpResponseToFile: Bool {
        get {
            // 如果从未设置过，默认 true
            if UserDefaults.standard.object(forKey: Keys.debugDumpResponseToFile) == nil {
                UserDefaults.standard.set(true, forKey: Keys.debugDumpResponseToFile)
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.debugDumpResponseToFile)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.debugDumpResponseToFile) }
    }

    /// Debug：是否打印 SSE/NDJSON 的每一个 data chunk（很吵，默认关闭）
    static var debugLogStreamEvents: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.debugLogStreamEvents) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.debugLogStreamEvents) }
    }

    /// Debug：是否打印解析后的 chunk 摘要（比 fullResponse 更轻，默认开启）
    static var debugLogChunkSummary: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.debugLogChunkSummary) == nil {
                UserDefaults.standard.set(true, forKey: Keys.debugLogChunkSummary)
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.debugLogChunkSummary)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.debugLogChunkSummary) }
    }
#endif
}


