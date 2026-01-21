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
    @AppStorage("yy_legal_agreement_accepted") private var hasAcceptedLegalAgreement: Bool = false
    @State private var showPrivacyPolicy: Bool = false
    @State private var showTermsOfService: Bool = false
    @State private var showAgreementAlert: Bool = false
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
                .zIndex(0)
            
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
                
                // 底部协议勾选区
                if !isCompact {
                    agreementSection
                        .padding(.horizontal, 32)
                }
            }
            .safeAreaPadding(.bottom, isCompact ? 0 : 20)
            .padding(.bottom, isCompact ? bottomAvoid : 0)
            .offset(y: isCompact ? -contentLift : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: keyboardHeight)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: loginMode)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showCodeInput)
            .safeAreaPadding(.top, 20)
            .zIndex(1)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentView(title: "隐私政策", bodyText: Self.privacyPolicyText)
        }
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentView(title: "服务条款", bodyText: Self.termsOfServiceText)
        }
        .alert("用户协议", isPresented: $showAgreementAlert) {
            Button("同意") {
                hasAcceptedLegalAgreement = true
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("登录即表示您已阅读并同意《隐私政策》和《服务条款》，我们将依法保护您的个人信息安全。")
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
                            guard hasAcceptedLegalAgreement else {
                                HapticFeedback.light()
                                showAgreementAlert = true
                                return
                            }
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
            guard hasAcceptedLegalAgreement else {
                HapticFeedback.light()
                showAgreementAlert = true
                return
            }
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
    
    private var agreementSection: some View {
        HStack(spacing: 2) {
            Button {
                HapticFeedback.light()
                hasAcceptedLegalAgreement.toggle()
            } label: {
                Image(systemName: hasAcceptedLegalAgreement ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(hasAcceptedLegalAgreement ? .black.opacity(0.7) : .black.opacity(0.35))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            
            Text("我已阅读并同意")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.55))
            
            Button {
                showPrivacyPolicy = true
            } label: {
                Text("隐私政策")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black.opacity(0.75))
            }
            
            Text("和")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.55))
            
            Button {
                showTermsOfService = true
            } label: {
                Text("服务条款")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black.opacity(0.75))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var canSubmit: Bool {
        let p = authStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = authStore.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !authStore.isLoading && !p.isEmpty && !c.isEmpty
    }
    
    private static let privacyPolicyText: String = """
    更新日期：2026-01-20

    欢迎使用 MolyMemo。我们非常重视你的个人信息与隐私保护。本政策用于说明我们在你使用本应用及相关服务时，如何收集、使用、存储、共享与保护你的信息，以及你享有的权利。

    一、我们收集的信息
    1. 账户与登录信息：手机号、验证码（仅用于登录校验）。
    2. 设备与日志信息：设备型号、系统版本、应用版本、必要的诊断日志（用于安全与稳定性分析）。
    3. 你主动提供的内容：你输入的文字、上传的图片/文件、录音与语音转文字内容（用于提供核心功能与同步）。
    4. 其他：为实现特定功能所需的权限相关信息（如麦克风、相册、文件访问），仅在你授权后使用。

    二、我们如何使用信息
    1. 提供与改进服务：登录、数据同步、生成内容、功能优化与故障排查。
    2. 安全保障：识别异常、反作弊与保护账号安全。
    3. 合规与必要通知：依据法律法规或监管要求进行必要处理。

    三、信息共享与披露
    1. 我们不会出售你的个人信息。
    2. 为实现服务所必需，我们可能与第三方服务提供方共享必要信息（例如：短信验证码服务、云存储/网络服务、崩溃分析服务），并要求其按本政策与法律法规处理。
    3. 在法律法规要求或为保护你与他人合法权益的情况下，我们可能依法披露。

    四、信息存储与保护
    1. 我们采用合理的安全措施（加密存储、访问控制等）保护信息安全。
    2. 你的登录态信息可能存储在系统钥匙串（Keychain）与本地偏好设置中，用于保持登录状态。

    五、你的权利
    你可以在合理范围内访问、更正、删除你的信息，或注销账号。你也可以撤回权限授权（撤回后可能影响相关功能使用）。

    六、联系我们
    如你对本政策有任何疑问、意见或投诉建议，请在应用内与我们联系（或通过你获取应用的渠道联系我们）。
    """
    
    private static let termsOfServiceText: String = """
    更新日期：2026-01-20

    欢迎使用 MolyMemo。你在使用本应用前，应当阅读并同意本服务条款。你开始使用或登录，即表示你已理解并同意本条款的全部内容。

    一、服务内容
    MolyMemo 向你提供包括但不限于：登录与账号服务、内容输入/整理、语音转文字、图片/文件处理、数据同步与相关功能。

    二、账号与使用规范
    1. 你应当遵守法律法规与公序良俗，不得利用本服务从事违法违规活动。
    2. 你应妥善保管账号信息与登录设备，因你自身原因导致的损失由你自行承担。

    三、内容与权利
    1. 你对你上传/输入的内容依法享有相应权利，并保证你有权提供该等内容。
    2. 为向你提供服务与改进体验，我们可能在必要范围内处理你的内容（例如：生成摘要、分类整理、转写等）。

    四、免责声明与责任限制
    1. 我们将尽力保障服务的稳定与安全，但不对不可抗力、系统故障、网络原因等导致的服务中断承担超出法律规定范围的责任。
    2. 你理解并同意：基于智能生成的内容可能存在不准确或偏差，请你自行判断并对使用结果负责。

    五、条款变更与终止
    1. 我们可能根据业务变化或法律法规要求更新本条款，并在应用内以适当方式提示。
    2. 若你不同意变更内容，应停止使用服务；若你继续使用，则视为接受更新后的条款。

    六、联系我们
    如你对本条款有任何疑问，请在应用内与我们联系。
    """
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

private struct LegalDocumentView: View {
    let title: String
    let bodyText: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.98).ignoresSafeArea()
                ScrollView {
                    Text(bodyText)
                        .font(.system(size: 15))
                        .foregroundColor(.black.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black.opacity(0.8))
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthStore())
}
