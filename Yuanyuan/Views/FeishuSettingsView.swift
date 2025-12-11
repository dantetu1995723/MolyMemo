import SwiftUI
import AuthenticationServices

/// 飞书日历设置视图
struct FeishuSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var feishuAPI = FeishuAPIService.shared
    @StateObject private var syncManager = FeishuCalendarSyncManager.shared
    
    @State private var isLoggingIn = false
    @State private var isSyncing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var calendars: [FeishuCalendar] = []
    @State private var selectedCalendars: Set<String> = []
    @State private var showCredentialsConfig = false
    @State private var inputAppId = ""
    @State private var inputAppSecret = ""
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    var body: some View {
        ZStack {
            // 背景渐变
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            // 配置说明卡片（未配置时显示）
                            if !feishuAPI.isConfigured {
                                configGuideCard
                            }
                            
                            // 登录状态卡片
                            if feishuAPI.isConfigured {
                                loginStatusCard
                            }
                            
                            // 日历列表
                            if feishuAPI.isLoggedIn {
                                calendarsSection
                                
                                // 同步设置
                                syncSettingsSection
                                
                                // 同步按钮
                                syncButton
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 0)
                        .padding(.bottom, 34)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                ModuleNavigationBar(
                    title: "飞书日历",
                    themeColor: themeColor,
                    onBack: { dismiss() }
                )
                
                // 向上滑动提示（放在导航栏下方）- 两个叠加的箭头
                ZStack {
                    // 底层箭头 - 稍大，半透明
                    Image(systemName: "chevron.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black.opacity(0.4))
                        .offset(y: 1)
                    
                    // 顶层箭头 - 更明显
                    Image(systemName: "chevron.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black.opacity(0.85))
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showCredentialsConfig) {
            credentialsConfigSheet
                .presentationDragIndicator(.visible)
        }
        .task {
            if feishuAPI.isLoggedIn {
                await loadCalendars()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    
    // MARK: - 配置说明卡片
    
    private var configGuideCard: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(themeColor.opacity(0.8))
                    
                    Text("首次使用需要配置")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                }
                
                Text("由于飞书企业应用限制，您需要：")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(themeColor.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text("1")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                            )
                        Text("在飞书开放平台创建企业自建应用")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    
                    HStack(spacing: 12) {
                        Circle()
                            .fill(themeColor.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text("2")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                            )
                        Text("获取 App ID 和 App Secret")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    
                    HStack(spacing: 12) {
                        Circle()
                            .fill(themeColor.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text("3")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                            )
                        Text("在本应用中配置凭证")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                }
                .padding(.vertical, 4)
                
                Button {
                    HapticFeedback.medium()
                    inputAppId = feishuAPI.appId
                    inputAppSecret = feishuAPI.appSecret
                    showCredentialsConfig = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .font(.system(size: 18, weight: .bold))
                        Text("配置凭证")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LiquidGlassCapsuleBackground())
                }
                .buttonStyle(ScaleButtonStyle())
                
                Button {
                    HapticFeedback.light()
                    if let url = URL(string: "https://open.feishu.cn/") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                            .font(.system(size: 16, weight: .semibold))
                        Text("打开飞书开放平台")
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black.opacity(0.5))
                }
            }
        }
    }
    
    // MARK: - 凭证配置表单
    
    private var credentialsConfigSheet: some View {
        ZStack {
            ModuleBackgroundView(themeColor: themeColor)
            
            VStack(spacing: 0) {
                Color.clear.frame(height: 16)
                
                // 头部
                HStack {
                    Button {
                        HapticFeedback.light()
                        showCredentialsConfig = false
                    } label: {
                        Text("取消")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Text("配置飞书凭证")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                    
                    Spacer()
                    
                    Button {
                        HapticFeedback.medium()
                        feishuAPI.saveCredentials(
                            appId: inputAppId.trimmingCharacters(in: .whitespaces),
                            appSecret: inputAppSecret.trimmingCharacters(in: .whitespaces)
                        )
                        showCredentialsConfig = false
                    } label: {
                        Text("保存")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(inputAppId.isEmpty || inputAppSecret.isEmpty ? .black.opacity(0.3) : themeColor)
                    }
                    .disabled(inputAppId.isEmpty || inputAppSecret.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 说明
                        LiquidGlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(themeColor.opacity(0.8))
                                
                                Text("请在飞书开放平台创建企业自建应用，然后填入凭证")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.black.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        // 凭证输入
                        LiquidGlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("飞书应用凭证")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.black.opacity(0.85))
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("App ID")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.black.opacity(0.6))
                                        
                                        TextField("cli_xxxxxxxxxx", text: $inputAppId)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.black.opacity(0.85))
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.white.opacity(0.6))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                                                    )
                                            )
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("App Secret")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.black.opacity(0.6))
                                        
                                        SecureField("请输入 App Secret", text: $inputAppSecret)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.black.opacity(0.85))
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.white.opacity(0.6))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                                                    )
                                            )
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.circle")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("重定向URL需配置为: yuanyuan://feishu/callback")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.circle")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("需要开启权限: calendar:calendar")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                }
                                .foregroundColor(.black.opacity(0.5))
                            }
                        }
                        
                        // 帮助链接
                        Button {
                            HapticFeedback.light()
                            if let url = URL(string: "https://open.feishu.cn/") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            LiquidGlassCard {
                                HStack {
                                    Image(systemName: "safari")
                                        .font(.system(size: 18, weight: .semibold))
                                    
                                    Text("打开飞书开放平台")
                                        .font(.system(size: 16, weight: .semibold))
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.black.opacity(0.7))
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - 登录状态卡片
    
    private var loginStatusCard: some View {
        LiquidGlassCard {
            if feishuAPI.isLoggedIn {
                // 已登录状态
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(themeColor)
                        .shadow(color: themeColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    VStack(spacing: 6) {
                        if let userInfo = feishuAPI.userInfo,
                           let name = userInfo["name"] as? String {
                            Text("已登录：\(name)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.black.opacity(0.85))
                        } else {
                            Text("已登录飞书账号")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.black.opacity(0.85))
                        }
                        
                        if let lastSync = syncManager.lastSyncTime {
                            Text("上次同步：\(formatDate(lastSync))")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black.opacity(0.5))
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            HapticFeedback.medium()
                            feishuAPI.logout()
                            calendars.removeAll()
                            selectedCalendars.removeAll()
                        } label: {
                            Text("退出登录")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.08))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        Button {
                            HapticFeedback.light()
                            inputAppId = feishuAPI.appId
                            inputAppSecret = feishuAPI.appSecret
                            showCredentialsConfig = true
                        } label: {
                            Text("重新配置")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black.opacity(0.6))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.5))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                
            } else {
                // 未登录状态
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 52))
                        .foregroundColor(themeColor)
                        .shadow(color: themeColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        .padding(.top, 20)
                    
                    VStack(spacing: 8) {
                        Text("连接飞书日历")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                        
                        Text("登录后可以同步飞书日历到本地")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    
                    Button {
                        HapticFeedback.medium()
                        loginToFeishu()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoggingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.7)))
                            }
                            Text(isLoggingIn ? "登录中..." : "登录飞书")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LiquidGlassCapsuleBackground())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isLoggingIn)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - 日历列表
    
    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择要同步的日历")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))
                
                Spacer()
                
                Button {
                    HapticFeedback.light()
                    Task {
                        await loadCalendars()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(GlassButtonBackground())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 4)
            
            if calendars.isEmpty {
                LiquidGlassCard {
                    Text("暂无日历")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.black.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            } else {
                LiquidGlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(calendars) { calendar in
                            calendarRow(calendar)
                            
                            if calendar.id != calendars.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func calendarRow(_ calendar: FeishuCalendar) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(calendar.summary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                
                if let description = calendar.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: {
                    selectedCalendars.contains(calendar.id)
                },
                set: { isOn in
                    HapticFeedback.light()
                    if isOn {
                        selectedCalendars.insert(calendar.id)
                    } else {
                        selectedCalendars.remove(calendar.id)
                    }
                    syncManager.enabledCalendars = Array(selectedCalendars)
                }
            ))
            .tint(themeColor)
        }
        .padding(16)
    }
    
    // MARK: - 同步设置
    
    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("同步设置")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
                .padding(.horizontal, 4)
            
            LiquidGlassCard {
                HStack {
                    Text("自动同步间隔")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.85))
                    
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { syncManager.syncInterval },
                        set: { 
                            HapticFeedback.light()
                            syncManager.syncInterval = $0 
                        }
                    )) {
                        Text("15分钟").tag(15)
                        Text("30分钟").tag(30)
                        Text("1小时").tag(60)
                        Text("2小时").tag(120)
                    }
                    .pickerStyle(.menu)
                    .tint(.black.opacity(0.7))
                }
            }
        }
    }
    
    // MARK: - 同步按钮
    
    private var syncButton: some View {
        Button {
            HapticFeedback.medium()
            Task {
                await syncCalendars()
            }
        } label: {
            HStack(spacing: 8) {
                if isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.7)))
                }
                Text(isSyncing ? "同步中..." : "立即同步")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(isSyncing || selectedCalendars.isEmpty ? .black.opacity(0.3) : .black.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    LiquidGlassCapsuleBackground()
                    
                    if isSyncing || selectedCalendars.isEmpty {
                        Capsule()
                            .fill(Color.white.opacity(0.4))
                    }
                }
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isSyncing || selectedCalendars.isEmpty)
    }
    
    // MARK: - 方法
    
    private func loginToFeishu() {
        // 检查是否已配置凭证
        guard feishuAPI.isConfigured else {
            errorMessage = "请先配置飞书应用凭证"
            showError = true
            return
        }
        
        isLoggingIn = true
        
        Task {
            do {
                // 获取当前window作为presentation context
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    try await feishuAPI.startLogin(presentationContext: FeishuPresentationContextProvider(window: window))
                    await loadCalendars()
                    print("✅ 飞书登录成功")
                } else {
                    throw FeishuError.invalidURL
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                print("⚠️ 飞书登录失败: \(error)")
            }
            
            isLoggingIn = false
        }
    }
    
    private func loadCalendars() async {
        do {
            calendars = try await feishuAPI.fetchCalendars()
            selectedCalendars = Set(syncManager.enabledCalendars)
            print("✅ 加载了 \(calendars.count) 个日历")
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("⚠️ 加载日历失败: \(error)")
        }
    }
    
    private func syncCalendars() async {
        guard !selectedCalendars.isEmpty else { return }
        
        isSyncing = true
        
        do {
            try await syncManager.syncCalendars()
            print("✅ 同步成功")
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("⚠️ 同步失败: \(error)")
        }
        
        isSyncing = false
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

class FeishuPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    
    init(window: UIWindow) {
        self.window = window
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window
    }
}

#Preview {
    FeishuSettingsView()
}

