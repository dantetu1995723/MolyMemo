import SwiftUI
import SwiftData

struct ContactListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Query(sort: \Contact.name) private var allContacts: [Contact]
    @State private var selectedContact: Contact?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isLoading = true
    @State private var remoteIsLoading: Bool = false
    @State private var remoteErrorText: String? = nil
    @State private var deleteErrorText: String? = nil
    
    // 追踪正在删除的联系人 ID（用于显示行内 loading）
    @State private var deletingContactIds: Set<UUID> = []
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    // 分组的联系人
    private var groupedContacts: [(String, [Contact])] {
        let contacts = allContacts
        
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
    
    // 字母索引列表
    private var indexLetters: [String] {
        let letters = groupedContacts.map { $0.0 }
        return letters
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color(white: 0.98).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 自定义导航栏
                ModuleNavigationBar(
                    title: "联系人",
                    themeColor: themeColor,
                    onBack: { dismiss() }
                )
                
                if let remoteErrorText, !remoteErrorText.isEmpty {
                    Text(remoteErrorText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
                
                if let deleteErrorText, !deleteErrorText.isEmpty {
                    Text(deleteErrorText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
                
                // 列表区域
                ZStack(alignment: .trailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                ForEach(groupedContacts, id: \.0) { initial, contacts in
                                    Section(header: SectionHeaderView(letter: initial)) {
                                        ForEach(contacts) { contact in
                                            ContactRowView(
                                                contact: contact,
                                                isDeleting: deletingContactIds.contains(contact.id),
                                                onDelete: {
                                                    requestDelete(contact)
                                                }
                                            )
                                            .onTapGesture {
                                                HapticFeedback.light()
                                                selectedContact = contact
                                            }
                                            .id(contact.id)
                                        }
                                    }
                                    .id(initial)
                                }
                                
                                // 空状态
                                if allContacts.isEmpty {
                                    EmptyContactView()
                                        .padding(.top, 80)
                                }
                                
                                // 底部留白
                                Color.clear.frame(height: 120)
                            }
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
                        .padding(.trailing, 10)
                    }
                }
            }
            
            // 加载指示器
            if isLoading {
                LoadingView()
                    .transition(.opacity)
                    .background(Color(white: 0.98).ignoresSafeArea())
            }
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailView(contact: contact)
                .presentationDragIndicator(.visible)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // 等待数据准备完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.25)) {
                    isLoading = false
                }
                
                // 检查是否需要滚动到指定联系人
                if let contactId = appState.scrollToContactId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy?.scrollTo(contactId, anchor: .center)
                        }
                        appState.scrollToContactId = nil
                    }
                }
            }
            
            // 与「日程」一致：进入模块即拉取后端列表；失败则仍展示本地缓存
            Task { await reloadRemoteContacts() }
        }
    }

    // MARK: - 后端拉取联系人列表（分页）
    @MainActor
    private func reloadRemoteContacts() async {
        remoteErrorText = nil
        
        // 1) 先用缓存秒开（不必每次进来都打网络）
        let base = ContactService.ListParams(page: nil, pageSize: nil, search: nil, relationshipType: nil)
        if let cached = await ContactService.peekAllContacts(maxPages: 5, pageSize: 100, baseParams: base) {
            upsertRemoteContacts(cached.value)
            // 即使缓存新鲜，也后台静默刷新，确保数据及时更新
            Task {
                await reloadRemoteContactsFromNetwork(base: base, showError: false)
            }
            return
        }
        
        // 2) 首次无缓存：走网络（可以显示错误提示）
        await reloadRemoteContactsFromNetwork(base: base, showError: true)
    }
    
    @MainActor
    private func reloadRemoteContactsFromNetwork(base: ContactService.ListParams, showError: Bool) async {
        remoteIsLoading = true
        defer { remoteIsLoading = false }
        
        do {
            let all = try await ContactService.fetchContactListAllPages(
                maxPages: 5,
                pageSize: 100,
                baseParams: base
            )
            upsertRemoteContacts(all)
        } catch {
            if showError {
                remoteErrorText = "后端联系人获取失败：\(error.localizedDescription)"
            }
        }
    }
    
    @MainActor
    private func upsertRemoteContacts(_ cards: [ContactCard]) {
        guard !cards.isEmpty else { return }
        
        for card in cards {
            let rid = (card.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1) 优先按 remoteId 命中
            if !rid.isEmpty, let existing = allContacts.first(where: { ($0.remoteId ?? "") == rid }) {
                applyRemote(card: card, to: existing)
                continue
            }
            
            // 2) 若 remoteId 是 UUID，且本地 id 命中，也算同一个
            if let u = UUID(uuidString: rid), let existing = allContacts.first(where: { $0.id == u }) {
                if (existing.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.remoteId = rid
                }
                applyRemote(card: card, to: existing)
                continue
            }
            
            // 3) 兜底：按 name + phone
            if let phone = card.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
               !phone.isEmpty,
               let existing = allContacts.first(where: { $0.name == card.name && ($0.phoneNumber ?? "") == phone })
            {
                if !rid.isEmpty, (existing.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.remoteId = rid
                }
                applyRemote(card: card, to: existing)
                continue
            }
            
            // 4) 新建
            let newContact = Contact(
                name: card.name,
                remoteId: rid.isEmpty ? nil : rid,
                phoneNumber: card.phone,
                company: card.company,
                identity: card.title,
                email: card.email,
                notes: {
                    let n = (card.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return n.isEmpty ? nil : n
                }()
            )
            
            // 若后端 id 是 UUID，用它稳定映射
            if rid.isEmpty == false, let u = UUID(uuidString: rid) {
                newContact.id = u
            }
            
            modelContext.insert(newContact)
        }
        
        try? modelContext.save()
    }
    
    private func applyRemote(card: ContactCard, to contact: Contact) {
        // 只补齐/覆盖“有值字段”，避免把本地自维护字段清空
        contact.name = card.name
        if let v = card.company?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { contact.company = v }
        if let v = card.title?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { contact.identity = v }
        if let v = card.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { contact.phoneNumber = v }
        if let v = card.email?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { contact.email = v }
        
        let n = (card.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty {
            let current = (contact.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                contact.notes = n
            } else if !current.contains(n) {
                contact.notes = current + "\n\n" + n
            }
        }
        
        contact.lastModified = Date()
    }
    
    // MARK: - 左滑删除（与详情页同一条后端路径）
    private func requestDelete(_ contact: Contact) {
        Task { @MainActor in
            deletingContactIds.insert(contact.id)
            defer { deletingContactIds.remove(contact.id) }
            
            do {
                deleteErrorText = nil
                if let current = selectedContact, current.id == contact.id {
                    selectedContact = nil
                }
                try await DeleteActions.deleteContact(contact, modelContext: modelContext)
            } catch {
                deleteErrorText = "删除失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 分组标题 - 清爽风格
struct SectionHeaderView: View {
    let letter: String
    
    var body: some View {
        HStack {
            Text(letter)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            Color(white: 0.98).opacity(0.95)
        )
    }
}

// MARK: - 联系人行视图
struct ContactRowView: View {
    @EnvironmentObject var appState: AppState
    @Bindable var contact: Contact
    var isDeleting: Bool = false
    var onDelete: () -> Void

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
        HStack(spacing: 12) {
            // 头像
            ZStack {
                if let avatarData = contact.avatarData,
                   let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    // 默认头像
                    ZStack {
                        Circle()
                            .fill(themeColor.opacity(0.12))
                        
                        Text(String(contact.name.prefix(1)))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(themeColor.opacity(0.8))
                    }
                    .frame(width: 44, height: 44)
                }
            }
            
            // 联系人信息
            VStack(alignment: .leading, spacing: 2) {
                // 名字
                Text(contact.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary)

                // 副内容
                if hasSecondaryInfo {
                    HStack(spacing: 4) {
                        ForEach(Array(secondaryInfoItems.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Text("·")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }

                            if item.isAttachment {
                                HStack(spacing: 2) {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 10))
                                    if item.count > 1 {
                                        Text("\(item.count)")
                                            .font(.system(size: 12))
                                    }
                                }
                                .foregroundColor(themeColor.opacity(0.6))
                            } else {
                                Text(item.text)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 现代感删除按钮
            ZStack {
                if isDeleting {
                    ProgressView()
                        .tint(.red)
                        .scaleEffect(0.8)
                } else {
                    Button {
                        HapticFeedback.medium()
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.red.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - 字母索引视图
struct AlphabetIndexView: View {
    let letters: [String]
    let onTap: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.4))
                    .frame(width: 24, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap(letter)
                    }
            }
        }
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.8))
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - 空状态视图
struct EmptyContactView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color.black.opacity(0.15))
            
            Text("暂无联系人")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.5))
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

