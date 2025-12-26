import SwiftUI
import SwiftData

// MARK: - 资料库：直接渲染“聊天室卡片”（不额外加 UI 要素）

// 日程卡片资料库（列表版：一条事件一行）
struct ScheduleCardLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredScheduleCardBatch.createdAt, order: .reverse) private var batches: [StoredScheduleCardBatch]

    @Binding var showAddSheet: Bool
    private let themeColor = Color(white: 0.55)

    init(showAddSheet: Binding<Bool> = .constant(false)) {
        self._showAddSheet = showAddSheet
    }

    var body: some View {
        ZStack {
            ModuleBackgroundView(themeColor: themeColor)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(batches) { batch in
                        ScheduleCardBatchList(batch: batch)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(title: "日程", themeColor: themeColor, onBack: { dismiss() })
        }
        .toolbar(.hidden, for: .navigationBar)
        // 模块不提供新增入口：统一用底部 tab 栏 +（或聊天室生成）触发
        .onChange(of: showAddSheet) { _, newValue in
            if newValue { showAddSheet = false }
        }
    }
}

private struct ScheduleCardBatchList: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var batch: StoredScheduleCardBatch
    @State private var events: [ScheduleEvent] = []

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(events.indices, id: \.self) { index in
                ScheduleListRow(event: events[index])
                    .contentShape(Rectangle())

                if index < events.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                }
            }
        }
        .onAppear {
            events = batch.decodedEvents()
        }
        .onChange(of: events) { _, newValue in
            batch.update(events: newValue)
            try? modelContext.save()
        }
    }
}

private struct ScheduleListRow: View {
    let event: ScheduleEvent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.06))
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
            }
            .frame(width: 36, height: 36)
            .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(1)

                Text(event.timeRange)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer()

            if event.hasConflict {
                Text("冲突")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.06)))
                    .padding(.trailing, 16)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 12)
    }
}

// 联系人卡片资料库（列表版）
struct ContactCardLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredContactCardBatch.createdAt, order: .reverse) private var batches: [StoredContactCardBatch]

    @Binding var showAddSheet: Bool
    private let themeColor = Color(white: 0.55)

    init(showAddSheet: Binding<Bool> = .constant(false)) {
        self._showAddSheet = showAddSheet
    }

    var body: some View {
        ZStack {
            ModuleBackgroundView(themeColor: themeColor)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(batches) { batch in
                        ContactCardBatchList(batch: batch)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(title: "联系人", themeColor: themeColor, onBack: { dismiss() })
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: showAddSheet) { _, newValue in
            if newValue { showAddSheet = false }
        }
    }
}

