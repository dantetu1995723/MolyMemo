import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore
    private let themeColor = Color(white: 0.55)
    
    var body: some View {
        ZStack {
            // 背景保持 App 统一的极简灰色渐变
            ModuleBackgroundView(themeColor: themeColor)
            
            VStack(spacing: 0) {
                Spacer(minLength: 40)
                
                // 1. App 大图标
                Image("molymemo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 12)
                    .padding(.bottom, 20)
                
                // 2. 标题与提示
                VStack(spacing: 8) {
                    Text("MolyMemo让记忆不被埋没")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                }
                .padding(.bottom, 36)
                
                // 3. 输入区域 (简化层级)
                VStack(spacing: 16) {
                    LoginGlassField(
                        placeholder: "请输入手机号",
                        text: $authStore.phone,
                        keyboard: .phonePad,
                        contentType: .telephoneNumber
                    )
                    
                    LoginGlassField(
                        placeholder: "请输入验证码",
                        text: $authStore.verificationCode,
                        keyboard: .numberPad,
                        contentType: .oneTimeCode
                    )
                    
                    if let err = authStore.lastError, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                
                // 4. 登录按钮
                Button {
                    HapticFeedback.medium()
                    Task { await authStore.login() }
                } label: {
                    HStack(spacing: 12) {
                        if authStore.isLoading {
                            ProgressView()
                                .tint(.black.opacity(0.7))
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                        }
                        
                        Text(authStore.isLoading ? "正在登录..." : "登录并注册")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.6))
                            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(!canSubmit)
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .safeAreaPadding(.top, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    
    private var canSubmit: Bool {
        let p = authStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = authStore.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !authStore.isLoading && !p.isEmpty && !c.isEmpty
    }
}

// MARK: - 登录页专属组件
struct LoginGlassField: View {
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    var contentType: UITextContentType? = nil
    
    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.black.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthStore())
}


