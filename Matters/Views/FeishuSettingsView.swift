import SwiftUI
import AuthenticationServices

/// 飞书日历设置视图
struct FeishuSettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
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
                    .padding()
                }
            }
            .navigationTitle("飞书日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") {
                        dismiss()
                    }
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showCredentialsConfig) {
                credentialsConfigSheet
            }
            .task {
                if feishuAPI.isLoggedIn {
                    await loadCalendars()
                }
            }
        }
    }
    
    // MARK: - 配置说明卡片
    
    private var configGuideCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                Text("首次使用需要配置")
                    .font(.headline)
            }
            
            Text("由于飞书企业应用限制，您需要：")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("在飞书开放平台创建企业自建应用", systemImage: "1.circle.fill")
                Label("获取 App ID 和 App Secret", systemImage: "2.circle.fill")
                Label("在本应用中配置凭证", systemImage: "3.circle.fill")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            Button {
                // 预填充已有的凭证（如果有）
                inputAppId = feishuAPI.appId
                inputAppSecret = feishuAPI.appSecret
                showCredentialsConfig = true
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("配置凭证")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            
            // 添加帮助链接
            Button {
                if let url = URL(string: "https://open.feishu.cn/") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "safari")
                    Text("打开飞书开放平台")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - 凭证配置表单
    
    private var credentialsConfigSheet: some View {
        NavigationView {
            Form {
                Section {
                    Text("请在飞书开放平台创建企业自建应用，然后填入凭证")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("说明")
                }
                
                Section {
                    TextField("cli_xxxxxxxxxx", text: $inputAppId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    SecureField("App Secret", text: $inputAppSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("飞书应用凭证")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• 重定向URL需配置为: yuanyuan://feishu/callback")
                        Text("• 需要开启权限: calendar:calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Section {
                    Button {
                        if let url = URL(string: "https://open.feishu.cn/") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "safari")
                            Text("打开飞书开放平台")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }
            }
            .navigationTitle("配置飞书凭证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showCredentialsConfig = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        feishuAPI.saveCredentials(
                            appId: inputAppId.trimmingCharacters(in: .whitespaces),
                            appSecret: inputAppSecret.trimmingCharacters(in: .whitespaces)
                        )
                        showCredentialsConfig = false
                    }
                    .disabled(inputAppId.isEmpty || inputAppSecret.isEmpty)
                }
            }
        }
    }
    
    // MARK: - 登录状态卡片
    
    private var loginStatusCard: some View {
        VStack(spacing: 16) {
            if feishuAPI.isLoggedIn {
                // 已登录状态
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    if let userInfo = feishuAPI.userInfo,
                       let name = userInfo["name"] as? String {
                        Text("已登录：\(name)")
                            .font(.headline)
                    } else {
                        Text("已登录飞书账号")
                            .font(.headline)
                    }
                    
                    // 上次同步时间
                    if let lastSync = syncManager.lastSyncTime {
                        Text("上次同步：\(formatDate(lastSync))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 12) {
                        Button("退出登录") {
                            feishuAPI.logout()
                            calendars.removeAll()
                            selectedCalendars.removeAll()
                        }
                        .foregroundColor(.red)
                        
                        Button("重新配置") {
                            inputAppId = feishuAPI.appId
                            inputAppSecret = feishuAPI.appSecret
                            showCredentialsConfig = true
                        }
                        .foregroundColor(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                
            } else {
                // 未登录状态
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("连接飞书日历")
                        .font(.headline)
                    
                    Text("登录后可以同步飞书日历到本地")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        loginToFeishu()
                    } label: {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoggingIn ? "登录中..." : "登录飞书")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isLoggingIn)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - 日历列表
    
    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择要同步的日历")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    Task {
                        await loadCalendars()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }
            
            if calendars.isEmpty {
                Text("暂无日历")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(calendars) { calendar in
                        calendarRow(calendar)
                        
                        if calendar.id != calendars.last?.id {
                            Divider()
                                .padding(.leading)
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    
    private func calendarRow(_ calendar: FeishuCalendar) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(calendar.summary)
                    .font(.body)
                
                if let description = calendar.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: {
                    selectedCalendars.contains(calendar.id)
                },
                set: { isOn in
                    if isOn {
                        selectedCalendars.insert(calendar.id)
                    } else {
                        selectedCalendars.remove(calendar.id)
                    }
                    syncManager.enabledCalendars = Array(selectedCalendars)
                }
            ))
        }
        .padding()
    }
    
    // MARK: - 同步设置
    
    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("同步设置")
                .font(.headline)
            
            VStack(spacing: 0) {
                HStack {
                    Text("自动同步间隔")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { syncManager.syncInterval },
                        set: { syncManager.syncInterval = $0 }
                    )) {
                        Text("15分钟").tag(15)
                        Text("30分钟").tag(30)
                        Text("1小时").tag(60)
                        Text("2小时").tag(120)
                    }
                    .pickerStyle(.menu)
                }
                .padding()
            }
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // MARK: - 同步按钮
    
    private var syncButton: some View {
        Button {
            Task {
                await syncCalendars()
            }
        } label: {
            HStack {
                if isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                Text(isSyncing ? "同步中..." : "立即同步")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSyncing ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
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

