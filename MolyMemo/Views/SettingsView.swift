import SwiftUI
import UIKit

// 设置页面 - 简约白色现代风
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var authStore: AuthStore
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.98).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 用户信息头部
                        userInfoHeader
                        
                        // 用户详细信息卡片
                        if let userInfo = authStore.userInfo {
                            infoSection(userInfo: userInfo)
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
                    .padding(.bottom, 30)
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
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black.opacity(0.8))
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
                Text(authStore.userInfo?.username ?? "圆圆的用户")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
                
                Text(authStore.phone)
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.4))
            }
        }
        .padding(.vertical, 10)
    }
    
    private func infoSection(userInfo: UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("账户信息")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .padding(.leading, 12)
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                infoRow(label: "邮箱", value: userInfo.email ?? "未绑定")
                Divider().padding(.horizontal, 16)
                infoRow(label: "微信", value: userInfo.wechat ?? "未绑定")
                Divider().padding(.horizontal, 16)
                infoRow(label: "城市", value: userInfo.city ?? "未知")
                Divider().padding(.horizontal, 16)
                infoRow(label: "地址", value: userInfo.address ?? "未填写")
                Divider().padding(.horizontal, 16)
                infoRow(label: "公司", value: userInfo.company ?? "未填写")
                Divider().padding(.horizontal, 16)
                infoRow(label: "行业", value: userInfo.industry ?? "未填写")
                Divider().padding(.horizontal, 16)
                infoRow(label: "注册时间", value: formatDateTime(userInfo.createdAt))
            }
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
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
    
    // MARK: - Helpers
    
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
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(AuthStore())
}
