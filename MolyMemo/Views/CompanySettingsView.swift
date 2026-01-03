import SwiftUI
import SwiftData

// 公司开票信息设置界面
struct CompanySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Query private var companies: [CompanyInfo]
    
    @State private var companyName: String = ""
    @State private var taxNumber: String = ""
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var bankName: String = ""
    @State private var bankAccount: String = ""
    
    @State private var showContent = false
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case companyName, taxNumber, phoneNumber, email, address, bankName, bankAccount
    }
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    // 获取现有的公司信息（如果有）
    private var existingCompany: CompanyInfo? {
        companies.first
    }
    
    var body: some View {
        ZStack {
            // 背景渐变
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 16)
                    
                    // 顶部操作栏
                    HStack {
                        Spacer()
                        Button {
                            HapticFeedback.medium()
                            saveCompanyInfo()
                        } label: {
                            Text("保存")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(isValid ? .black.opacity(0.7) : .black.opacity(0.3))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(LiquidGlassCapsuleBackground())
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(!isValid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    
                    ScrollView(showsIndicators: false) {
                        if showContent {
                            VStack(spacing: 16) {
                                // 说明文字
                                InfoBanner(themeColor: themeColor)
                                
                                // 基本信息卡片（必填）
                                BasicInfoCard(
                                    companyName: $companyName,
                                    taxNumber: $taxNumber,
                                    focusedField: $focusedField,
                                    themeColor: themeColor
                                )
                                
                                // 联系方式卡片（选填）
                                ContactInfoCard(
                                    phoneNumber: $phoneNumber,
                                    email: $email,
                                    focusedField: $focusedField,
                                    themeColor: themeColor
                                )
                                
                                // 详细信息卡片（选填）
                                DetailInfoCard(
                                    address: $address,
                                    bankName: $bankName,
                                    bankAccount: $bankAccount,
                                    focusedField: $focusedField,
                                    themeColor: themeColor
                                )
                                
                                Spacer(minLength: 80)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 34)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadExistingData()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.1)) {
                showContent = true
            }
        }
    }
    
    // 计算深色标题颜色
    private var titleColor: Color {
        let uiColor = UIColor(themeColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.3, 1.0), brightness: brightness * 0.55, opacity: alpha)
    }
    
    // 验证输入（抬头、税号、手机号、邮箱都是必填项）
    private var isValid: Bool {
        !companyName.isEmpty &&
        !taxNumber.isEmpty &&
        !phoneNumber.isEmpty &&
        !email.isEmpty
    }
    
    // 加载现有数据
    private func loadExistingData() {
        if let company = existingCompany {
            companyName = company.companyName
            taxNumber = company.taxNumber ?? ""
            phoneNumber = company.phoneNumber ?? ""
            email = company.email ?? ""
            address = company.address ?? ""
            bankName = company.bankName ?? ""
            bankAccount = company.bankAccount ?? ""
        }
    }
    
    // 保存公司信息
    private func saveCompanyInfo() {
        guard isValid else { return }
        
        HapticFeedback.medium()
        
        if let company = existingCompany {
            // 更新现有信息
            company.companyName = companyName
            company.taxNumber = taxNumber.isEmpty ? nil : taxNumber
            company.phoneNumber = phoneNumber.isEmpty ? nil : phoneNumber
            company.email = email.isEmpty ? nil : email
            company.address = address.isEmpty ? nil : address
            company.bankName = bankName.isEmpty ? nil : bankName
            company.bankAccount = bankAccount.isEmpty ? nil : bankAccount
            company.lastModified = Date()
        } else {
            // 创建新信息
            let newCompany = CompanyInfo(
                companyName: companyName,
                taxNumber: taxNumber.isEmpty ? nil : taxNumber,
                phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                email: email.isEmpty ? nil : email,
                address: address.isEmpty ? nil : address,
                bankName: bankName.isEmpty ? nil : bankName,
                bankAccount: bankAccount.isEmpty ? nil : bankAccount
            )
            modelContext.insert(newCompany)
        }
        
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 子视图组件

// 说明横幅
struct InfoBanner: View {
    var themeColor: Color
    
    var body: some View {
        LiquidGlassCard {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(themeColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动开票功能")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black.opacity(0.85))
                    
                    Text("设置后，上传发票二维码即可自动开票")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black.opacity(0.5))
                }
                
                Spacer()
            }
        }
    }
}

