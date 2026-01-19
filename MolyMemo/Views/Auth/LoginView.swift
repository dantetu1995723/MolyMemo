import SwiftUI
import UIKit

struct TypingSloganView: View {
    let fullText: String
    @State private var displayedText: String = ""
    @State private var currentIndex: Int = 0
    @State private var cursorVisible: Bool = true
    
    let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            Text(displayedText)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            // 闪烁光标
            Rectangle()
                .fill(Color.black.opacity(0.65))
                .frame(width: 2.5, height: 26)
                .opacity(cursorVisible ? 1 : 0)
        }
        .onReceive(timer) { _ in
            handleTyping()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
        }
    }
    
    private func handleTyping() {
        if currentIndex < fullText.count {
            let index = fullText.index(fullText.startIndex, offsetBy: currentIndex)
            displayedText.append(fullText[index])
            currentIndex += 1
            
            if currentIndex == fullText.count {
                // 刚完成打字，停留一会儿后直接重置重新开始
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    displayedText = ""
                    currentIndex = 0
                }
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore
    private let themeColor = Color(white: 0.55)
    @State private var keyboardHeight: CGFloat = 0
    @State private var loginMode: LoginMode = .manual
    @State private var showCodeInput: Bool = false
    @FocusState private var focusedField: FocusField?

    enum LoginMode {
        case quick
        case manual
    }

    enum FocusField {
        case phone
        case code
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func updateKeyboardHeight(_ note: Notification) {
        guard let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screenHeight = UIScreen.main.bounds.height
        keyboardHeight = max(0, screenHeight - endFrame.minY)
    }
    
    var body: some View {
        let isCompact = keyboardHeight > 0
        let contentLift = min(48, keyboardHeight * 0.16)
        let bottomAvoid = min(90, keyboardHeight * 0.28)
        
        ZStack {
            // 背景保持 App 统一的极简灰色渐变
            ModuleBackgroundView(themeColor: themeColor)
                .onTapGesture { dismissKeyboard() }
            
            VStack(spacing: 0) {
                // 整体上移：减小顶部 Spacer 并在非压缩状态下应用负 Offset
                Spacer(minLength: isCompact ? 0 : 30)
                
                VStack(spacing: 0) {
                    // 1. App 大图标 - 图标缩小幅度减小
                    Image("molymemo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isCompact ? 110 : 180, height: isCompact ? 110 : 180)
                        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 28 : 42, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 25, x: 0, y: 15)
                        .padding(.bottom, isCompact ? 12 : 10)
                    
                    // 2. 标题与打字机动画欢迎语
                    if loginMode != .quick && !isCompact {
                        TypingSloganView(fullText: "MolyMemo让记忆不被埋没")
                            .frame(height: 32)
                            .padding(.bottom, 40)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if loginMode == .quick && !isCompact {
                        // 一键登录模式且键盘未弹起时，保留图标下方的间距
                        Spacer().frame(height: 20)
                    }
                    
                    if loginMode == .quick && authStore.rememberedPhone != nil {
                        quickLoginView
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)), removal: .opacity.combined(with: .move(edge: .trailing))))
                    } else {
                        manualLoginView
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity.combined(with: .move(edge: .leading))))
                    }
                }
                .offset(y: isCompact ? 0 : -20) // 整体视觉上移
                
                Spacer()
            }
            .padding(.bottom, isCompact ? bottomAvoid : 0)
            .offset(y: isCompact ? -contentLift : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: keyboardHeight)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: loginMode)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showCodeInput)
            .safeAreaPadding(.top, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if authStore.rememberedPhone != nil {
                loginMode = .quick
            } else {
                loginMode = .manual
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            updateKeyboardHeight(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    // MARK: - 一键登录视图
    private var quickLoginView: some View {
        VStack(spacing: 24) { // 统一大组间距
            // 上次登录号码卡片
            VStack(spacing: 8) { // 统一标签间距
                Text(authStore.maskedPhone)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))
                
                Text("上次登录的号码")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            )
            .padding(.horizontal, 32)
            
            if showCodeInput {
                VStack(spacing: 16) { // 统一小组间距
                    LoginGlassFieldWithTrailing(
                        placeholder: "请输入验证码",
                        text: $authStore.verificationCode,
                        keyboard: .numberPad,
                        contentType: .oneTimeCode
                    ) {
                        Button {
                            HapticFeedback.light()
                            Task { await authStore.sendVerificationCode() }
                        } label: {
                            Text(authStore.sendCountdown > 0 ? "\(authStore.sendCountdown)s" : "重新获取")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black.opacity(0.75))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.6))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(authStore.isSendingCode || authStore.sendCountdown > 0)
                        .opacity(authStore.isSendingCode || authStore.sendCountdown > 0 ? 0.6 : 1.0)
                    }
                    .focused($focusedField, equals: .code)
                    
                    loginButton
                    
                    Button {
                        withAnimation {
                            showCodeInput = false
                            authStore.verificationCode = ""
                        }
                    } label: {
                        Text("返回")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
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
                }
                .padding(.horizontal, 32)
            } else {
                VStack(spacing: 16) { // 统一小组间距
                    Button {
                        HapticFeedback.medium()
                        Task {
                            await authStore.quickLogin()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(.black.opacity(0.7))
                            } else {
                                Image(systemName: "iphone.radiowaves.left.and.right")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            Text("一键登录")
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
                    .disabled(authStore.isLoading)
                    
                    Button {
                        withAnimation {
                            loginMode = .manual
                            authStore.phone = ""
                        }
                    } label: {
                        Text("使用其他号码登录")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
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
                }
                .padding(.horizontal, 32)
            }
            
            if let err = authStore.lastError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.horizontal, 36)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - 手动登录视图
    private var manualLoginView: some View {
        VStack(spacing: 24) { // 统一大组间距
            VStack(spacing: 16) { // 统一小组间距
                LoginGlassFieldWithTrailing(
                    placeholder: "请输入手机号",
                    text: $authStore.phone,
                    keyboard: .phonePad,
                    contentType: .telephoneNumber
                ) {
                    let trimmedPhone = authStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedPhone.isEmpty {
                        Button {
                            HapticFeedback.light()
                            Task { await authStore.sendVerificationCode() }
                        } label: {
                            Text(authStore.sendCountdown > 0 ? "\(authStore.sendCountdown)s" : "获取验证码")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black.opacity(0.75))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.6))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(authStore.isSendingCode || authStore.sendCountdown > 0)
                        .opacity(authStore.isSendingCode || authStore.sendCountdown > 0 ? 0.6 : 1.0)
                    }
                }
                .focused($focusedField, equals: .phone)
                
                LoginGlassField(
                    placeholder: "请输入验证码",
                    text: $authStore.verificationCode,
                    keyboard: .numberPad,
                    contentType: .oneTimeCode
                )
                .focused($focusedField, equals: .code)
                
                if let err = authStore.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 32)
            
            VStack(spacing: 16) { // 统一小组间距
                loginButton
                
                if authStore.rememberedPhone != nil {
                    Button {
                        withAnimation {
                            loginMode = .quick
                            authStore.phone = authStore.rememberedPhone ?? ""
                        }
                    } label: {
                        Text("返回一键登录")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
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
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private var loginButton: some View {
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

// MARK: - 带右侧按钮的输入框
struct LoginGlassFieldWithTrailing<Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    var contentType: UITextContentType? = nil
    let trailing: Trailing

    init(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        contentType: UITextContentType? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.placeholder = placeholder
        self._text = text
        self.keyboard = keyboard
        self.contentType = contentType
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
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
