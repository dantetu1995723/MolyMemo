import SwiftUI
import SwiftData

// 公司开票信息设置界面
struct CompanySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
    
    // 获取现有的公司信息（如果有）
    private var existingCompany: CompanyInfo? {
        companies.first
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.94)
                    .ignoresSafeArea()
                
                ScrollView {
                    if showContent {
                        VStack(spacing: 16) {
                            // 说明文字
                            InfoBanner()
                            
                            // 基本信息卡片（必填）
                            BasicInfoCard(
                                companyName: $companyName,
                                taxNumber: $taxNumber,
                                focusedField: $focusedField
                            )
                            
                            // 联系方式卡片（选填）
                            ContactInfoCard(
                                phoneNumber: $phoneNumber,
                                email: $email,
                                focusedField: $focusedField
                            )
                            
                            // 详细信息卡片（选填）
                            DetailInfoCard(
                                address: $address,
                                bankName: $bankName,
                                bankAccount: $bankAccount,
                                focusedField: $focusedField
                            )
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("开票信息设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveCompanyInfo) {
                        Text("保存")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: isValid ? [
                                                Color(red: 0.6, green: 0.75, blue: 0.2),
                                                Color(red: 0.5, green: 0.65, blue: 0.15)
                                            ] : [Color.gray.opacity(0.5)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: isValid ? Color.black.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadExistingData()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.1)) {
                    showContent = true
                }
            }
        }
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
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(red: 0.6, green: 0.75, blue: 0.2))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("自动开票功能")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                
                Text("设置后，上传发票二维码即可自动开票")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.6, green: 0.75, blue: 0.2).opacity(0.1))
        )
    }
}

// 基本信息卡片
struct BasicInfoCard: View {
    @Binding var companyName: String
    @Binding var taxNumber: String
    var focusedField: FocusState<CompanySettingsView.Field?>.Binding
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.6, green: 0.75, blue: 0.2))
                Text("基本信息")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                Text("*必填")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
            
            VStack(spacing: 12) {
                InputField(
                    icon: "building.2",
                    placeholder: "公司名称（抬头）",
                    text: $companyName,
                    isFocused: focusedField.wrappedValue == .companyName
                )
                .focused(focusedField, equals: .companyName)
                
                InputField(
                    icon: "number",
                    placeholder: "税号（6-20位）",
                    text: $taxNumber,
                    isFocused: focusedField.wrappedValue == .taxNumber,
                    keyboardType: .numbersAndPunctuation
                )
                .focused(focusedField, equals: .taxNumber)
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

// 联系方式卡片
struct ContactInfoCard: View {
    @Binding var phoneNumber: String
    @Binding var email: String
    var focusedField: FocusState<CompanySettingsView.Field?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.6, green: 0.75, blue: 0.2))
                Text("联系方式")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                Text("*必填")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
            
            VStack(spacing: 12) {
                InputField(
                    icon: "phone",
                    placeholder: "手机号",
                    text: $phoneNumber,
                    isFocused: focusedField.wrappedValue == .phoneNumber,
                    keyboardType: .phonePad
                )
                .focused(focusedField, equals: .phoneNumber)
                
                InputField(
                    icon: "envelope",
                    placeholder: "邮箱",
                    text: $email,
                    isFocused: focusedField.wrappedValue == .email,
                    keyboardType: .emailAddress
                )
                .focused(focusedField, equals: .email)
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

// 详细信息卡片
struct DetailInfoCard: View {
    @Binding var address: String
    @Binding var bankName: String
    @Binding var bankAccount: String
    var focusedField: FocusState<CompanySettingsView.Field?>.Binding
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.6, green: 0.75, blue: 0.2))
                Text("详细信息")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                Text("选填")
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.4))
            }
            
            VStack(spacing: 12) {
                InputField(
                    icon: "location",
                    placeholder: "地址",
                    text: $address,
                    isFocused: focusedField.wrappedValue == .address
                )
                .focused(focusedField, equals: .address)
                
                InputField(
                    icon: "building.columns",
                    placeholder: "开户行",
                    text: $bankName,
                    isFocused: focusedField.wrappedValue == .bankName
                )
                .focused(focusedField, equals: .bankName)
                
                InputField(
                    icon: "creditcard",
                    placeholder: "银行账号",
                    text: $bankAccount,
                    isFocused: focusedField.wrappedValue == .bankAccount,
                    keyboardType: .numbersAndPunctuation
                )
                .focused(focusedField, equals: .bankAccount)
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

// 输入框组件
struct InputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isFocused ? Color(red: 0.6, green: 0.75, blue: 0.2) : Color.black.opacity(0.3))
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .keyboardType(keyboardType)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.96, green: 0.96, blue: 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color(red: 0.6, green: 0.75, blue: 0.2) : Color.clear, lineWidth: 2)
                )
        )
    }
}

