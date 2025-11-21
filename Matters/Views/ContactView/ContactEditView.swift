import SwiftUI
import SwiftData
import PhotosUI

struct ContactEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
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
                                                .fill(Color(red: 0.6, green: 0.75, blue: 0.2))
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
                                                .fill(Color(red: 0.6, green: 0.75, blue: 0.2))
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
                                                        textAttachments.remove(at: index)
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
                        saveContact()
                    }) {
                        Text("保存")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white)
                            .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                            .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                            .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                            .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
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
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black, lineWidth: 2)
                                    )
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(name.isEmpty)
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
    
    private func saveContact() {
        guard !name.isEmpty else { return }
        
        HapticFeedback.success()
        
        if let existingContact = contact {
            // 编辑现有联系人
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
        } else {
            // 创建新联系人
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
        }
        
        try? modelContext.save()
        dismiss()
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
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3),
                                Color(red: 0.78, green: 0.98, blue: 0.2).opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color.black.opacity(0.4))
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
                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
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
    let imageData: Data
    let index: Int
    @Binding var selectedImageIndices: Set<Int>

    private var isSelected: Bool {
        selectedImageIndices.contains(index)
    }

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
                            .stroke(isSelected ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                    .onTapGesture {
                        toggleSelection()
                    }
                
                // 选中标记
                Circle()
                    .fill(isSelected ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .overlay(
                        isSelected ? Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black) : nil
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
