import SwiftUI
import UIKit
import Combine

// 设置页面 - 简约白色现代风
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var authStore: AuthStore
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showUpdateError = false
    @State private var updateErrorMessage = ""
    
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var focusedField: Field?
    @State private var lastFocusedField: Field? = nil
    
    @State private var draftUsername: String = ""
    @State private var draftEmail: String = ""
    @State private var draftWechat: String = ""
    @State private var draftCity: String = ""
    @State private var draftAddress: String = ""
    @State private var draftCompany: String = ""
    @State private var draftIndustry: String = ""
    
    enum Field: Hashable {
        case username, email, wechat, city, address, company, industry
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.98).ignoresSafeArea()
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            // 用户信息头部
                            userInfoHeader
                            
                            // 用户详细信息卡片
                            if let userInfo = authStore.userInfo {
                                infoSection(userInfo: userInfo, proxy: proxy)
                            } else {
                                infoSkeleton
                            }
                            
                            // 功能操作区
                            actionSection
                            
                            // 底部退出/注销
                            dangerSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, max(30, keyboardHeight + 16))
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        focusedField = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .onChange(of: focusedField) { old, new in
                        // 离开某一行时，保存该行（避免频繁请求：只在切焦/收键盘时触发）
                        if let old, old != new {
                            Task { await saveIfNeeded(field: old) }
                        }
                        lastFocusedField = new
                        
                        if let new {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(new, anchor: .center)
                            }
                        }
                    }
                }
                .opacity(authStore.isLoadingUserInfo ? 0.15 : 1.0)
                .allowsHitTesting(!authStore.isLoadingUserInfo)

                // 全屏 Loading：GET 用户信息期间覆盖整个 sheet
                if authStore.isLoadingUserInfo {
                    loadingOverlay
                }
            }
            .navigationTitle("个人中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        focusedField = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        if let lastFocusedField {
                            Task { await saveIfNeeded(field: lastFocusedField) }
                        }
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black.opacity(0.8))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if authStore.isUpdatingUserInfo {
                        ProgressView()
                    }
                    Button("完成") {
                        focusedField = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .alert("确认退出？", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    Task {
                        await authStore.logoutAsync(clearPhone: false)
                        appState.showSettings = false
                        dismiss()
                    }
                }
            } message: {
                Text("退出后需重新输入验证码登录。")
            }
            .alert("更新失败", isPresented: $showUpdateError) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(updateErrorMessage)
            }
            .alert("确认注销？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) { }
                Button("确认注销", role: .destructive) {
                    Task {
                        let success = await authStore.deactivateAccount()
                        if success {
                            appState.showSettings = false
                            dismiss()
                        } else {
                            deleteErrorMessage = authStore.lastError ?? "注销失败，请稍后再试"
                            showDeleteError = true
                        }
                    }
                }
            } message: {
                Text("注销将永久删除账号与服务端数据，且不可恢复。")
            }
            .onAppear {
                if authStore.userInfo == nil {
                    Task { await authStore.fetchCurrentUserInfoRaw(forceRefresh: false) }
                }
            }
            .onChange(of: authStore.userInfo?.id) { _, _ in
                syncDraftFromUserInfo()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard
                    let userInfo = note.userInfo,
                    let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
                else { return }
                
                let screenH = UIScreen.main.bounds.height
                let overlap = max(0, screenH - endFrame.origin.y)
                
                withAnimation(.easeOut(duration: duration)) {
                    keyboardHeight = overlap
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                withAnimation(.easeOut(duration: duration)) {
                    keyboardHeight = 0
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var userInfoHeader: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.white)
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.black.opacity(0.2))
                )
            
            VStack(spacing: 4) {
                Text((authStore.userInfo?.username?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "圆圆的用户")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
                
                Text(authStore.phone)
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.4))
            }
        }
        .padding(.vertical, 10)
    }
    
    private func infoSection(userInfo: UserInfo, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("账户信息")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .padding(.leading, 12)
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                editableRow(
                    id: .username,
                    label: "昵称",
                    text: $draftUsername,
                    placeholder: "未填写",
                    keyboardType: .default,
                    submitLabel: .next,
                    onSubmit: { focusedField = .email }
                )
                Divider().padding(.horizontal, 16)
                editableRow(
                    id: .email,
                    label: "邮箱",
                    text: $draftEmail,
                    placeholder: "未绑定",
                    keyboardType: .emailAddress,
                    submitLabel: .next,
                    textContentType: .emailAddress,
                    onSubmit: { focusedField = .wechat }
                )
                Divider().padding(.horizontal, 16)
                editableRow(
                    id: .wechat,
                    label: "微信",
                    text: $draftWechat,
                    placeholder: "未绑定",
                    keyboardType: .default,
                    submitLabel: .next,
                    onSubmit: { focusedField = .city }
                )
                Divider().padding(.horizontal, 16)
                editableRow(
                    id: .city,
                    label: "城市",
                    text: $draftCity,
                    placeholder: "未知",
                    keyboardType: .default,
                    submitLabel: .next,
                    onSubmit: { focusedField = .address }
                )
                Divider().padding(.horizontal, 16)
                editableRow(
                    id: .address,
                    label: "地址",
                    text: $draftAddress,
                    placeholder: "未填写",
                    keyboardType: .default,
                    submitLabel: .next,
                    onSubmit: { focusedField = .company }
                )
                Divider().padding(.horizontal, 16)
                editableRow(
                    id: .company,
                    label: "公司",
                    text: $draftCompany,
                    placeholder: "未填写",
                    keyboardType: .default,
                    submitLabel: .next,
                    onSubmit: { focusedField = .industry }
                )
                Divider().padding(.horizontal, 16)
                editableRow(
                    id: .industry,
                    label: "行业",
                    text: $draftIndustry,
                    placeholder: "未填写",
                    keyboardType: .default,
                    submitLabel: .done,
                    onSubmit: { focusedField = nil }
                )
                Divider().padding(.horizontal, 16)
                infoRow(label: "注册时间", value: formatDateTime(userInfo.createdAt))
            }
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
            .onAppear {
                syncDraftFromUserInfo()
            }
        }
    }

    private var infoSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("账户信息")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .padding(.leading, 12)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                infoRow(label: "邮箱", value: "—")
                Divider().padding(.horizontal, 16)
                infoRow(label: "微信", value: "—")
                Divider().padding(.horizontal, 16)
                infoRow(label: "城市", value: "—")
                Divider().padding(.horizontal, 16)
                infoRow(label: "地址", value: "—")
                Divider().padding(.horizontal, 16)
                infoRow(label: "公司", value: "—")
                Divider().padding(.horizontal, 16)
                infoRow(label: "行业", value: "—")
                Divider().padding(.horizontal, 16)
                infoRow(label: "注册时间", value: "—")
            }
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
        .redacted(reason: .placeholder)
        .shimmering(active: true)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.06)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
            )
        }
        .transition(.opacity)
    }
    
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("应用设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .padding(.leading, 12)
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                Button(action: {
                    HapticFeedback.light()
                    openShortcutURL()
                }) {
                    HStack {
                        Image(systemName: "plus.app.fill")
                            .foregroundColor(.black.opacity(0.7))
                            .font(.system(size: 18))
                        Text("添加快捷指令")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black.opacity(0.8))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black.opacity(0.15))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
            }
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }
    
    private var dangerSection: some View {
        HStack(spacing: 12) {
            Button {
                HapticFeedback.medium()
                showLogoutConfirm = true
            } label: {
                Text("退出登录")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
            }

            Button {
                HapticFeedback.medium()
                showDeleteConfirm = true
            } label: {
                Text("注销账号")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
            }
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
    
    private func editableRow(
        id: Field,
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType,
        submitLabel: SubmitLabel,
        textContentType: UITextContentType? = nil,
        onSubmit: @escaping () -> Void
    ) -> some View {
        let isEditing = focusedField == id
        let displayValue = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = displayValue.isEmpty ? placeholder : displayValue
        
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.6))
            
            Spacer()
            
            ZStack(alignment: .trailing) {
                // 展示态
                Text(displayText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(displayValue.isEmpty ? .black.opacity(0.35) : .black.opacity(0.85))
                    .opacity(isEditing ? 0 : 1)
                
                // 编辑态
                TextField("", text: text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.black.opacity(0.85))
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .multilineTextAlignment(.trailing)
                    .opacity(isEditing ? 1 : 0)
                    .focused($focusedField, equals: id)
                    .submitLabel(submitLabel)
                    .onSubmit {
                        Task { await saveIfNeeded(field: id) }
                        onSubmit()
                    }
                    .onChange(of: isEditing) { _, nowEditing in
                        // 从编辑态退出（包括点空白/滑动收键盘）也保存
                        if !nowEditing {
                            Task { await saveIfNeeded(field: id) }
                        }
                    }
                    .ifLet(textContentType) { view, ct in
                        view.textContentType(ct)
                    }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = id
        }
        .id(id)
    }
    
    // MARK: - Helpers
    
    private func syncDraftFromUserInfo() {
        guard let userInfo = authStore.userInfo else { return }
        // 避免正在编辑时被覆盖
        if focusedField != nil { return }
        
        draftUsername = userInfo.username ?? ""
        draftEmail = userInfo.email ?? ""
        draftWechat = userInfo.wechat ?? ""
        draftCity = userInfo.city ?? ""
        draftAddress = userInfo.address ?? ""
        draftCompany = userInfo.company ?? ""
        draftIndustry = userInfo.industry ?? ""
    }
    
    private func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func currentValue(for field: Field) -> String {
        let u = authStore.userInfo
        switch field {
        case .username: return normalized(u?.username ?? "")
        case .email: return normalized(u?.email ?? "")
        case .wechat: return normalized(u?.wechat ?? "")
        case .city: return normalized(u?.city ?? "")
        case .address: return normalized(u?.address ?? "")
        case .company: return normalized(u?.company ?? "")
        case .industry: return normalized(u?.industry ?? "")
        }
    }
    
    private func draftValue(for field: Field) -> String {
        switch field {
        case .username: return normalized(draftUsername)
        case .email: return normalized(draftEmail)
        case .wechat: return normalized(draftWechat)
        case .city: return normalized(draftCity)
        case .address: return normalized(draftAddress)
        case .company: return normalized(draftCompany)
        case .industry: return normalized(draftIndustry)
        }
    }
    
    private func patchKey(for field: Field) -> String {
        switch field {
        case .username: return "username"
        case .email: return "email"
        case .wechat: return "wechat"
        case .city: return "city"
        case .address: return "address"
        case .company: return "company"
        case .industry: return "industry"
        }
    }
    
    private func saveIfNeeded(field: Field) async {
        guard authStore.userInfo != nil else { return }
        let before = currentValue(for: field)
        let after = draftValue(for: field)
        guard before != after else { return }
        
        var patch: [String: Any] = [:]
        if after.isEmpty {
            patch[patchKey(for: field)] = NSNull()
        } else {
            patch[patchKey(for: field)] = after
        }
        
        let ok = await authStore.updateUserInfo(patch: patch)
        if !ok {
            updateErrorMessage = authStore.updateUserInfoError ?? "更新失败，请稍后再试"
            showUpdateError = true
            // 失败时回滚草稿到当前服务端值，避免 UI 状态漂移
            await MainActor.run {
                let serverValue = currentValue(for: field)
                switch field {
                case .username: draftUsername = serverValue
                case .email: draftEmail = serverValue
                case .wechat: draftWechat = serverValue
                case .city: draftCity = serverValue
                case .address: draftAddress = serverValue
                case .company: draftCompany = serverValue
                case .industry: draftIndustry = serverValue
                }
            }
        }
    }
    
    
    
    private func formatDateTime(_ isoString: String?) -> String {
        guard let isoString = isoString else { return "未知" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy/MM/dd"
            return displayFormatter.string(from: date)
        }
        // 如果标准的 ISO8601 失败，尝试处理带 6 位微秒的情况
        let customFormatter = DateFormatter()
        customFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = customFormatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy/MM/dd"
            return displayFormatter.string(from: date)
        }
        return isoString.prefix(10).replacingOccurrences(of: "-", with: "/")
    }
    
    private func openShortcutURL() {
        if let url = URL(string: "https://www.icloud.com/shortcuts/a9114a98c4ef48c698c5279d6c6f5585") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Lightweight Shimmer (no dependencies)
private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        if !active {
            content
        } else {
            content
                .overlay(
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.0), location: 0.0),
                                .init(color: .white.opacity(0.35), location: 0.5),
                                .init(color: .white.opacity(0.0), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .rotationEffect(.degrees(20))
                        .frame(width: w * 0.55)
                        .offset(x: w * phase)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .onAppear {
                            phase = -0.6
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                phase = 1.4
                            }
                        }
                    }
                )
        }
    }
}

private extension View {
    func shimmering(active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
    
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(AuthStore())
}
