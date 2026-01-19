import SwiftUI
import UIKit

// 设置页面 - 包含快捷指令配置
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var authStore: AuthStore
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.black.opacity(0.04))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.black.opacity(0.45))
                            )
                        
                        Text(greetingText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black.opacity(0.85))
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    Button(action: {
                        HapticFeedback.medium()
                        openShortcutURL()
                    }) {
                        actionRow(title: "添加快捷指令", systemImage: "plus.app.fill", tint: .black.opacity(0.8))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, 20)
                    
                    HStack(spacing: 10) {
                        Button {
                            HapticFeedback.medium()
                            showLogoutConfirm = true
                        } label: {
                            actionTile(title: "退出登录", systemImage: "rectangle.portrait.and.arrow.right", tint: .black.opacity(0.7))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        Button {
                            HapticFeedback.medium()
                            showDeleteConfirm = true
                        } label: {
                            actionTile(title: "注销账号", systemImage: "person.badge.minus", tint: .red.opacity(0.75))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("个人中心")
            .navigationBarTitleDisplayMode(.inline)
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
                        await authStore.logoutAsync(clearPhone: true)
                        appState.showSettings = false
                        dismiss()
                    }
                }
            } message: {
                Text("注销将彻底清除本地数据和登录信息。")
            }
        }
    }
    
    private var greetingText: String {
        let p = authStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = p.count >= 4 ? String(p.suffix(4)) : "访客"
        return "圆圆的主人 (\(suffix))"
    }

    @ViewBuilder
    private func actionRow(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.2))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func actionTile(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func openShortcutURL() {
        if let url = URL(string: "https://www.icloud.com/shortcuts/a9114a98c4ef48c698c5279d6c6f5585") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(AuthStore())
}

