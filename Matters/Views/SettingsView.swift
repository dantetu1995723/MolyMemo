import SwiftUI
import UIKit

// 设置页面 - 包含快捷指令配置
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showCompanySettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 标题区域
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 1.0, blue: 0.25),
                                        Color(red: 0.75, green: 0.95, blue: 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 20)

                        Text("背面轻点截图")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))

                        Text("快速分享截图给小助手")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .padding(.bottom, 8)

                    // 🆕 公司开票信息设置按钮
                    CompanySettingsButton(showCompanySettings: $showCompanySettings)

                    // 快捷指令按钮
                    ShortcutActionButton()

                    // 步骤说明
                    SetupInstructionsView()

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.94))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticFeedback.light()
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                            Text("返回")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.black)
                    }
                }
            }
            .sheet(isPresented: $showCompanySettings) {
                CompanySettingsView()
            }
        }
    }
}

// 🆕 公司开票信息设置按钮
struct CompanySettingsButton: View {
    @Binding var showCompanySettings: Bool

    var body: some View {
        Button(action: {
            HapticFeedback.medium()
            showCompanySettings = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20, weight: .bold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("开票信息设置")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("设置公司抬头，自动开票")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.7)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0.5)
            }
            .foregroundColor(.black.opacity(0.85))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 快捷指令按钮组件
struct ShortcutActionButton: View {
    @State private var showCopyAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            // 快速使用提示
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 0.5, green: 0.7, blue: 0.1))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("现在可以用了！")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black.opacity(0.85))
                    Text("在 Spotlight 搜索「截图分析」即可使用")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.15))
            )
            
            // 添加快捷指令按钮
            Button(action: {
                HapticFeedback.medium()
                // 主动触发剪贴板权限请求（只会在第一次弹窗）
                requestClipboardPermission()
                openShortcutURL()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.app.fill")
                        .font(.system(size: 22, weight: .bold))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("添加到快捷指令")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("在快捷指令 App 中使用")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0.7)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25),
                                    Color(red: 0.75, green: 0.95, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), radius: 12, x: 0, y: 4)
                )
            }
            
            // 提示文本
            Text("点击后会打开快捷指令页面，点「添加」即可")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black.opacity(0.4))
        }
        .padding(.horizontal, 4)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            HStack {
                Image(systemName: "list.number")
                    .font(.system(size: 18, weight: .bold))
                Text("设置步骤")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .foregroundColor(.black.opacity(0.85))
            .padding(.bottom, 4)
            
            // 步骤列表
            VStack(spacing: 16) {
                InstructionStep(
                    number: 1,
                    title: "添加快捷指令",
                    description: "点击上方按钮，在打开的页面中点击「添加快捷指令」",
                    icon: "plus.square.fill"
                )
                
                InstructionStep(
                    number: 2,
                    title: "打开系统设置",
                    description: "前往：设置 → 辅助功能 → 触控 → 背面轻点",
                    icon: "gearshape.fill"
                )
                
                InstructionStep(
                    number: 3,
                    title: "配置手势",
                    description: "选择「轻点两下」或「轻点三下」，然后选择刚添加的快捷指令",
                    icon: "hand.tap.fill"
                )
                
                InstructionStep(
                    number: 4,
                    title: "开始使用",
                    description: "轻点手机背面即可截图并自动发送给小助手分析",
                    icon: "checkmark.circle.fill",
                    isLast: true
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// 单个步骤组件
struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    var isLast: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // 步骤数字
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.2),
                                Color(red: 0.75, green: 0.95, blue: 0.2).opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Text("\(number)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.7, blue: 0.1))
            }
            
            // 内容
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.5, green: 0.7, blue: 0.1))
                    
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

