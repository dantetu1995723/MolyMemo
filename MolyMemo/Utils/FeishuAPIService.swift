import Foundation
import AuthenticationServices

// 飞书API服务
class FeishuAPIService: NSObject, ObservableObject {
    static let shared = FeishuAPIService()
    
    // 飞书应用配置 - 用户自行配置
    private let redirectUri = "\(AppIdentifiers.urlScheme)://feishu/callback"  // 回调地址
    
    // 从UserDefaults读取用户配置的凭证
    var appId: String {
        UserDefaults.standard.string(forKey: "feishu_app_id") ?? ""
    }
    
    var appSecret: String {
        UserDefaults.standard.string(forKey: "feishu_app_secret") ?? ""
    }
    
    // 检查是否已配置凭证
    var isConfigured: Bool {
        !appId.isEmpty && !appSecret.isEmpty
    }
    
    // 保存用户配置的凭证
    func saveCredentials(appId: String, appSecret: String) {
        UserDefaults.standard.set(appId, forKey: "feishu_app_id")
        UserDefaults.standard.set(appSecret, forKey: "feishu_app_secret")
        updateLoginStatus()
    }
    
    // 清除凭证
    func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: "feishu_app_id")
        UserDefaults.standard.removeObject(forKey: "feishu_app_secret")
        logout()
    }
    
    // API端点
    private let baseURL = "https://open.feishu.cn/open-apis"
    
    // 存储token的key
    private let accessTokenKey = "feishu_access_token"
    private let refreshTokenKey = "feishu_refresh_token"
    private let tokenExpiryKey = "feishu_token_expiry"
    private let userInfoKey = "feishu_user_info"
    
    // 发布登录状态变化
    @Published var isLoggedIn: Bool = false
    
    private override init() {
        super.init()
        // 初始化时检查登录状态
        updateLoginStatus()
    }
    
    // MARK: - 认证相关
    
    /// 更新登录状态
    private func updateLoginStatus() {
        guard let token = accessToken, !token.isEmpty else {
            isLoggedIn = false
            return
        }
        // 检查token是否过期
        if let expiry = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date {
            isLoggedIn = expiry > Date()
        } else {
            isLoggedIn = false
        }
    }
    
    /// 获取存储的访问token
    var accessToken: String? {
        UserDefaults.standard.string(forKey: accessTokenKey)
    }
    
    /// 获取用户信息
    var userInfo: [String: Any]? {
        if let data = UserDefaults.standard.data(forKey: userInfoKey) {
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        return nil
    }
    
    /// 开始OAuth登录流程
    func startLogin(presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        // 构建授权URL
        let scope = "calendar:calendar" // 申请日历权限
        guard var urlComponents = URLComponents(string: "https://open.feishu.cn/open-apis/authen/v1/authorize") else {
            throw FeishuError.invalidURL
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "app_id", value: appId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        
        guard let authURL = urlComponents.url else {
            throw FeishuError.invalidURL
        }
        
        // 使用ASWebAuthenticationSession进行OAuth
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: AppIdentifiers.urlScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: FeishuError.noAuthCode)
                    return
                }
                
                // 用code换取token
                Task {
                    do {
                        try await self.exchangeToken(code: code)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            session.presentationContextProvider = presentationContext
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
    
    /// 用授权码换取token
    private func exchangeToken(code: String) async throws {
        let url = URL(string: "\(baseURL)/authen/v1/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "client_id": appId,
            "client_secret": appSecret,
            "code": code,
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FeishuError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let data = json?["data"] as? [String: Any],
              let accessToken = data["access_token"] as? String,
              let refreshToken = data["refresh_token"] as? String,
              let expiresIn = data["expires_in"] as? Int else {
            throw FeishuError.invalidResponse
        }
        
        // 保存token
        let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        UserDefaults.standard.set(expiry, forKey: tokenExpiryKey)
        
        // 更新登录状态
        await MainActor.run {
            updateLoginStatus()
        }
        
        // 获取用户信息
        try await fetchUserInfo()
    }
    
    /// 刷新token
    private func refreshAccessToken() async throws {
        guard let refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey) else {
            throw FeishuError.noRefreshToken
        }
        
        let url = URL(string: "\(baseURL)/authen/v1/refresh_access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": appId,
            "client_secret": appSecret
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FeishuError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let data = json?["data"] as? [String: Any],
              let accessToken = data["access_token"] as? String,
              let newRefreshToken = data["refresh_token"] as? String,
              let expiresIn = data["expires_in"] as? Int else {
            throw FeishuError.invalidResponse
        }
        
        // 更新token
        let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        UserDefaults.standard.set(newRefreshToken, forKey: refreshTokenKey)
        UserDefaults.standard.set(expiry, forKey: tokenExpiryKey)
        
        // 更新登录状态
        await MainActor.run {
            updateLoginStatus()
        }
    }
    
    /// 退出登录
    func logout() {
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
        UserDefaults.standard.removeObject(forKey: userInfoKey)
        updateLoginStatus()
    }
    
    // MARK: - 用户信息
    
    /// 获取用户信息
    private func fetchUserInfo() async throws {
        guard let token = accessToken else {
            throw FeishuError.notLoggedIn
        }
        
        let url = URL(string: "\(baseURL)/authen/v1/user_info")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FeishuError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let userData = json?["data"] as? [String: Any] {
            // 保存用户信息
            if let userDataJSON = try? JSONSerialization.data(withJSONObject: userData) {
                UserDefaults.standard.set(userDataJSON, forKey: userInfoKey)
            }
        }
    }
    
    // MARK: - 日历相关API
    
    /// 获取日历列表
    func fetchCalendars() async throws -> [FeishuCalendar] {
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw FeishuError.notLoggedIn
        }
        
        let url = URL(string: "\(baseURL)/calendar/v4/calendars")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FeishuError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["data"]  as? [String: Any],
              let calendars = items["calendars"] as? [[String: Any]] else {
            return []
        }
        
        return calendars.compactMap { FeishuCalendar(dict: $0) }
    }
    
    /// 获取日历事件列表
    func fetchEvents(calendarId: String, startTime: Date, endTime: Date) async throws -> [FeishuEvent] {
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw FeishuError.notLoggedIn
        }
        
        // 将时间转换为时间戳（秒）
        let startTimestamp = Int(startTime.timeIntervalSince1970)
        let endTimestamp = Int(endTime.timeIntervalSince1970)
        
        var urlComponents = URLComponents(string: "\(baseURL)/calendar/v4/calendars/\(calendarId)/events")!
        urlComponents.queryItems = [
            URLQueryItem(name: "start_time", value: "\(startTimestamp)"),
            URLQueryItem(name: "end_time", value: "\(endTimestamp)")
        ]
        
        guard let url = urlComponents.url else {
            throw FeishuError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FeishuError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["data"] as? [String: Any],
              let events = items["items"] as? [[String: Any]] else {
            return []
        }
        
        return events.compactMap { FeishuEvent(dict: $0) }
    }
    
    /// 创建日历事件
    @discardableResult
    func createEvent(calendarId: String, event: FeishuEventCreate) async throws -> FeishuEvent {
        try await ensureValidToken()
        
        guard let token = accessToken else {
            throw FeishuError.notLoggedIn
        }
        
        let url = URL(string: "\(baseURL)/calendar/v4/calendars/\(calendarId)/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(event)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FeishuError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let eventData = json?["data"] as? [String: Any],
              let event = FeishuEvent(dict: eventData) else {
            throw FeishuError.invalidResponse
        }
        
        return event
    }
    
    // MARK: - 辅助方法
    
    /// 确保token有效
    private func ensureValidToken() async throws {
        // 检查token是否即将过期（提前5分钟刷新）
        if let expiry = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date {
            let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)
            if expiry < fiveMinutesFromNow {
                try await refreshAccessToken()
            }
        }
    }
}

// MARK: - 数据模型

/// 飞书日历
struct FeishuCalendar: Identifiable {
    let id: String
    let summary: String
    let description: String?
    let permissions: String
    let color: Int
    let type: String
    
    init?(dict: [String: Any]) {
        guard let id = dict["calendar_id"] as? String,
              let summary = dict["summary"] as? String else {
            return nil
        }
        
        self.id = id
        self.summary = summary
        self.description = dict["description"] as? String
        self.permissions = dict["permissions"] as? String ?? "reader"
        self.color = dict["color"] as? Int ?? 0
        self.type = dict["type"] as? String ?? "primary"
    }
}

/// 飞书日历事件
struct FeishuEvent: Identifiable {
    let id: String
    let summary: String
    let description: String?
    let startTime: Date
    let endTime: Date
    let location: String?
    let attendees: [String]
    
    init?(dict: [String: Any]) {
        guard let id = dict["event_id"] as? String,
              let summary = dict["summary"] as? String else {
            return nil
        }
        
        self.id = id
        self.summary = summary
        self.description = dict["description"] as? String
        self.location = (dict["location"] as? [String: Any])?["name"] as? String
        
        // 解析时间
        if let startTimeDict = dict["start_time"] as? [String: Any],
           let timestamp = startTimeDict["timestamp"] as? String,
           let timeInterval = TimeInterval(timestamp) {
            self.startTime = Date(timeIntervalSince1970: timeInterval)
        } else {
            self.startTime = Date()
        }
        
        if let endTimeDict = dict["end_time"] as? [String: Any],
           let timestamp = endTimeDict["timestamp"] as? String,
           let timeInterval = TimeInterval(timestamp) {
            self.endTime = Date(timeIntervalSince1970: timeInterval)
        } else {
            self.endTime = Date()
        }
        
        // 解析参与者
        if let attendeesArray = dict["attendees"] as? [[String: Any]] {
            self.attendees = attendeesArray.compactMap { $0["user_id"] as? String }
        } else {
            self.attendees = []
        }
    }
}

/// 创建飞书事件的数据结构
struct FeishuEventCreate: Encodable {
    let summary: String
    let description: String?
    let startTime: TimeInterval
    let endTime: TimeInterval
    let location: String?
    let reminders: [Int]?  // 提前提醒时间（分钟）
    
    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case startTime = "start_time"
        case endTime = "end_time"
        case location
        case reminders
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(description, forKey: .description)
        
        // 时间格式
        let startTimeDict = ["timestamp": String(Int(startTime))]
        let endTimeDict = ["timestamp": String(Int(endTime))]
        try container.encode(startTimeDict, forKey: .startTime)
        try container.encode(endTimeDict, forKey: .endTime)
        
        // 地点
        if let location = location {
            let locationDict = ["name": location]
            try container.encode(locationDict, forKey: .location)
        }
        
        // 提醒
        if let reminders = reminders {
            try container.encode(reminders, forKey: .reminders)
        }
    }
}

// MARK: - 错误类型

enum FeishuError: LocalizedError {
    case invalidURL
    case noAuthCode
    case networkError
    case invalidResponse
    case notLoggedIn
    case noRefreshToken
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .noAuthCode:
            return "未获取到授权码"
        case .networkError:
            return "网络请求失败"
        case .invalidResponse:
            return "服务器响应格式错误"
        case .notLoggedIn:
            return "未登录飞书账号"
        case .noRefreshToken:
            return "无刷新令牌"
        }
    }
}

