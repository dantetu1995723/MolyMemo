import Foundation

@MainActor
final class AuthStore: ObservableObject {
    private enum Keys {
        static let sessionId = "yuanyuan_auth_session_id"
        static let phone = "yuanyuan_auth_phone"
    }

    /// 统一手机号输入规范化：强制去掉空格/短横线/括号等，仅保留数字。
    /// - Note: 粘贴自系统/其它应用的手机号常带格式化空格，这里做强制清洗，避免后端校验失败。
    static func normalizePhoneInput(_ raw: String) -> String {
        let allowed = CharacterSet.decimalDigits
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }
    
    @Published private(set) var isLoggedIn: Bool
    @Published var phone: String
    @Published var verificationCode: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isSendingCode: Bool = false
    @Published private(set) var sendCountdown: Int = 0
    
    // 调试：登录后拉 /api/v1/user/info 的原始返回（用于核对字段）
    @Published private(set) var userInfoRawResponse: String = ""
    @Published private(set) var isLoadingUserInfo: Bool = false
    @Published private(set) var userInfoFetchError: String? = nil
    @Published private(set) var userInfo: UserInfo? = nil
    
    @Published private(set) var isUpdatingUserInfo: Bool = false
    @Published private(set) var updateUserInfoError: String? = nil
    
    var rememberedPhone: String? {
        let raw = (KeychainStore.getString(Keys.phone) ?? UserDefaults.standard.string(forKey: Keys.phone) ?? "")
        let p = Self.normalizePhoneInput(raw)
        return p.isEmpty ? nil : p
    }
    
    var maskedPhone: String {
        guard let p = rememberedPhone, p.count >= 7 else { return "" }
        let start = p.index(p.startIndex, offsetBy: 3)
        let end = p.index(p.startIndex, offsetBy: 7)
        return p.replacingCharacters(in: start..<end, with: "****")
    }

    private var sendCountdownTask: Task<Void, Never>? = nil
    
    var sessionId: String? {
        // Keychain 优先：可跨 Debug 重装保留；UserDefaults 作为兼容回退
        KeychainStore.getString(Keys.sessionId) ?? UserDefaults.standard.string(forKey: Keys.sessionId)
    }
    
