import SwiftUI
import UIKit

// 设置页面 - 包含快捷指令配置
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var authStore: AuthStore
    @State private var showLogoutConfirm = false
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)

    var body: some View {
        ZStack {
            // 背景渐变
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 20) {
                    Text(greetingText)
                        .font(.custom("SourceHanSerifSC-Bold", size: 18))
                        .foregroundColor(.black.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, 30)
                        .padding(.horizontal, 24)

                    ShortcutActionButton(themeColor: themeColor)
                        .padding(.horizontal, 24)
                    
                    Button {
                        HapticFeedback.medium()
                        showLogoutConfirm = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18, weight: .bold))
                            Text("退出登录")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LiquidGlassCapsuleBackground())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
        .alert("确认退出登录？", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) { }
            Button("退出登录", role: .destructive) {
                Task {
                    await authStore.logoutAsync()
                    appState.showSettings = false
                    dismiss()
                }
            }
        } message: {
            Text("退出后将清除本地登录 token。")
        }
    }
    
    private var greetingText: String {
        let p = authStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = p.count >= 4 ? String(p.suffix(4)) : p
        if suffix.isEmpty {
            return "尊贵的主人，使用 MolyMemo 还愉快吗？"
        }
        return "尊贵的主人\(suffix)，使用 MolyMemo 还愉快吗？"
    }
}

// 聊天后端设置按钮
struct BackendSettingsButton: View {
    @Binding var showBackendSettings: Bool
    let themeColor: Color
    
    var body: some View {
        Button(action: {
            HapticFeedback.medium()
            showBackendSettings = true
        }) {
            LiquidGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(themeColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("聊天后端")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                        Text("配置后端接口（Apifox）")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// 飞书日历设置按钮
struct FeishuSettingsButton: View {
    @Binding var showFeishuSettings: Bool
    let themeColor: Color

    var body: some View {
        Button(action: {
            HapticFeedback.medium()
            showFeishuSettings = true
        }) {
            LiquidGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(themeColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("飞书日历")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                        Text("同步飞书日历到本地")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// 公司开票信息设置按钮
struct CompanySettingsButton: View {
    @Binding var showCompanySettings: Bool
    let themeColor: Color

    var body: some View {
        Button(action: {
            HapticFeedback.medium()
            showCompanySettings = true
        }) {
            LiquidGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(themeColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("开票信息设置")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                        Text("设置公司抬头，自动开票")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// 快捷指令按钮组件
struct ShortcutActionButton: View {
    @State private var showCopyAlert = false
    let themeColor: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                HapticFeedback.medium()
                openShortcutURL()
            }) {
                LiquidGlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.app.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(themeColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("添加快捷指令")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.black.opacity(0.85))
                            Text("一键打开并添加到「快捷指令」App")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(themeColor)
                    }
                }
            }
            .buttonStyle(ScaleButtonStyle())
            
            Text("点击后会打开 iCloud 快捷指令页面，点「获取捷径/添加」即可")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black.opacity(0.4))
                .padding(.horizontal, 4)
        }
        .alert("无法打开", isPresented: $showCopyAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("请确保已安装「快捷指令」App")
        }
    }
    
    private func openShortcutURL() {
        // 打开快捷指令链接，一键添加
        if let url = URL(string: "https://www.icloud.com/shortcuts/a9114a98c4ef48c698c5279d6c6f5585") {
            UIApplication.shared.open(url) { success in
                if !success {
                    showCopyAlert = true
                }
            }
        } else {
            showCopyAlert = true
        }
    }
}

// 步骤说明组件
struct SetupInstructionsView: View {
    let themeColor: Color
    
    var body: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 20) {
                // 标题
                HStack(spacing: 10) {
                    Image(systemName: "list.number")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(themeColor)
                    Text("设置步骤")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                }
                .padding(.bottom, 4)
                
                // 步骤列表
                VStack(spacing: 16) {
                    InstructionStep(
                        number: 1,
                        title: "添加快捷指令",
                        description: "点击上方按钮，在打开的页面中点击「添加快捷指令」",
                        icon: "plus.square.fill",
                        themeColor: themeColor
                    )
                    
                    InstructionStep(
                        number: 2,
                        title: "打开系统设置",
                        description: "前往：设置 → 辅助功能 → 触控 → 背面轻点",
                        icon: "gearshape.fill",
                        themeColor: themeColor
                    )
                    
                    InstructionStep(
                        number: 3,
                        title: "配置手势",
                        description: "选择「轻点两下」或「轻点三下」，然后选择刚添加的快捷指令",
                        icon: "hand.tap.fill",
                        themeColor: themeColor
                    )
                    
                    InstructionStep(
                        number: 4,
                        title: "开始使用",
                        description: "轻点手机背面即可截图并自动发送给小助手分析",
                        icon: "checkmark.circle.fill",
                        themeColor: themeColor,
                        isLast: true
                    )
                }
            }
        }
    }
}

// 单个步骤组件
struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    let themeColor: Color
    var isLast: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 步骤数字
            ZStack {
                Circle()
                    .fill(themeColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Text("\(number)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.7))
            }
            
            // 内容
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeColor.opacity(0.8))
                    
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                }
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, isLast ? 0 : 8)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(AuthStore())
}

