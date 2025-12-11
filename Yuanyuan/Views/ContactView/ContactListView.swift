import SwiftUI
import SwiftData

struct ContactListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Query(sort: \Contact.name) private var allContacts: [Contact]

    @State private var searchText = ""
    // 外部绑定的添加弹窗状态（由底部tab栏控制）
    @Binding var showAddSheet: Bool
    @State private var selectedContact: Contact?
    @State private var showHeader = false
    @State private var showContent = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showImportSheet = false
    @State private var isLoading = true
    
    init(showAddSheet: Binding<Bool> = .constant(false)) {
        self._showAddSheet = showAddSheet
    }
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
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
            // 渐变背景
            ModuleBackgroundView(themeColor: themeColor)
            
            // 加载指示器
            if isLoading {
                LoadingView()
                    .transition(.opacity)
            }
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    // 搜索栏和导入按钮 - 同一行
                    if showHeader && showContent {
                        HStack(spacing: 12) {
                            ContactSearchBar(text: $searchText)
                            
                            Button(action: {
                                HapticFeedback.light()
                                showImportSheet = true
                            }) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                                    .frame(width: 40, height: 40)
                                    .background(GlassButtonBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    } else if showHeader {
                        HStack {
                            Spacer()
                            Button(action: {
                                HapticFeedback.light()
                                showImportSheet = true
                            }) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                                    .frame(width: 40, height: 40)
                                    .background(GlassButtonBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    } else if showContent {
                        ContactSearchBar(text: $searchText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    
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
                                .padding(.bottom, 120)
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
            }
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(
                title: "联系人",
                themeColor: themeColor,
                onBack: { dismiss() },
                trailingIcon: "plus",
                trailingAction: { showAddSheet = true }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            ContactEditView()
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailView(contact: contact)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportSheet) {
            ContactImportView()
                .presentationDragIndicator(.visible)
        }
        .toolbar(.hidden, for: .navigationBar)
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

// MARK: - 搜索框 - 液态玻璃风格
struct ContactSearchBar: View {
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
            ZStack {
                // 液态玻璃基础
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.85), location: 0.0),
                                .init(color: Color.white.opacity(0.65), location: 0.5),
                                .init(color: Color.white.opacity(0.75), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // 表面高光
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.4), location: 0.0),
                                .init(color: Color.white.opacity(0.15), location: 0.2),
                                .init(color: Color.clear, location: 0.5)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // 晶体边框
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.9), location: 0.0),
                                .init(color: Color.white.opacity(0.3), location: 0.5),
                                .init(color: Color.white.opacity(0.6), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.white.opacity(0.5), radius: 6, x: 0, y: -2)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

// MARK: - 分组标题 - 液态玻璃风格
struct SectionHeaderView: View {
    let letter: String
    
    var body: some View {
        HStack {
            Text(letter)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - 联系人行视图
struct ContactRowView: View {
    @EnvironmentObject var appState: AppState
    @Bindable var contact: Contact

    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)

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
            // 头像 - 液态玻璃风格
            ZStack {
                if let avatarData = contact.avatarData,
                   let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    // 默认头像 - 显示首字母，液态玻璃风格
                    ZStack {
                        Circle()
                            .fill(themeColor.opacity(0.3))
                        
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                        
                        Text(String(contact.name.prefix(1)))
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                    }
                    .frame(width: 48, height: 48)
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
                                    .foregroundColor(themeColor.opacity(0.8))
                            } else {
                                // 文本信息
                                Text(item.text)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.black.opacity(0.5))
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
                .foregroundColor(themeColor.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // 液态玻璃基础
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.88), location: 0.0),
                                .init(color: Color.white.opacity(0.68), location: 0.5),
                                .init(color: Color.white.opacity(0.78), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // 表面高光
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.45), location: 0.0),
                                .init(color: Color.white.opacity(0.15), location: 0.2),
                                .init(color: Color.clear, location: 0.5)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // 晶体边框
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.9), location: 0.0),
                                .init(color: Color.white.opacity(0.35), location: 0.5),
                                .init(color: Color.white.opacity(0.65), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.white.opacity(0.5), radius: 6, x: 0, y: -2)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

// MARK: - 字母索引视图 - 液态玻璃风格
struct AlphabetIndexView: View {
    let letters: [String]
    let onTap: (String) -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.55))
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
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.65)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            }
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - 空状态视图
struct EmptyContactView: View {
    let onAddContact: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color.black.opacity(0.15))
            
            Text("暂无联系人")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.5))
            
            Text("点击下方按钮添加新联系人")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color.black.opacity(0.35))
        }
    }
}

// MARK: - 加载视图
struct LoadingView: View {
    @EnvironmentObject var appState: AppState
    @State private var isAnimating = false
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    var body: some View {
        VStack(spacing: 24) {
            // 旋转的圆圈
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                themeColor.opacity(0.3),
                                themeColor
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
                                themeColor,
                                themeColor
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
                .foregroundColor(.white)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

