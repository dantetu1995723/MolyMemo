import Foundation

/// 自有后端聊天配置（存储在 UserDefaults，避免引入额外依赖/复杂度）
enum BackendChatConfig {
    private enum Keys {
        static let enabled = "backend_chat_enabled"
        static let baseURL = "backend_chat_base_url"
        static let apiKey = "backend_chat_api_key"
        static let model = "backend_chat_model"
        static let shortcut = "backend_chat_shortcut"
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
                if existing == "http://192.168.2.12:8000" || existing == "http://192.168.2.12:8000/" {
                    let migrated = "http://192.168.106.108:8000"
                    UserDefaults.standard.set(migrated, forKey: Keys.baseURL)
                    return migrated
                }
                #endif
                return existing
            }
            
            // 默认指向你提供的本地服务地址；用户之后可在设置里覆盖
            if UserDefaults.standard.object(forKey: Keys.baseURL) == nil || existing.isEmpty {
                let fallback = "http://192.168.106.108:8000/"
                UserDefaults.standard.set(fallback, forKey: Keys.baseURL)
                return fallback
            }
            
            return existing
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.baseURL) }
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
        guard !trimmedBase.isEmpty else { return nil }
        
        let normalizedBase = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = p.hasPrefix("/") ? p : "/" + p
        
        return URL(string: normalizedBase + normalizedPath)
    }
}


