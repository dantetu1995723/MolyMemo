import Foundation

@MainActor
final class AuthStore: ObservableObject {
    private enum Keys {
        static let sessionId = "yuanyuan_auth_session_id"
        static let phone = "yuanyuan_auth_phone"
    }
    
    @Published private(set) var isLoggedIn: Bool
    @Published var phone: String
    @Published var verificationCode: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String? = nil
    
    var sessionId: String? {
        // Keychain 优先：可跨 Debug 重装保留；UserDefaults 作为兼容回退
        KeychainStore.getString(Keys.sessionId) ?? UserDefaults.standard.string(forKey: Keys.sessionId)
    }
    
    init() {
        let storedSession = (KeychainStore.getString(Keys.sessionId) ?? UserDefaults.standard.string(forKey: Keys.sessionId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.isLoggedIn = !storedSession.isEmpty
        self.phone = (KeychainStore.getString(Keys.phone) ?? UserDefaults.standard.string(forKey: Keys.phone) ?? "")

        // 让后端请求统一走 BackendChatConfig.apiKey（其它 service 会优先读它）
        if !storedSession.isEmpty {
            BackendChatConfig.apiKey = storedSession
            // 顺便把 UserDefaults 补齐，便于旧代码路径命中
            UserDefaults.standard.set(storedSession, forKey: Keys.sessionId)
        }
        if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(phone, forKey: Keys.phone)
        }
    }
    
    func login() async {
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines) // 允许为空
        
        guard !p.isEmpty else {
            lastError = "请输入手机号"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        #if DEBUG
        #endif
        
        do {
            let sessionId = try await AuthService.login(
                baseURL: BackendChatConfig.baseURL,
                phone: p,
                verificationCode: c
            )
            // 1) Keychain：跨重装保留
            _ = KeychainStore.setString(sessionId, for: Keys.sessionId)
            _ = KeychainStore.setString(p, for: Keys.phone)
            // 2) UserDefaults：兼容旧读取路径
            UserDefaults.standard.set(sessionId, forKey: Keys.sessionId)
            UserDefaults.standard.set(p, forKey: Keys.phone)
            
            // 复用后端聊天的 Authorization 存储位：保存 session_id，便于后续请求统一取值
            BackendChatConfig.apiKey = sessionId
            
            lastError = nil
            isLoggedIn = true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoggedIn = false
            
            #if DEBUG
            #endif
        }
    }
    
    func logout() {
        Task { await logoutAsync() }
    }

    func logoutAsync() async {
        let sessionId = (sessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 先尝试通知后端登出；即使失败也会清本地，避免用户被卡住
        if !BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try await AuthService.logout(
                    baseURL: BackendChatConfig.baseURL,
                    sessionId: sessionId
                )
                #if DEBUG
                #endif
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                #if DEBUG
                #endif
            }
        }
        
        UserDefaults.standard.removeObject(forKey: Keys.sessionId)
        _ = KeychainStore.delete(Keys.sessionId)
        // 保留手机号，方便下次登录更快
        verificationCode = ""
        isLoggedIn = false
        
        // 清掉后端聊天 token，避免误带旧登录态
        BackendChatConfig.apiKey = ""
        
        #if DEBUG
        #endif
    }
}


