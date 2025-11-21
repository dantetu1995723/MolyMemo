import SwiftUI
import SwiftData

// 批量人脉预览气泡
struct BatchContactPreviewBubble: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Query(sort: \Contact.name) private var allContacts: [Contact]
    
    let messageId: UUID
    @State private var batchPreview: BatchContactPreviewData
    @State private var expandedGroups: Set<Int> = [0]  // 默认展开第一组
    
    init(messageId: UUID, batchPreview: BatchContactPreviewData) {
        self.messageId = messageId
        self._batchPreview = State(initialValue: batchPreview)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 顶部统计信息
            headerStatistics
            
            Divider()
                .background(Color.black.opacity(0.1))
            
            // 分组列表
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(groupedContacts, id: \.groupIndex) { group in
                        ContactGroupSection(
                            group: group,
                            isExpanded: expandedGroups.contains(group.groupIndex),
                            onToggleExpand: {
                                toggleGroup(group.groupIndex)
                            },
                            onToggleSelectAll: { select in
                                selectAllInGroup(group.groupIndex, select: select)
                            },
                            onToggleItem: { itemId in
                                toggleItem(itemId)
                            },
                            onToggleExpand: { itemId in
                                toggleItemExpansion(itemId)
                            },
                            onUpdateItem: { itemId, newData in
                                updateItemData(itemId, newData: newData)
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 400)  // 限制最大高度，避免太长
            
            // 无法识别的图片提示
            if batchPreview.failedCount > 0 {
                failedImagesSection
            }
            
            Divider()
                .background(Color.black.opacity(0.1))
            
            // 底部操作栏
            HStack(spacing: 12) {
                // 全选/取消全选
                Button(action: toggleSelectAll) {
                    HStack(spacing: 6) {
                        Image(systemName: allSelected ? "square" : "checkmark.square.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(allSelected ? "取消全选" : "全选")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                // 批量添加按钮
                Button(action: handleBatchAdd) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("批量添加 (\(selectedCount)人)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 1.0, blue: 0.25),
                                        Color(red: 0.78, green: 0.98, blue: 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(selectedCount == 0)
                .opacity(selectedCount == 0 ? 0.5 : 1.0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - 子视图
    
    // 顶部统计信息
    private var headerStatistics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已识别 \(batchPreview.successCount) 位联系人")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.8))
            }
            
            // 细分统计
            HStack(spacing: 16) {
                // 新增数量
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12))
                    Text("\(batchPreview.newContactsCount) 位新增")
                        .font(.system(size: 13))
                }
                .foregroundColor(.blue)
                
                // 更新数量
                if batchPreview.updateContactsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("\(batchPreview.updateContactsCount) 位更新")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.orange)
                }
            }
            
            // 失败提示
            if batchPreview.failedCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("无法识别 \(batchPreview.failedCount) 张截图")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    // 无法识别的图片区域
    private var failedImagesSection: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)
            
            Text("无法识别 \(batchPreview.failedCount) 张截图")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.black.opacity(0.6))
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    // MARK: - 计算属性
    
    // 按组索引分组的联系人
    private var groupedContacts: [ContactGroup] {
        let groups = Dictionary(grouping: batchPreview.contacts) { $0.groupIndex }
        return groups.keys.sorted().map { groupIndex in
            ContactGroup(
                groupIndex: groupIndex,
                contacts: groups[groupIndex] ?? []
            )
        }
    }
    
    // 已选中的数量
    private var selectedCount: Int {
        batchPreview.contacts.filter { $0.isSelected }.count
    }
    
    // 是否全部选中
    private var allSelected: Bool {
        batchPreview.contacts.allSatisfy { $0.isSelected }
    }
    
    // MARK: - 操作方法
    
    // 切换分组展开状态
    private func toggleGroup(_ groupIndex: Int) {
        if expandedGroups.contains(groupIndex) {
            expandedGroups.remove(groupIndex)
        } else {
            expandedGroups.insert(groupIndex)
        }
        HapticFeedback.light()
    }
    
    // 选择/取消选择分组内所有联系人
    private func selectAllInGroup(_ groupIndex: Int, select: Bool) {
        for index in batchPreview.contacts.indices {
            if batchPreview.contacts[index].groupIndex == groupIndex {
                batchPreview.contacts[index].isSelected = select
            }
        }
        HapticFeedback.light()
    }
    
    // 切换单个联系人选中状态
    private func toggleItem(_ itemId: UUID) {
        if let index = batchPreview.contacts.firstIndex(where: { $0.id == itemId }) {
            batchPreview.contacts[index].isSelected.toggle()
            HapticFeedback.light()
        }
    }
    
    // 切换单个联系人展开状态
    private func toggleItemExpansion(_ itemId: UUID) {
        if let index = batchPreview.contacts.firstIndex(where: { $0.id == itemId }) {
            batchPreview.contacts[index].isExpanded.toggle()
            HapticFeedback.light()
        }
    }
    
    // 更新单个联系人数据
    private func updateItemData(_ itemId: UUID, newData: ContactPreviewData) {
        if let index = batchPreview.contacts.firstIndex(where: { $0.id == itemId }) {
            batchPreview.contacts[index].contactData = newData
        }
    }
    
    // 全选/取消全选
    private func toggleSelectAll() {
        let newState = !allSelected
        for index in batchPreview.contacts.indices {
            batchPreview.contacts[index].isSelected = newState
        }
        HapticFeedback.light()
    }
    
    // 批量添加
    private func handleBatchAdd() {
        let selectedContacts = batchPreview.contacts.filter { $0.isSelected }
        
        guard !selectedContacts.isEmpty else { return }
        
        print("📝 开始批量添加 \(selectedContacts.count) 位联系人")
        
        var addedCount = 0      // 新增数量
        var updatedCount = 0    // 更新数量
        
        for item in selectedContacts {
            let contactData = item.contactData
            
            if let existingId = contactData.existingContactId {
                // 更新现有联系人
                if let existing = allContacts.first(where: { $0.id == existingId }) {
                    existing.name = contactData.name
                    existing.phoneNumber = contactData.phoneNumber
                    existing.company = contactData.company
                    existing.identity = contactData.identity
                    existing.hobbies = contactData.hobbies
                    existing.relationship = contactData.relationship
                    
                    // 更新头像（如果有新的）
                    if let newAvatar = contactData.avatarData {
                        existing.avatarData = newAvatar
                    }
                    
                    // 追加截图到附件
                    if var imageData = existing.imageData {
                        imageData.append(contactData.imageData)
                        existing.imageData = imageData
                    } else {
                        existing.imageData = [contactData.imageData]
                    }
                    
                    existing.lastModified = Date()
                    updatedCount += 1
                    
                    print("✅ 更新联系人: \(existing.name), ID: \(existing.id)")
                }
            } else {
                // 新增联系人
                let newContact = Contact(
                    name: contactData.name,
                    phoneNumber: contactData.phoneNumber,
                    company: contactData.company,
                    identity: contactData.identity,
                    hobbies: contactData.hobbies,
                    relationship: contactData.relationship,
                    avatarData: contactData.avatarData,
                    imageData: [contactData.imageData],
                    textAttachments: nil
                )
                modelContext.insert(newContact)
                addedCount += 1
                
                print("✅ 新增联系人: \(newContact.name), ID: \(newContact.id)")
            }
        }
        
        // 保存到数据库
        do {
            try modelContext.save()
            print("💾 批量保存成功")
        } catch {
            print("❌ 保存失败: \(error)")
        }
        
        // 显示成功消息
        let successMessage: String
        if addedCount > 0 && updatedCount > 0 {
            successMessage = "✅ 已添加 \(addedCount) 位新联系人，更新 \(updatedCount) 位现有联系人"
        } else if addedCount > 0 {
            successMessage = "✅ 已添加 \(addedCount) 位联系人"
        } else {
            successMessage = "✅ 已更新 \(updatedCount) 位联系人"
        }
        
        // 在聊天室显示成功消息
        let resultMessage = ChatMessage(
            role: .agent,
            content: successMessage
        )
        appState.chatMessages.append(resultMessage)
        appState.saveMessageToStorage(resultMessage, modelContext: modelContext)
        
        // 移除预览消息
        if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
            appState.chatMessages.remove(at: idx)
        }
        
        HapticFeedback.success()
    }
}

