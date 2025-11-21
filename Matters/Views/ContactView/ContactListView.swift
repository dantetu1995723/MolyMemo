import SwiftUI
import SwiftData

struct ContactListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Query(sort: \Contact.name) private var allContacts: [Contact]

    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var selectedContact: Contact?
    @State private var showHeader = false
    @State private var showContent = false
    @State private var showAddButton = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showImportSheet = false
    @State private var isLoading = true
    
    // 分组的联系人
    private var groupedContacts: [(String, [Contact])] {
        let contacts = filteredContacts
        
        // 按首字母分组
        let grouped = Dictionary(grouping: contacts) { $0.nameInitial }
        
        // 排序：#在最后
        let sorted = grouped.sorted { lhs, rhs in
            if lhs.key == "#" { return false }
            if rhs.key == "#" { return true }
            return lhs.key < rhs.key
        }
        
        return sorted
    }
    
    // 过滤后的联系人
    private var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return allContacts
        }
        return allContacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(searchText) ||
            contact.company?.localizedCaseInsensitiveContains(searchText) == true ||
            contact.phoneNumber?.contains(searchText) == true
        }
    }
    
    // 字母索引列表
    private var indexLetters: [String] {
        let letters = groupedContacts.map { $0.0 }
        return letters
    }
    
    var body: some View {
        ZStack {
            // 白色背景
            Color.white.ignoresSafeArea()
            
            // 加载指示器
            if isLoading {
                LoadingView()
                    .transition(.opacity)
            }
            
            VStack(spacing: 0) {
                // 顶部标题栏
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
                        
                        // 标题和数量
                        VStack(alignment: .leading, spacing: 2) {
                            Text("人脉")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(Color.white)
                                .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                            
                            if allContacts.count > 0 {
                                Text("\(allContacts.count) 位联系人")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.white)
                                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                            }
                        }
                        
                        Spacer()
                        
                        // 从通讯录导入按钮
                        Button(action: {
                            HapticFeedback.light()
                            showImportSheet = true
                        }) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
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
                    }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .opacity(showHeader ? 1 : 0)
                
                // 搜索框
                SearchBar(text: $searchText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .opacity(showContent ? 1 : 0)
                
                // 联系人列表
                ZStack(alignment: .trailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                ForEach(groupedContacts, id: \.0) { initial, contacts in
                                        Section(header: SectionHeaderView(letter: initial)) {
                                            ForEach(contacts) { contact in
                                                ContactRowView(contact: contact)
                                                    .id(contact.id) // 给每个联系人添加ID用于滚动定位
                                                    .onTapGesture {
                                                        HapticFeedback.light()
                                                        selectedContact = contact
                                                    }
                                            }
                                    }
                                    .id(initial) // Section的ID用于滚动定位
                                }
                                
                                // 空状态
                                if allContacts.isEmpty {
                                    EmptyContactView(onAddContact: { showAddSheet = true })
                                        .padding(.top, 80)
                                }
                            }
                            .padding(.bottom, 180)
                            .opacity(showContent ? 1 : 0)
                        }
                        .onAppear {
                            scrollProxy = proxy
                        }
                    }
                    
                    // 右侧字母索引
                    if !groupedContacts.isEmpty {
                        AlphabetIndexView(letters: indexLetters) { letter in
                            HapticFeedback.light()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scrollProxy?.scrollTo(letter, anchor: .top)
                            }
                        }
                        .padding(.trailing, 8)
                        .opacity(showContent ? 1 : 0)
                    }
                }
            }
            
            // 底部浮动添加按钮
            VStack {
                Spacer()
                
                Button(action: {
                        HapticFeedback.medium()
                        showAddSheet = true
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                            
                            Text("添加新联系人")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
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
                                .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.4), radius: 20, x: 0, y: 8)
                        )
                    }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showAddButton ? 1 : 0)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ContactEditView()
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailView(contact: contact)
        }
        .sheet(isPresented: $showImportSheet) {
            ContactImportView()
        }
        .navigationBarHidden(true)
        .onAppear {
            // 创建示例联系人
            createSampleContactsIfNeeded()
            
            // 等待数据准备完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // 先关闭loading
                withAnimation(.easeOut(duration: 0.25)) {
                    isLoading = false
                }
                
                // loading关闭后，依次显示各个元素
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showHeader = true
                    }
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08)) {
                        showContent = true
                    }
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.16)) {
                        showAddButton = true
                    }
                    
                    // 检查是否需要滚动到指定联系人
                    if let contactId = appState.scrollToContactId {
                        // 延迟滚动，确保视图已经完全加载
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            print("📍 滚动到联系人 ID: \(contactId)")
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy?.scrollTo(contactId, anchor: .center)
                            }
                            // 清除滚动标记
                            appState.scrollToContactId = nil
                        }
                    }
                }
            }
        }
    }
    
    // 创建示例联系人
    private func createSampleContactsIfNeeded() {
        guard allContacts.isEmpty else { return }
        
        let sampleContacts = [
            Contact(name: "张伟", phoneNumber: "138****1234", company: "科技公司", hobbies: "阅读、跑步", relationship: "同事"),
            Contact(name: "李娜", phoneNumber: "139****5678", company: "设计工作室", hobbies: "绘画、摄影", relationship: "朋友"),
            Contact(name: "王强", phoneNumber: "136****9012", company: "互联网公司", hobbies: "编程、游戏", relationship: "客户"),
            Contact(name: "赵敏", phoneNumber: "137****3456", company: "咨询公司", hobbies: "旅游", relationship: "同事"),
            Contact(name: "Alex Chen", phoneNumber: "188****7890", hobbies: "创业、投资", relationship: "朋友"),
            Contact(name: "Bob Wilson", phoneNumber: "186****2345", company: "Global Corp", relationship: "客户")
        ]
        
        for contact in sampleContacts {
            modelContext.insert(contact)
        }
        
        try? modelContext.save()
    }
}

