import SwiftUI
import SwiftData

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var contact: Contact
    
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showHeader = false
    @State private var showContent = false
    @State private var selectedImageIndex: Int?
    @State private var showImageViewer = false
    @State private var isSyncing = false
    @State private var showSyncAlert = false
    @State private var syncAlertMessage = ""
    
    var body: some View {
        content
    }
    
    private var content: some View {
        ZStack {
            // 白色背景
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部标题栏
                if showHeader {
                    HStack(spacing: 16) {
                        // 返回按钮
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
                        
                        Spacer()
                        
                        // 编辑按钮
                        Button(action: {
                            HapticFeedback.light()
                            showEditSheet = true
                        }) {
                            Text("编辑")
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
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 内容区域
                if showContent {
                    ScrollView {
                        VStack(spacing: 24) {
                            // 头像和基本信息
                            VStack(spacing: 16) {
                                // 头像
                                ZStack {
                                    if let avatarData = contact.avatarData,
                                       let uiImage = UIImage(data: avatarData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
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
                                            .frame(width: 100, height: 100)
                                            .overlay(
                                                Text(String(contact.name.prefix(1)))
                                                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                                                    .foregroundColor(Color.black.opacity(0.6))
                                            )
                                    }
                                }
                                
                                // 名字
                                Text(contact.name)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.white)
                                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                                
                                // 公司和关系
                                if let description = contact.displayDescription {
                                    Text(description)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                                        .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                                        .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                                        .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                                }
                            }
                            .padding(.top, 20)
                            
                            // 联系方式卡片
                            VStack(spacing: 12) {
                                // 电话
                                if let phone = contact.phoneNumber, !phone.isEmpty {
                                    ContactInfoRow(
                                        icon: "phone.fill",
                                        title: "手机号",
                                        content: phone,
                                        showCallButton: true,
                                        action: {
                                            if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                                UIApplication.shared.open(url)
                                            }
                                        }
                                    )
                                }
                                
                                // 公司
                                if let company = contact.company, !company.isEmpty {
                                    ContactInfoRow(icon: "building.2.fill", title: "公司", content: company)
                                }
                                
                                // 身份（职位）
                                if let identity = contact.identity, !identity.isEmpty {
                                    ContactInfoRow(icon: "briefcase.fill", title: "身份", content: identity)
                                }
                                
                                // 兴趣爱好
                                if let hobbies = contact.hobbies, !hobbies.isEmpty {
                                    ContactInfoRow(icon: "heart.fill", title: "兴趣爱好", content: hobbies)
                                }
                                
                                // 与我关系
                                if let relationship = contact.relationship, !relationship.isEmpty {
                                    ContactInfoRow(icon: "person.2.fill", title: "与我关系", content: relationship)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // 附件展示
                            if contact.hasAttachments {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "paperclip")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color.black.opacity(0.5))
                                        
                                        Text("附件 (\(contact.attachmentCount))")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color.black.opacity(0.7))
                                    }
                                    .padding(.horizontal, 20)
                                    
                                    // 图片附件
                                    if let imageData = contact.imageData, !imageData.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(imageData.indices, id: \.self) { index in
                                                    if let uiImage = UIImage(data: imageData[index]) {
                                                        Image(uiImage: uiImage)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 120, height: 120)
                                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                                            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                                                            .onTapGesture {
                                                                selectedImageIndex = index
                                                                showImageViewer = true
                                                                HapticFeedback.light()
                                                            }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 20)
                                        }
                                    }
                                    
                                    // 文本附件
                                    if let textAttachments = contact.textAttachments, !textAttachments.isEmpty {
                                        VStack(spacing: 8) {
                                            ForEach(textAttachments.indices, id: \.self) { index in
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack {
                                                        Text("文本 \(index + 1)")
                                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                            .foregroundColor(Color.black.opacity(0.5))
                                                        Spacer()
                                                    }
                                                    
                                                    Text(textAttachments[index])
                                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                                        .foregroundColor(Color.black.opacity(0.7))
                                                        .lineLimit(3)
                                                }
                                                .padding(12)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(Color.white)
                                                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                            
                            // 操作按钮区域
                            VStack(spacing: 10) {
                                // 同步到系统通讯录按钮
                                Button(action: {
                                    HapticFeedback.light()
                                    syncToSystemContacts()
                                }) {
                                    HStack(spacing: 10) {
                                        if isSyncing {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                                                .scaleEffect(0.9)
                                        } else {
                                            Image(systemName: "person.crop.circle.badge.plus")
                                                .font(.system(size: 18, weight: .semibold))
                                        }
                                        
                                        Text(isSyncing ? "同步中..." : "同步到系统通讯录")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(Color.white)
                                    .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                                    .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                                    .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                                    .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
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
                                .disabled(isSyncing)
                                
                                // 删除按钮
                                Button(action: {
                                    HapticFeedback.light()
                                    showDeleteAlert = true
                                }) {
                                    Text("删除联系人")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.red.opacity(0.8))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color.white)
                                                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
                                        )
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }
                        .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ContactEditView(contact: contact)
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteContact()
            }
        } message: {
            Text("确定要删除联系人「\(contact.name)」吗？")
        }
        .alert("同步结果", isPresented: $showSyncAlert) {
            Button("好的", role: .cancel) { }
        } message: {
            Text(syncAlertMessage)
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let index = selectedImageIndex,
                   let imageData = contact.imageData,
                   index < imageData.count {
                    ContactImageViewerOverlay(imageData: imageData[index], isPresented: $showImageViewer)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.7))
                        Text("图片数据错误")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Text("index: \(selectedImageIndex ?? -1), count: \(contact.imageData?.count ?? 0)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .onTapGesture {
                        showImageViewer = false
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                showHeader = true
            }
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.2)) {
                showContent = true
            }
        }
    }
    
    private func deleteContact() {
        HapticFeedback.medium()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            modelContext.delete(contact)
            try? modelContext.save()
        }
        dismiss()
    }
    
    // 同步到系统通讯录
    private func syncToSystemContacts() {
        isSyncing = true
        
        Task {
            do {
                let manager = ContactsManager.shared
                
                // 检查权限
                let status = manager.checkAuthorizationStatus()
                if status != .authorized {
                    let granted = await manager.requestAccess()
                    if !granted {
                        await MainActor.run {
                            isSyncing = false
                            syncAlertMessage = "需要通讯录权限才能同步，请在系统设置中开启"
                            showSyncAlert = true
                        }
                        return
                    }
                }
                
                // 执行同步
                let result = try await manager.syncToSystemContacts(contact: contact)
                
                await MainActor.run {
                    isSyncing = false
                    
                    switch result {
                    case .success:
                        HapticFeedback.success()
                        syncAlertMessage = "「\(contact.name)」已成功同步到系统通讯录 ✓"
                    case .duplicate:
                        HapticFeedback.warning()
                        syncAlertMessage = "系统通讯录中已存在相同的联系人，跳过同步"
                    }
                    
                    showSyncAlert = true
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    HapticFeedback.error()
                    
                    if let contactError = error as? ContactsError {
                        syncAlertMessage = contactError.localizedDescription
                    } else {
                        syncAlertMessage = "同步失败: \(error.localizedDescription)"
                    }
                    
                    showSyncAlert = true
                }
            }
        }
    }
}

// MARK: - 联系信息行
struct ContactInfoRow: View {
    let icon: String
    let title: String
    let content: String
    var showCallButton: Bool = false
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.2),
                                    Color(red: 0.78, green: 0.98, blue: 0.2).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.5))
                
                Text(content)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                    .lineLimit(3)
            }
            
            Spacer()
            
            // 拨打电话按钮
            if showCallButton, let action = action {
                Button(action: {
                    HapticFeedback.light()
                    action()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.arrow.up.right.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("拨打")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                    .padding(.horizontal, 14)
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
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), radius: 6, x: 0, y: 2)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - 全屏图片查看器（详情页）
struct ContactImageViewerOverlay: View {
    let imageData: Data
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // 背景
            Color.black
                .ignoresSafeArea()

            // 图片
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                // 加载失败提示
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.7))
                    Text("图片加载失败")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .onTapGesture {
            // 单击退出
            isPresented = false
            HapticFeedback.light()
        }
    }
}
