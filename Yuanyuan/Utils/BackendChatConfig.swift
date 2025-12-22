import Foundation

/// 自有后端聊天配置（存储在 UserDefaults，避免引入额外依赖/复杂度）
enum BackendChatConfig {
    private enum Keys {
        static let enabled = "backend_chat_enabled"
        static let baseURL = "backend_chat_base_url"
        static let path = "backend_chat_path"
        static let apiKey = "backend_chat_api_key"
        static let model = "backend_chat_model"
        static let shortcut = "backend_chat_shortcut"
    }
    
    static var isEnabled: Bool {
        get {
            // 如果用户从未设置过，Debug 默认开启后端，便于联调；Release 默认关闭避免误连局域网
            if UserDefaults.standard.object(forKey: Keys.enabled) == nil {
                #if DEBUG
                UserDefaults.standard.set(true, forKey: Keys.enabled)
                return true
                #else
                return false
                #endif
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
                if existing == "http://192.168.2.12:8000" || existing == "http://192.168.2.12:8000/" {
                    let migrated = "http://192.168.106.108:8000"
                    UserDefaults.standard.set(migrated, forKey: Keys.baseURL)
                    return migrated
                }
                #endif
                return existing
            }
            
            // Debug 默认指向你提供的本地服务地址；用户之后可在设置里覆盖
            #if DEBUG
            if UserDefaults.standard.object(forKey: Keys.baseURL) == nil || existing.isEmpty {
                let fallback = "http://192.168.106.108:8000"
                UserDefaults.standard.set(fallback, forKey: Keys.baseURL)
                return fallback
            }
            #endif
            
            return existing
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.baseURL) }
    }
    
    /// 默认按你们后端示例：`/api/v1/chat/mock`
    static var path: String {
        get {
            let existing = UserDefaults.standard.string(forKey: Keys.path)
            if let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return existing
            }
            // 保持默认路径，并写入一次，避免 UI 首次展示为空
            let fallback = "/api/v1/chat/mock"
            if UserDefaults.standard.object(forKey: Keys.path) == nil {
                UserDefaults.standard.set(fallback, forKey: Keys.path)
            }
            return fallback
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.path) }
    }
    
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
    
    enum RequestFormat {
        case contentV1 // /api/v1/chat/...
        case openAICompatible // /v1/chat/completions + SSE
    }
    
    static var requestFormat: RequestFormat {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if p.contains("/api/v1/chat/") { return .contentV1 }
        return .openAICompatible
    }
    
    static var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    static func endpointURL() -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }
        
        let normalizedBase = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = p.hasPrefix("/") ? p : "/" + p
        
        return URL(string: normalizedBase + normalizedPath)
    }
}


