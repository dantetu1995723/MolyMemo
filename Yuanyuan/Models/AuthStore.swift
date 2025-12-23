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
    
    var sessionId: String? { UserDefaults.standard.string(forKey: Keys.sessionId) }
    
    init() {
        let storedSession = UserDefaults.standard.string(forKey: Keys.sessionId) ?? ""
        self.isLoggedIn = !storedSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.phone = UserDefaults.standard.string(forKey: Keys.phone) ?? ""
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
        print("🔐 [Auth] login start, phone=\(p), verification_code_len=\(c.count)")
        #endif
        
        do {
            let sessionId = try await AuthService.login(
                baseURL: BackendChatConfig.baseURL,
                phone: p,
                verificationCode: c
            )
            UserDefaults.standard.set(sessionId, forKey: Keys.sessionId)
            UserDefaults.standard.set(p, forKey: Keys.phone)
            
            // 复用后端聊天的 Authorization 存储位：保存 session_id，便于后续请求统一取值
            BackendChatConfig.apiKey = sessionId
            
            lastError = nil
            isLoggedIn = true
            
            #if DEBUG
            let masked = sessionId.count <= 8 ? "***" : "\(sessionId.prefix(4))...\(sessionId.suffix(4))"
            print("✅ [Auth] login success, session_id=\(masked), isLoggedIn=true")
            #endif
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoggedIn = false
            
            #if DEBUG
            print("❌ [Auth] login failed, error=\(lastError ?? error.localizedDescription)")
            #endif
        }
    }
    
    func logout() {
        Task { await logoutAsync() }
    }

    func logoutAsync() async {
        let sessionId = (sessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        #if DEBUG
        let masked = sessionId.count <= 8 ? "***" : "\(sessionId.prefix(4))...\(sessionId.suffix(4))"
        print("🔐 [Auth] logout start, sessionId=\(masked)")
        #endif
        
        // 先尝试通知后端登出；即使失败也会清本地，避免用户被卡住
        if !BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try await AuthService.logout(
                    baseURL: BackendChatConfig.baseURL,
                    sessionId: sessionId
                )
                #if DEBUG
                print("✅ [Auth] logout API success")
                #endif
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                #if DEBUG
                print("⚠️ [Auth] logout API failed, error=\(lastError ?? error.localizedDescription)")
                #endif
            }
        }
        
        UserDefaults.standard.removeObject(forKey: Keys.sessionId)
        // 保留手机号，方便下次登录更快
        verificationCode = ""
        isLoggedIn = false
        
        // 清掉后端聊天 token，避免误带旧登录态
        BackendChatConfig.apiKey = ""
        
        #if DEBUG
        print("✅ [Auth] local logout done, isLoggedIn=false")
        #endif
    }
}