private struct ContactCardBatchList: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var batch: StoredContactCardBatch
    @State private var contacts: [ContactCard] = []
    @State private var selectedIndex: Int? = nil
    @State private var selectedContact: Contact? = nil
    @Query private var allContacts: [Contact]

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(contacts.indices, id: \.self) { index in
                ContactListRow(contact: contacts[index])
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticFeedback.light()
                        selectedIndex = index
                        if index < contacts.count {
                            selectedContact = findOrCreateContact(from: contacts[index])
                        }
                    }

                if index < contacts.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                }
            }
        }
        .onAppear {
            contacts = batch.decodedContacts()
        }
        .onChange(of: contacts) { _, newValue in
            batch.update(contacts: newValue)
            try? modelContext.save()
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailView(contact: contact)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
    
    private func findOrCreateContact(from card: ContactCard) -> Contact {
        // 先尝试根据 ID 查找
        if let existing = allContacts.first(where: { $0.id == card.id }) {
            // 绑定远端 id（用于后续详情/更新/删除）
            if let rid = card.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
                if (existing.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.remoteId = rid
                    try? modelContext.save()
                }
            }
            let imp = (card.impression ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !imp.isEmpty {
                let current = (existing.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if current.isEmpty {
                    existing.notes = imp
                    try? modelContext.save()
                } else if !current.contains(imp) {
                    existing.notes = current + "\n\n" + imp
                    try? modelContext.save()
                }
            }
            return existing
        }
        
        // 如果找不到，尝试根据名字和电话查找
        if let phone = card.phone, !phone.isEmpty,
           let existing = allContacts.first(where: { $0.name == card.name && $0.phoneNumber == phone }) {
            if let rid = card.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
                if (existing.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.remoteId = rid
                    try? modelContext.save()
                }
            }
            let imp = (card.impression ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !imp.isEmpty {
                let current = (existing.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if current.isEmpty {
                    existing.notes = imp
                    try? modelContext.save()
                } else if !current.contains(imp) {
                    existing.notes = current + "\n\n" + imp
                    try? modelContext.save()
                }
            }
            return existing
        }
        
        // 如果都找不到，创建一个新的 Contact
        let newContact = Contact(
            name: card.name,
            remoteId: {
                let rid = (card.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return rid.isEmpty ? nil : rid
            }(),
            phoneNumber: card.phone,
            company: card.company,
            identity: card.title,
            notes: {
                let imp = (card.impression ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !imp.isEmpty { return imp }
                let n = (card.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return n.isEmpty ? nil : n
            }(),
            avatarData: card.avatarData
        )
        
        modelContext.insert(newContact)
        try? modelContext.save()
        
        return newContact
    }
}

private struct ContactSelection: Identifiable {
    let id: UUID
    let index: Int
}

private struct ContactListRow: View {
    let contact: ContactCard

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.06))

                if let data = contact.avatarData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .frame(width: 36, height: 36)
            .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(1)

                let sub = [contact.company, contact.title].compactMap { s in
                    guard let s, !s.isEmpty else { return nil }
                    return s
                }.joined(separator: " · ")

                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.black.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.25))
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}

// 发票卡片资料库（对应“报销发票”模块，列表版）
struct InvoiceCardLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredInvoiceCardBatch.createdAt, order: .reverse) private var batches: [StoredInvoiceCardBatch]

    @Binding var showAddSheet: Bool
    private let themeColor = Color(white: 0.55)

    init(showAddSheet: Binding<Bool> = .constant(false)) {
        self._showAddSheet = showAddSheet
    }

    var body: some View {
        ZStack {
            ModuleBackgroundView(themeColor: themeColor)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(batches) { batch in
                        InvoiceCardBatchList(batch: batch)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(title: "报销发票", themeColor: themeColor, onBack: { dismiss() })
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: showAddSheet) { _, newValue in
            if newValue { showAddSheet = false }
        }
    }
}

private struct InvoiceCardBatchList: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var batch: StoredInvoiceCardBatch
    @State private var invoices: [InvoiceCard] = []
    @State private var selectedIndex: Int? = nil

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(invoices.indices, id: \.self) { index in
                InvoiceListRow(invoice: invoices[index])
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticFeedback.light()
                        selectedIndex = index
                    }

                if index < invoices.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                }
            }
        }
        .onAppear {
            invoices = batch.decodedInvoices()
        }
        .onChange(of: invoices) { _, newValue in
            batch.update(invoices: newValue)
            try? modelContext.save()
        }
        .sheet(item: Binding(
            get: {
                guard let idx = selectedIndex, idx < invoices.count else { return nil }
                return InvoiceSelection(id: invoices[idx].id, index: idx)
            },
            set: { (_: InvoiceSelection?) in selectedIndex = nil }
        )) { selection in
            InvoiceDetailSheet(
                invoice: $invoices[selection.index],
                onDelete: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if let idx = invoices.firstIndex(where: { $0.id == selection.id }) {
                            invoices.remove(at: idx)
                        }
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct InvoiceSelection: Identifiable {
    let id: UUID
    let index: Int
}

private struct InvoiceListRow: View {
    let invoice: InvoiceCard

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: invoice.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.06))
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
            }
            .frame(width: 36, height: 36)
            .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.merchantName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(1)

                Text([dateText, invoice.type, invoice.invoiceNumber].joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer()

            Text(String(format: "¥%.2f", invoice.amount))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.75))
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}


