import SwiftUI

/// 自有后端聊天设置
struct BackendSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var enabled: Bool = BackendChatConfig.isEnabled
    @State private var baseURL: String = BackendChatConfig.baseURL
    @State private var apiKey: String = BackendChatConfig.apiKey
    @State private var model: String = BackendChatConfig.model
    @State private var shortcut: String = BackendChatConfig.shortcut
    
    @State private var showSavedToast: Bool = false
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    var body: some View {
        ZStack {
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            Color.clear.frame(height: 4)
                            
                            LiquidGlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "server.rack")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(themeColor)
                                        
                                        Text("聊天后端")
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundColor(.black.opacity(0.85))
                                        
                                        Spacer()
                                        
                                        Toggle("", isOn: $enabled)
                                            .labelsHidden()
                                            .tint(themeColor)
                                    }
                                    
                                    Text("开启后，聊天会走后端接口（不回退到内置模型）。")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.black.opacity(0.55))
                                }
                            }
                            
                            LiquidGlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("接口配置")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundColor(.black.opacity(0.85))
                                    
                                    field(title: "Base URL", placeholder: "例如：https://api.xxx.com", text: $baseURL, isSecure: false)
                                    field(title: "API Key（可选）", placeholder: "Bearer Token", text: $apiKey, isSecure: true)
                                    field(title: "Model（可选）", placeholder: "由后端默认可不填", text: $model, isSecure: false)
                                    field(title: "Shortcut（可选）", placeholder: "例如：创建日程", text: $shortcut, isSecure: false)
                                    
                                    HStack(spacing: 10) {
                                        Button {
                                            HapticFeedback.light()
                                            baseURL = BackendChatConfig.defaultBaseURL
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "wand.and.stars")
                                                    .font(.system(size: 14, weight: .semibold))
                                                Text("填入测试地址")
                                                    .font(.system(size: 14, weight: .semibold))
                                            }
                                            .foregroundColor(.black.opacity(0.65))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(GlassButtonBackground())
                                        }
                                        .buttonStyle(ScaleButtonStyle())
                                        
                                        Spacer()
                                    }
                                    
                                    if let url = BackendChatConfig.endpointURL(fromBase: baseURL, path: BackendChatConfig.path) {
                                        Text("最终地址：\(url.absoluteString)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black.opacity(0.5))
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text("最终地址：—")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.black.opacity(0.35))
                                    }
                                }
                            }
                            
                            Button {
                                HapticFeedback.medium()
                                save()
                                showSavedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                                    showSavedToast = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("保存")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.black.opacity(0.75))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LiquidGlassCapsuleBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Spacer(minLength: 24)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                ModuleNavigationBar(
                    title: "聊天后端",
                    themeColor: themeColor,
                    onBack: { dismiss() }
                )
                
                if showSavedToast {
                    Text("已保存")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                        .padding(.vertical, 8)
                } else {
                    Color.clear.frame(height: 8)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    
    @ViewBuilder
    private func field(title: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black.opacity(0.6))
            
            if isSecure {
                SecureField(placeholder, text: text)
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
            } else {
                TextField(placeholder, text: text)
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
    }
    
    private func save() {
        BackendChatConfig.isEnabled = enabled
        BackendChatConfig.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        BackendChatConfig.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        BackendChatConfig.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        BackendChatConfig.shortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension BackendChatConfig {
    static func endpointURL(fromBase base: String, path: String) -> URL? {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBase = BackendChatConfig.normalizeBaseURL(trimmedBase)
        guard !normalizedBase.isEmpty else { return nil }
        
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = p.isEmpty ? "" : (p.hasPrefix("/") ? p : "/" + p)
        
        return URL(string: normalizedBase + normalizedPath)
    }
}

#Preview {
    BackendSettingsView()
}


