import SwiftUI
import Contacts
import SwiftData

// 通讯录导入视图
struct ContactImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @Query private var existingContacts: [Contact]

    @State private var systemContacts: [SystemContact] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var selectAll = false

    private let contactsManager = ContactsManager.shared
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    // 过滤后的联系人
    private var filteredContacts: [SystemContact] {
        if searchText.isEmpty {
            return systemContacts
        }
        return systemContacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(searchText) ||
            contact.phoneNumber?.contains(searchText) == true ||
            contact.company?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    // 已选中的联系人数量
    private var selectedCount: Int {
        systemContacts.filter { $0.isSelected }.count
    }

    // 新增联系人数量（未重复的）
    private var newContactsCount: Int {
        systemContacts.filter { !$0.isDuplicate }.count
    }

    // 重复联系人数量
    private var duplicateContactsCount: Int {
        systemContacts.filter { $0.isDuplicate }.count
    }
    
    var body: some View {
        // 统一后端接入：系统通讯录导入/同步已下线（避免读取通讯录权限）。
        NavigationView {
            VStack(spacing: 14) {
                Spacer()

                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.black.opacity(0.18))

                Text("已取消系统通讯录导入/同步")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.78))

                Text("联系人现在统一以「后端人脉」为准，不再读取系统通讯录。")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("关闭") { dismiss() }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.08)))

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("通讯录导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.6))
                    }
                }
            }
        }
    }
    
    // 加载通讯录
    private func loadContacts() {
        isLoading = true
        
        Task {
            // 先检查权限
            let status = contactsManager.checkAuthorizationStatus()
            print("📋 通讯录权限状态: \(status.rawValue)")
            
            if status == .notDetermined {
                print("⏳ 正在请求通讯录权限...")
                // 请求权限
                let granted = await contactsManager.requestAccess()
                print(granted ? "✅ 用户授予了通讯录权限" : "❌ 用户拒绝了通讯录权限")
                
                if !granted {
                    await MainActor.run {
                        errorMessage = "需要通讯录权限才能导入联系人。请在系统设置中允许访问通讯录。"
                        showError = true
                        isLoading = false
                    }
                    return
                }
                
                // 权限刚授予，再次检查状态
                let newStatus = contactsManager.checkAuthorizationStatus()
                print("🔄 重新检查权限状态: \(newStatus.rawValue)")
                
                if newStatus != .authorized {
                    await MainActor.run {
                        errorMessage = "权限授予后状态异常，请重试或在系统设置中手动开启"
                        showError = true
                        isLoading = false
                    }
                    return
                }
            } else if status == .denied || status == .restricted {
                print("⚠️ 通讯录权限被拒绝或受限")
                await MainActor.run {
                    errorMessage = "通讯录权限已被拒绝。请在【设置】->【隐私与安全性】->【通讯录】中允许 Yuanyuan 访问通讯录。"
                    showError = true
                    isLoading = false
                }
                return
            }
            
            print("✅ 通讯录权限已授予，开始获取联系人...")
            
            // 再次确认权限状态
            let finalStatus = contactsManager.checkAuthorizationStatus()
            print("📝 最终权限状态: \(finalStatus.rawValue)")
            
            if finalStatus != .authorized {
                await MainActor.run {
                    errorMessage = "权限状态异常（状态码：\(finalStatus.rawValue)），请在系统设置中检查通讯录权限"
                    showError = true
                    isLoading = false
                }
                return
            }
            
            // 获取联系人
            do {
                let cnContacts = try await contactsManager.fetchAllContacts()
                await MainActor.run {
                    systemContacts = cnContacts.map { SystemContact(cnContact: $0) }

                    // 标记重复的联系人
                    markDuplicateContacts()

                    isLoading = false
                    print("✅ 成功加载 \(systemContacts.count) 个联系人（新增: \(newContactsCount), 重复: \(duplicateContactsCount)）")
                }
            } catch {
                print("❌ 获取通讯录失败: \(error)")
                await MainActor.run {
                    let currentStatus = contactsManager.checkAuthorizationStatus()
                    errorMessage = "获取通讯录失败: \(error.localizedDescription)\n当前权限状态: \(currentStatus.rawValue)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    // 标记重复的联系人
    private func markDuplicateContacts() {
        // 创建已有联系人的查找集合（使用姓名和手机号）
        var existingNameSet = Set<String>()
        var existingPhoneSet = Set<String>()

        for contact in existingContacts {
            // 添加姓名（忽略大小写和空格）
            let normalizedName = contact.name.lowercased().trimmingCharacters(in: .whitespaces)
            existingNameSet.insert(normalizedName)

            // 添加手机号（去除所有非数字字符）
            if let phone = contact.phoneNumber {
                let normalizedPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if !normalizedPhone.isEmpty {
                    existingPhoneSet.insert(normalizedPhone)
                }
            }
        }

        // 标记重复的联系人
        for index in systemContacts.indices {
            let systemContact = systemContacts[index]

            // 检查姓名是否重复
            let normalizedName = systemContact.displayName.lowercased().trimmingCharacters(in: .whitespaces)
            let nameExists = existingNameSet.contains(normalizedName)

            // 检查手机号是否重复
            var phoneExists = false
            if let phone = systemContact.phoneNumber {
                let normalizedPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if !normalizedPhone.isEmpty {
                    phoneExists = existingPhoneSet.contains(normalizedPhone)
                }
            }

            // 如果姓名或手机号任一重复，则标记为重复
            systemContacts[index].isDuplicate = nameExists || phoneExists

            // 重复的联系人不自动选中
            if systemContacts[index].isDuplicate {
                systemContacts[index].isSelected = false
            }
        }

        print("📊 去重结果: 总计 \(systemContacts.count) 个，新增 \(newContactsCount) 个，重复 \(duplicateContactsCount) 个")
    }

    // 导入选中的联系人
    private func importSelectedContacts() {
        HapticFeedback.success()

        // 只导入选中且非重复的联系人
        let selectedContacts = systemContacts.filter { $0.isSelected && !$0.isDuplicate }

        if selectedContacts.isEmpty {
            errorMessage = "没有可导入的联系人"
            showError = true
            return
        }

        print("🔄 准备导入 \(selectedContacts.count) 个联系人")

        var importedCount = 0
        for systemContact in selectedContacts {
            let contact = contactsManager.convertToContact(systemContact.cnContact)
            modelContext.insert(contact)
            importedCount += 1
        }

        do {
            try modelContext.save()
            print("✅ 成功导入 \(importedCount) 个联系人")
            dismiss()
        } catch {
            print("❌ 保存失败: \(error)")
            errorMessage = "保存联系人失败: \(error.localizedDescription)"
            showError = true
        }
    }

    // 更新全选状态
    private func updateSelectAllState() {
        // 只考虑非重复的联系人
        let nonDuplicateContacts = systemContacts.filter { !$0.isDuplicate }
        let allSelected = nonDuplicateContacts.allSatisfy { $0.isSelected }
        if selectAll != allSelected {
            selectAll = allSelected
        }
    }
}

// MARK: - 系统联系人行
struct SystemContactRow: View {
    let contact: SystemContact
    let isSelected: Bool
    var themeColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            // 如果是重复的联系人，不允许选择
            if !contact.isDuplicate {
                onTap()
            }
        }) {
            HStack(spacing: 16) {
                // 选中指示或重复标记
                if contact.isDuplicate {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color.black.opacity(0.2))
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isSelected ? themeColor : Color.black.opacity(0.2))
                }

                // 联系人信息
                VStack(alignment: .leading, spacing: 4) {
                     HStack(spacing: 8) {
                         Text(contact.displayName)
                             .font(.system(size: 16, weight: .semibold, design: .rounded))
                             .foregroundColor(contact.isDuplicate ? Color.black.opacity(0.4) : Color.black.opacity(0.85))

                         if contact.isDuplicate {
                             Text("已在人脉库中")
                                 .font(.system(size: 11, weight: .medium, design: .rounded))
                                 .foregroundColor(Color.white)
                                 .padding(.horizontal, 8)
                                 .padding(.vertical, 3)
                                 .background(
                                     Capsule()
                                         .fill(Color.black.opacity(0.3))
                                 )
                         }
                     }

                    HStack(spacing: 8) {
                        if let phone = contact.phoneNumber {
                            Text(phone)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(contact.isDuplicate ? Color.black.opacity(0.3) : Color.black.opacity(0.5))
                        }

                        if let company = contact.company {
                            Text("·")
                                .foregroundColor(Color.black.opacity(0.3))
                            Text(company)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(contact.isDuplicate ? Color.black.opacity(0.3) : Color.black.opacity(0.5))
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        contact.isDuplicate ?
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.03),
                                Color.black.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        isSelected ?
                        LinearGradient(
                            colors: [
                                themeColor.opacity(0.1),
                                themeColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                Color.white.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.black.opacity(contact.isDuplicate ? 0.02 : 0.04), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(contact.isDuplicate ? 0.6 : 1.0)
    }
}

