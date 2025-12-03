import SwiftUI
import UIKit

// 设置页面 - 包含快捷指令配置
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showCompanySettings = false
    @State private var showFeishuSettings = false
    
    // 主题色
    private var themeColor: Color {
        YuanyuanTheme.color(at: appState.colorIndex)
    }

    var body: some View {
        ZStack {
            // 背景渐变
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            Color.clear.frame(height: 16)
                            // 标题区域
                            VStack(spacing: 12) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 52))
                                    .foregroundColor(themeColor)
                                    .shadow(color: themeColor.opacity(0.3), radius: 8, x: 0, y: 4)
                                
                                VStack(spacing: 6) {
                                    Text("背面轻点截图")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundColor(.black.opacity(0.85))
                                    
                                    Text("快速分享截图给小助手")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.black.opacity(0.5))
                                }
                            }
                            .padding(.vertical, 8)
                            
                            // 公司开票信息设置按钮
                            CompanySettingsButton(showCompanySettings: $showCompanySettings, themeColor: themeColor)
                            
                            // 飞书日历设置按钮
                            FeishuSettingsButton(showFeishuSettings: $showFeishuSettings, themeColor: themeColor)
                            
                            // 快捷指令按钮
                            ShortcutActionButton(themeColor: themeColor)
                            
                            // 步骤说明
                            SetupInstructionsView(themeColor: themeColor)
                            
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCompanySettings) {
            CompanySettingsView()
                .environmentObject(appState)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFeishuSettings) {
            FeishuSettingsView()
                .environmentObject(appState)
                .presentationDragIndicator(.visible)
        }
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
        VStack(spacing: 16) {
            // 快速使用提示
            LiquidGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(themeColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("现在可以用了！")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black.opacity(0.85))
                        Text("在 Spotlight 搜索「截图分析」即可使用")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                    }
                    
                    Spacer()
                }
            }
            
            // 添加快捷指令按钮
            Button(action: {
                HapticFeedback.medium()
                requestClipboardPermission()
                openShortcutURL()
            }) {
                LiquidGlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.app.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(themeColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("添加到快捷指令")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.black.opacity(0.85))
                            Text("在快捷指令 App 中使用")
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
            
            // 提示文本
            Text("点击后会打开快捷指令页面，点「添加」即可")
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
    
    private func requestClipboardPermission() {
        // 主动检查剪贴板，触发权限请求（只在第一次会弹窗）
        #if os(iOS)
        _ = UIPasteboard.general.hasImages
        print("✅ 已触发剪贴板权限请求")
        #endif
    }
    
    private func openShortcutURL() {
        // 打开快捷指令链接，一键添加
        if let url = URL(string: "https://www.icloud.com/shortcuts/6aa2c8b9e727472ab1483649873ce13e") {
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
}