// MARK: - 辅助数据结构

struct ContactGroup {
    let groupIndex: Int
    let contacts: [ContactItemPreview]
}

// MARK: - 分组区域视图

struct ContactGroupSection: View {
    let group: ContactGroup
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleSelectAll: (Bool) -> Void
    let onToggleItem: (UUID) -> Void
    let onToggleExpand: (UUID) -> Void
    let onUpdateItem: (UUID, ContactPreviewData) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // 分组标题栏
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                
                Text("分组 \(group.groupIndex + 1) (\(group.contacts.count)人)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.7))
                
                Spacer()
                
                // 全选按钮
                Button(action: {
                    onToggleSelectAll(!allSelected)
                }) {
                    Text(allSelected ? "取消全选" : "全选本组")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                }
                
                // 展开/收起按钮
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.5))
                        .frame(width: 24, height: 24)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.03))
            )
            
            // 联系人列表
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(group.contacts) { item in
                        ContactItemRow(
                            item: item,
                            onToggleSelect: {
                                onToggleItem(item.id)
                            },
                            onToggleExpand: {
                                onToggleExpand(item.id)
                            },
                            onUpdate: { newData in
                                onUpdateItem(item.id, newData)
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    // 是否全部选中
    private var allSelected: Bool {
        group.contacts.allSatisfy { $0.isSelected }
    }
}

// MARK: - 单个联系人行视图

struct ContactItemRow: View {
    let item: ContactItemPreview
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void
    let onUpdate: (ContactPreviewData) -> Void
    
    @State private var editingData: ContactPreviewData
    
    init(item: ContactItemPreview, onToggleSelect: @escaping () -> Void, onToggleExpand: @escaping () -> Void, onUpdate: @escaping (ContactPreviewData) -> Void) {
        self.item = item
        self.onToggleSelect = onToggleSelect
        self.onToggleExpand = onToggleExpand
        self.onUpdate = onUpdate
        self._editingData = State(initialValue: item.contactData)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 折叠状态的简要信息
            HStack(spacing: 12) {
                // 选择框
                Button(action: onToggleSelect) {
                    Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundColor(item.isSelected ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.gray)
                }
                
                // 头像缩略图
                avatarThumbnail
                
                // 基本信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.contactData.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.85))
                    
                    if let company = item.contactData.company, !company.isEmpty {
                        Text(company)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    
                    // 更新提示
                    if item.contactData.isEditMode {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .medium))
                            Text("将更新此人信息")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(Color.orange.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // 展开/收起按钮
                Button(action: onToggleExpand) {
                    Text(item.isExpanded ? "收起▲" : "展开▼")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                }
            }
            .padding(12)
            
            // 展开状态的详细编辑区域
            if item.isExpanded {
                ContactDetailEditSection(
                    contactData: $editingData,
                    onSave: {
                        onUpdate(editingData)
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(item.isSelected ? Color.white : Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(item.isSelected ? Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .onChange(of: editingData) { _, newValue in
            onUpdate(newValue)
        }
    }
    
    // 头像缩略图
    private var avatarThumbnail: some View {
        Group {
            if let avatarData = item.contactData.avatarData,
               let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(item.contactData.name.prefix(1)))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.6))
                    )
            }
        }
    }
}

// MARK: - 详细编辑区域

struct ContactDetailEditSection: View {
    @Binding var contactData: ContactPreviewData
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            // 手机号
            ContactInfoEditRow(
                icon: "phone.fill",
                label: "手机号",
                text: Binding(
                    get: { contactData.phoneNumber ?? "" },
                    set: { contactData.phoneNumber = $0.isEmpty ? nil : $0 }
                ),
                placeholder: "输入手机号"
            )
            
            // 公司
            ContactInfoEditRow(
                icon: "building.2.fill",
                label: "公司",
                text: Binding(
                    get: { contactData.company ?? "" },
                    set: { contactData.company = $0.isEmpty ? nil : $0 }
                ),
                placeholder: "输入公司"
            )
            
            // 身份（职位）
            ContactInfoEditRow(
                icon: "briefcase.fill",
                label: "身份",
                text: Binding(
                    get: { contactData.identity ?? "" },
                    set: { contactData.identity = $0.isEmpty ? nil : $0 }
                ),
                placeholder: "输入职位"
            )
            
            // 兴趣爱好
            ContactInfoEditRow(
                icon: "heart.fill",
                label: "兴趣",
                text: Binding(
                    get: { contactData.hobbies ?? "" },
                    set: { contactData.hobbies = $0.isEmpty ? nil : $0 }
                ),
                placeholder: "输入兴趣"
            )
            
            // 与我关系
            ContactInfoEditRow(
                icon: "person.2.fill",
                label: "关系",
                text: Binding(
                    get: { contactData.relationship ?? "" },
                    set: { contactData.relationship = $0.isEmpty ? nil : $0 }
                ),
                placeholder: "输入关系"
            )
        }
        .padding(12)
        .background(Color.black.opacity(0.02))
        .cornerRadius(8)
    }
}