    init() {
        let storedSession = (KeychainStore.getString(Keys.sessionId) ?? UserDefaults.standard.string(forKey: Keys.sessionId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.isLoggedIn = !storedSession.isEmpty
        self.phone = Self.normalizePhoneInput(KeychainStore.getString(Keys.phone) ?? UserDefaults.standard.string(forKey: Keys.phone) ?? "")

        // 让后端请求统一走 BackendChatConfig.apiKey（其它 service 会优先读它）
        if !storedSession.isEmpty {
            BackendChatConfig.apiKey = storedSession
            // 顺便把 UserDefaults 补齐，便于旧代码路径命中
            UserDefaults.standard.set(storedSession, forKey: Keys.sessionId)
        }
        if !phone.isEmpty {
            UserDefaults.standard.set(phone, forKey: Keys.phone)
        }
    }
    
    /// 仅用于 UI 层提示错误：避免暴露 `lastError` 的 setter。
    func setLastError(_ message: String?) {
        lastError = message
    }

    func fetchCurrentUserInfoRaw(forceRefresh: Bool = false) async {
        guard isLoggedIn else { return }
        guard !BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let sid = (sessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { return }
        if !forceRefresh && !userInfoRawResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        isLoadingUserInfo = true
        userInfoFetchError = nil
        defer { isLoadingUserInfo = false }

        do {
            let raw = try await AuthService.fetchCurrentUserInfoRaw(
                baseURL: BackendChatConfig.baseURL,
                sessionId: sid
            )
            userInfoRawResponse = raw
            
            // 尝试解析
            if let data = raw.data(using: .utf8) {
                let decoded = try JSONDecoder().decode(UserInfoResponse.self, from: data)
                userInfo = decoded.data
            }
        } catch {
            userInfoFetchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    /// 更新当前用户信息（仅更新 patch 内字段）
    /// - Note: 为了最小化改动，这里复用 `/api/v1/user/info` 的 PUT；失败会写入 `updateUserInfoError`
    func updateUserInfo(patch: [String: Any]) async -> Bool {
        guard isLoggedIn else { return false }
        let sid = (sessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else {
            updateUserInfoError = "登录状态异常，请重新登录"
            return false
        }
        guard !BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updateUserInfoError = "后端 Base URL 为空或不合法，请先在「聊天后端」里配置"
            return false
        }
        guard !patch.isEmpty else { return true }
        if isUpdatingUserInfo { return false }
        
        isUpdatingUserInfo = true
        updateUserInfoError = nil
        defer { isUpdatingUserInfo = false }
        
        do {
            let updated = try await AuthService.updateCurrentUserInfo(
                baseURL: BackendChatConfig.baseURL,
                sessionId: sid,
                patch: patch
            )
            userInfo = updated
            return true
        } catch {
            updateUserInfoError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
    
    func quickLogin() async {
        let p = rememberedPhone ?? Self.normalizePhoneInput(phone)
        guard !p.isEmpty else {
            lastError = "未找到记录的手机号"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 提示：此处假定后端已支持“识别本机号码”或针对已验证号码的“免密登录/一键登录”
            // 如果后端目前仍需验证码，此处可临时透传一个约定好的 code（如 123456）进行联调
            let sessionId = try await AuthService.login(
                baseURL: BackendChatConfig.baseURL,
                phone: p,
                verificationCode: "123456" // 联调期间默认 code，生产环境应替换为 token 校验逻辑
            )
            
            _ = KeychainStore.setString(sessionId, for: Keys.sessionId)
            _ = KeychainStore.setString(p, for: Keys.phone)
            UserDefaults.standard.set(sessionId, forKey: Keys.sessionId)
            UserDefaults.standard.set(p, forKey: Keys.phone)
            BackendChatConfig.apiKey = sessionId
            
            lastError = nil
            isLoggedIn = true
            await fetchCurrentUserInfoRaw(forceRefresh: true)
        } catch {
            lastError = "一键登录失败，请使用验证码登录"
        }
    }
    
    func login() async {
        let p = Self.normalizePhoneInput(phone)
        let c = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !p.isEmpty else {
            lastError = "请输入手机号"
            return
        }
        
        guard !c.isEmpty else {
            lastError = "请输入验证码"
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
            
            // 登录成功后拉一次“用户信息（原始返回）”，方便在 SettingsView 里核对字段
            userInfoRawResponse = ""
            userInfoFetchError = nil
            await fetchCurrentUserInfoRaw(forceRefresh: true)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoggedIn = false
            
            #if DEBUG
            #endif
        }
    }

    func sendVerificationCode() async {
        let p = Self.normalizePhoneInput(phone)
        guard !p.isEmpty else {
            lastError = "请输入手机号"
            return
        }
        guard !isSendingCode && sendCountdown == 0 else { return }

        isSendingCode = true
        defer { isSendingCode = false }

        do {
            try await AuthService.sendVerificationCode(
                baseURL: BackendChatConfig.baseURL,
                phone: p
            )
            lastError = nil
            startSendCountdown(seconds: 60)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func startSendCountdown(seconds: Int) {
        sendCountdownTask?.cancel()
        sendCountdown = max(0, seconds)
        guard sendCountdown > 0 else { return }

        sendCountdownTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.sendCountdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                self.sendCountdown = max(0, self.sendCountdown - 1)
            }
        }
    }
    
    func logout() {
        Task { await logoutAsync() }
    }

    func logoutAsync(clearPhone: Bool = false) async {
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

        clearLocalAuth(clearPhone: clearPhone)
    }

    func deactivateAccount() async -> Bool {
        let sessionId = (sessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty else {
            lastError = "登录状态异常，请重新登录"
            return false
        }
        guard !BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "后端 Base URL 为空或不合法，请先在「聊天后端」里配置"
            return false
        }

        do {
            try await AuthService.deactivateAccount(
                baseURL: BackendChatConfig.baseURL,
                sessionId: sessionId
            )
            clearLocalAuth(clearPhone: true)
            lastError = nil
            return true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func clearLocalAuth(clearPhone: Bool) {
        UserDefaults.standard.removeObject(forKey: Keys.sessionId)
        _ = KeychainStore.delete(Keys.sessionId)
        verificationCode = ""
        isLoggedIn = false
        
        userInfoRawResponse = ""
        userInfoFetchError = nil
        isLoadingUserInfo = false

        // 清掉后端聊天 token，避免误带旧登录态
        BackendChatConfig.apiKey = ""

        if clearPhone {
            phone = ""
            UserDefaults.standard.removeObject(forKey: Keys.phone)
            _ = KeychainStore.delete(Keys.phone)
        }

        #if DEBUG
        #endif
    }
}