// 基本信息卡片
struct BasicInfoCard: View {
    @Binding var companyName: String
    @Binding var taxNumber: String
    var focusedField: FocusState<CompanySettingsView.Field?>.Binding
    var themeColor: Color
    
    var body: some View {
        LiquidGlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(themeColor)
                    Text("基本信息")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                    Text("*必填")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.red.opacity(0.7))
                }
                
                VStack(spacing: 12) {
                    InputField(
                        icon: "building.2",
                        placeholder: "公司名称（抬头）",
                        text: $companyName,
                        isFocused: focusedField.wrappedValue == .companyName,
                        themeColor: themeColor
                    )
                    .focused(focusedField, equals: .companyName)
                    
                    InputField(
                        icon: "number",
                        placeholder: "税号（6-20位）",
                        text: $taxNumber,
                        isFocused: focusedField.wrappedValue == .taxNumber,
                        keyboardType: .numbersAndPunctuation,
                        themeColor: themeColor
                    )
                    .focused(focusedField, equals: .taxNumber)
                }
            }
        }
    }
}

// 联系方式卡片
struct ContactInfoCard: View {
    @Binding var phoneNumber: String
    @Binding var email: String
    var focusedField: FocusState<CompanySettingsView.Field?>.Binding
    var themeColor: Color

    var body: some View {
        LiquidGlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(themeColor)
                    Text("联系方式")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                    Text("*必填")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.red.opacity(0.7))
                }
                
                VStack(spacing: 12) {
                    InputField(
                        icon: "phone",
                        placeholder: "手机号",
                        text: $phoneNumber,
                        isFocused: focusedField.wrappedValue == .phoneNumber,
                        keyboardType: .phonePad,
                        themeColor: themeColor
                    )
                    .focused(focusedField, equals: .phoneNumber)
                    
                    InputField(
                        icon: "envelope",
                        placeholder: "邮箱",
                        text: $email,
                        isFocused: focusedField.wrappedValue == .email,
                        keyboardType: .emailAddress,
                        themeColor: themeColor
                    )
                    .focused(focusedField, equals: .email)
                }
            }
        }
    }
}

// 详细信息卡片
struct DetailInfoCard: View {
    @Binding var address: String
    @Binding var bankName: String
    @Binding var bankAccount: String
    var focusedField: FocusState<CompanySettingsView.Field?>.Binding
    var themeColor: Color
    
    var body: some View {
        LiquidGlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(themeColor)
                    Text("详细信息")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.85))
                    Text("选填")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black.opacity(0.4))
                }
                
                VStack(spacing: 12) {
                    InputField(
                        icon: "location",
                        placeholder: "地址",
                        text: $address,
                        isFocused: focusedField.wrappedValue == .address,
                        themeColor: themeColor
                    )
                    .focused(focusedField, equals: .address)
                    
                    InputField(
                        icon: "building.columns",
                        placeholder: "开户行",
                        text: $bankName,
                        isFocused: focusedField.wrappedValue == .bankName,
                        themeColor: themeColor
                    )
                    .focused(focusedField, equals: .bankName)
                    
                    InputField(
                        icon: "creditcard",
                        placeholder: "银行账号",
                        text: $bankAccount,
                        isFocused: focusedField.wrappedValue == .bankAccount,
                        keyboardType: .numbersAndPunctuation,
                        themeColor: themeColor
                    )
                    .focused(focusedField, equals: .bankAccount)
                }
            }
        }
    }
}

// 输入框组件
struct InputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool
    var keyboardType: UIKeyboardType = .default
    var themeColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isFocused ? themeColor : Color.black.opacity(0.3))
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black.opacity(0.85))
                .keyboardType(keyboardType)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.6))
                
                if isFocused {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [themeColor, themeColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                }
            }
        )
    }
}

