import SwiftUI
import SwiftData
import PhotosUI

struct ContactEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    var contact: Contact? // nil表示新建，非nil表示编辑
    
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var company = ""
    @State private var identity = ""
    @State private var hobbies = ""
    @State private var relationship = ""
    @State private var avatarData: Data?
    
    // 附件
    @State private var imageData: [Data] = []
    @State private var textAttachments: [String] = []

    @State private var showImagePicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var newTextAttachment = ""
    @State private var showAddText = false

    // 图片选择相关状态
    @State private var selectedImageIndices: Set<Int> = []
    @State private var isSubmitting: Bool = false
    @State private var alertMessage: String? = nil
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    var body: some View {
        NavigationView {
            ZStack {
                // 白色背景
                Color.white.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 头像选择
                        VStack(spacing: 12) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                avatarView
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Text("点击设置头像")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color.black.opacity(0.5))
                        }
                        .padding(.top, 20)
                        
                        // 基本信息表单
                        VStack(spacing: 16) {
                            // 姓名（必填）
                            EditField(
                                icon: "person.fill",
                                placeholder: "名字（昵称）*",
                                text: $name
                            )
                            
                            // 电话
                            EditField(
                                icon: "phone.fill",
                                placeholder: "手机号",
                                text: $phoneNumber,
                                keyboardType: .phonePad
                            )
                            
                            // 公司
                            EditField(
                                icon: "building.2.fill",
                                placeholder: "公司",
                                text: $company
                            )
                            
                            // 身份（职位）
                            EditField(
                                icon: "briefcase.fill",
                                placeholder: "身份（职位）",
                                text: $identity
                            )
                            
                            // 兴趣爱好
                            EditField(
                                icon: "heart.fill",
                                placeholder: "兴趣爱好",
                                text: $hobbies
                            )
                            
                            // 与我关系
                            EditField(
                                icon: "person.2.fill",
                                placeholder: "与我关系",
                                text: $relationship
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // 附件管理
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color.black.opacity(0.5))
                                
                                Text("附件")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color.black.opacity(0.7))
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            // 图片附件
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("截图")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.6))
                                    
                                    Spacer()
                                    
                                    if !imageData.isEmpty {
                                        // 删除按钮
                                        Button(action: {
                                            deleteSelectedImages()
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "trash.circle.fill")
                                                    .font(.system(size: 18))
                                                Text("删除")
                                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color.red.opacity(selectedImageIndices.isEmpty ? 0.4 : 0.8))
                                            )
                                        }
                                        .disabled(selectedImageIndices.isEmpty)
                                    }
                                    
                                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 18))
                                            Text("添加")
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(themeColor)
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                if !imageData.isEmpty {
                                    ImageThumbnailsView(
                                        imageData: $imageData,
                                        selectedImageIndices: $selectedImageIndices
                                    )
                                }
                            }
                            
                            // 文本附件
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("文本备注")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.6))
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        showAddText = true
                                        HapticFeedback.light()
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 18))
                                            Text("添加")
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(themeColor)
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                if !textAttachments.isEmpty {
                                    VStack(spacing: 8) {
                                        ForEach(textAttachments.indices, id: \.self) { index in
                                            TextAttachmentRow(
                                                text: textAttachments[index],
                                                onDelete: {
                                                    withAnimation {
                                                        _ = textAttachments.remove(at: index)
                                                    }
                                                    HapticFeedback.light()
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(contact == nil ? "新建联系人" : "编辑联系人")
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
                    Button(action: {
                        Task { await submitSave() }
                    }) {
                        Text("保存")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(themeColor)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(name.isEmpty || isSubmitting)
                    .opacity(name.isEmpty ? 0.5 : 1.0)
                }
            }
            .onChange(of: selectedAvatarItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        avatarData = data
                    }
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    imageData.removeAll()
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            imageData.append(data)
                        }
                    }
                }
            }
            .alert("添加文本备注", isPresented: $showAddText) {
                TextField("输入备注内容", text: $newTextAttachment)
                Button("取消", role: .cancel) { newTextAttachment = "" }
                Button("添加") {
                    guard !newTextAttachment.isEmpty else { return }
                    withAnimation {
                        textAttachments.append(newTextAttachment)
                    }
                    newTextAttachment = ""
                    HapticFeedback.success()
                }
            }
            .onAppear {
                loadContactData()
            }
            .alert(
                "保存失败",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }
    
    private func loadContactData() {
        guard let contact = contact else { return }
        
        name = contact.name
        phoneNumber = contact.phoneNumber ?? ""
        company = contact.company ?? ""
        identity = contact.identity ?? ""
        hobbies = contact.hobbies ?? ""
        relationship = contact.relationship ?? ""
        avatarData = contact.avatarData
        imageData = contact.imageData ?? []
        textAttachments = contact.textAttachments ?? []
    }
    
    @MainActor
    private func submitSave() async {
        guard !name.isEmpty else { return }
        guard !isSubmitting else { return }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            HapticFeedback.success()
            
            if let existingContact = contact {
                // 先本地更新（UI 即时反馈）
                existingContact.name = name
                existingContact.phoneNumber = phoneNumber.isEmpty ? nil : phoneNumber
                existingContact.company = company.isEmpty ? nil : company
                existingContact.identity = identity.isEmpty ? nil : identity
                existingContact.hobbies = hobbies.isEmpty ? nil : hobbies
                existingContact.relationship = relationship.isEmpty ? nil : relationship
                existingContact.avatarData = avatarData
                existingContact.imageData = imageData.isEmpty ? nil : imageData
                existingContact.textAttachments = textAttachments.isEmpty ? nil : textAttachments
                existingContact.lastModified = Date()
                
                // 有 remoteId 才走后端更新（后端没有 create 接口时，避免误调用）
                let rid = (existingContact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !rid.isEmpty {
                    var payload: [String: Any] = ["name": name]
                    if !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { payload["company"] = company }
                    if !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { payload["position"] = identity }
                    if !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { payload["phone"] = phoneNumber }
                    if let email = existingContact.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                        payload["email"] = email
                    }
                    if !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { payload["relationship_type"] = relationship }
                    if let notes = existingContact.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        payload["notes"] = notes
                    }
                    
                    if let updated = try await ContactService.updateContact(remoteId: rid, payload: payload, keepLocalId: existingContact.id) {
                        existingContact.remoteId = updated.remoteId ?? rid
                        existingContact.name = updated.name
                        if let v = updated.company?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { existingContact.company = v }
                        if let v = updated.title?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { existingContact.identity = v }
                        if let v = updated.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { existingContact.phoneNumber = v }
                        if let v = updated.email?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { existingContact.email = v }
                        let imp = (updated.impression ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let n = (updated.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let candidate = !imp.isEmpty ? imp : (n.isEmpty ? nil : n)
                        if let candidate {
                            let current = (existingContact.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if current.isEmpty {
                                existingContact.notes = candidate
                            } else if !current.contains(candidate) {
                                existingContact.notes = current + "\n\n" + candidate
                            }
                        }
                        existingContact.lastModified = Date()
                    }
                }
                
                try? modelContext.save()
                dismiss()
                return
            }
            
            // 新建：只做本地保存（后端创建通常由聊天 tool 完成）
            let newContact = Contact(
                name: name,
                phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                company: company.isEmpty ? nil : company,
                identity: identity.isEmpty ? nil : identity,
                hobbies: hobbies.isEmpty ? nil : hobbies,
                relationship: relationship.isEmpty ? nil : relationship,
                avatarData: avatarData,
                imageData: imageData.isEmpty ? nil : imageData,
                textAttachments: textAttachments.isEmpty ? nil : textAttachments
            )
            modelContext.insert(newContact)
            try? modelContext.save()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
    
    private func deleteSelectedImages() {
        guard !selectedImageIndices.isEmpty else { return }
        
        HapticFeedback.success()
        withAnimation {
            // 按照索引从大到小排序，避免删除时索引变化
            for index in selectedImageIndices.sorted(by: >) {
                if index < imageData.count {
                    imageData.remove(at: index)
                }
            }
            selectedImageIndices.removeAll()
        }
    }
    
    // 头像视图
    private var avatarView: some View {
        ZStack {
            if let avatarData = avatarData,
               let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(themeColor.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                    )
            }
        }
    }
}

// MARK: - 编辑字段
struct EditField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isMultiline: Bool = false
    
    var body: some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.black.opacity(0.5))
                .frame(width: 28)
                .padding(.top, isMultiline ? 12 : 0)
            
            if isMultiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                    .lineLimit(3...6)
                    .keyboardType(keyboardType)
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                    .keyboardType(keyboardType)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - 图片缩略图视图
struct ImageThumbnailsView: View {
    @Binding var imageData: [Data]
    @Binding var selectedImageIndices: Set<Int>
    @State private var draggedItem: Data?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(imageData.indices, id: \.self) { index in
                    SelectableThumbnail(
                        imageData: imageData[index],
                        index: index,
                        selectedImageIndices: $selectedImageIndices
                    )
                    .onDrag {
                        draggedItem = imageData[index]
                        return NSItemProvider(object: NSString(string: "\(index)"))
                    }
                    .onDrop(of: [.text], delegate: ImageDropDelegate(
                        item: imageData[index],
                        items: $imageData,
                        draggedItem: $draggedItem,
                        selectedImageIndices: $selectedImageIndices
                    ))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .frame(height: 84)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击空白处取消选择
            if !selectedImageIndices.isEmpty {
                withAnimation {
                    selectedImageIndices.removeAll()
                }
                HapticFeedback.light()
            }
        }
    }
}

