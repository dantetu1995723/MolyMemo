import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore
    private let themeColor = Color(white: 0.55)
    
    var body: some View {
        ZStack {
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 16) {
                    Spacer(minLength: 40)
                    
                    LiquidGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            field(
                                placeholder: "请输入手机号",
                                text: $authStore.phone,
                                keyboard: .phonePad
                            )
                            
                            if let err = authStore.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.red.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Button {
                        HapticFeedback.medium()
                        Task { await authStore.login() }
                    } label: {
                        HStack(spacing: 10) {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(.black.opacity(0.7))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            
                            Text(authStore.isLoading ? "登录中…" : "登录")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LiquidGlassCapsuleBackground())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(authStore.isLoading)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    
    @ViewBuilder
    private func field(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
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

#Preview {
    LoginView()
        .environmentObject(AuthStore())
}