// MARK: - 搜索框
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.black.opacity(0.4))
            
            TextField("搜索联系人", text: $text)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(Color.black.opacity(0.85))
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    HapticFeedback.light()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.black.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - 分组标题
struct SectionHeaderView: View {
    let letter: String
    
    var body: some View {
        HStack {
            Text(letter)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.95))
    }
}

// MARK: - 联系人行视图
struct ContactRowView: View {
    @Bindable var contact: Contact

    // 副内容项结构
    struct SecondaryInfoItem {
        let text: String
        let isAttachment: Bool
        let count: Int

        init(text: String) {
            self.text = text
            self.isAttachment = false
            self.count = 0
        }

        init(attachmentCount: Int) {
            self.text = ""
            self.isAttachment = true
            self.count = attachmentCount
        }
    }

    // 是否有副内容
    var hasSecondaryInfo: Bool {
        !secondaryInfoItems.isEmpty
    }

    // 副内容项列表
    var secondaryInfoItems: [SecondaryInfoItem] {
        var items: [SecondaryInfoItem] = []

        // 公司
        if let company = contact.company, !company.isEmpty {
            items.append(SecondaryInfoItem(text: company))
        }

        // 关系
        if let relationship = contact.relationship, !relationship.isEmpty {
            items.append(SecondaryInfoItem(text: relationship))
        }

        // 兴趣爱好
        if let hobbies = contact.hobbies, !hobbies.isEmpty {
            items.append(SecondaryInfoItem(text: hobbies))
        }

        // 附件
        if contact.hasAttachments {
            items.append(SecondaryInfoItem(attachmentCount: contact.attachmentCount))
        }

        return items
    }

    var body: some View {
        HStack(spacing: 16) {
            // 头像
            ZStack {
                if let avatarData = contact.avatarData,
                   let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    // 默认头像 - 显示首字母
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
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(contact.name.prefix(1)))
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.black.opacity(0.6))
                        )
                }
            }
            
            // 联系人信息
            VStack(alignment: .leading, spacing: 4) {
                // 名字
                Text(contact.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))

                // 副内容：统一在一行横向排列
                if hasSecondaryInfo {
                    HStack(spacing: 6) {
                        ForEach(Array(secondaryInfoItems.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Text("·")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.black.opacity(0.35))
                            }

                            if item.isAttachment {
                                // 附件图标
                                HStack(spacing: 3) {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 11, weight: .medium))
                                    if item.count > 1 {
                                        Text("\(item.count)")
                                            .font(.system(size: 13, weight: .regular))
                                    }
                                }
                                .foregroundColor(Color.black.opacity(0.4))
                            } else {
                                // 文本信息
                                Text(item.text)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.black.opacity(0.4))
                            }
                        }
                    }
                    .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 右箭头
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

// MARK: - 字母索引视图
struct AlphabetIndexView: View {
    let letters: [String]
    let onTap: (String) -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.5))
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap(letter)
                    }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.8))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - 空状态视图
struct EmptyContactView: View {
    let onAddContact: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color.black.opacity(0.2))
            
            Text("暂无联系人")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color.white)
                .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                .shadow(color: Color.black, radius: 0, x: 1, y: 1)
            
            Text("点击下方按钮添加新联系人")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color.white)
                .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
        }
    }
}

// MARK: - 加载视图
struct LoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            // 旋转的圆圈
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3),
                                Color(red: 0.78, green: 0.98, blue: 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 1.0, blue: 0.25),
                                Color(red: 0.78, green: 0.98, blue: 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            
            Text("加载中...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.5))
        }
        .onAppear {
            isAnimating = true
        }
    }
}