// MARK: - 可选择的缩略图
struct SelectableThumbnail: View {
    @EnvironmentObject var appState: AppState
    let imageData: Data
    let index: Int
    @Binding var selectedImageIndices: Set<Int>

    private var isSelected: Bool {
        selectedImageIndices.contains(index)
    }
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)

    var body: some View {
        if let uiImage = UIImage(data: imageData) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? themeColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                    .onTapGesture {
                        toggleSelection()
                    }
                
                // 选中标记
                Circle()
                    .fill(isSelected ? themeColor : Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .overlay(
                        isSelected ? Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white) : nil
                    )
                    .offset(x: 5, y: -5)
                    .allowsHitTesting(false)
            }
        }
    }

    private func toggleSelection() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if isSelected {
                selectedImageIndices.remove(index)
            } else {
                selectedImageIndices.insert(index)
            }
        }
        HapticFeedback.light()
    }
}

// MARK: - 图片拖放代理
struct ImageDropDelegate: DropDelegate {
    let item: Data
    @Binding var items: [Data]
    @Binding var draggedItem: Data?
    @Binding var selectedImageIndices: Set<Int>
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              let fromIndex = items.firstIndex(of: draggedItem),
              let toIndex = items.firstIndex(of: item),
              fromIndex != toIndex else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            // 更新选中的索引
            updateSelectedIndices(from: fromIndex, to: toIndex)
        }
        HapticFeedback.light()
    }
    
    private func updateSelectedIndices(from: Int, to: Int) {
        var newIndices = Set<Int>()
        for index in selectedImageIndices {
            if index == from {
                newIndices.insert(to)
            } else if from < to && index > from && index <= to {
                newIndices.insert(index - 1)
            } else if from > to && index >= to && index < from {
                newIndices.insert(index + 1)
            } else {
                newIndices.insert(index)
            }
        }
        selectedImageIndices = newIndices
    }
}

// MARK: - 文本附件行
struct TextAttachmentRow: View {
    let text: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color.black.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.black.opacity(0.3))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }
}
