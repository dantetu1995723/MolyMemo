import Foundation
import SwiftData
import Contacts

/// 统一：把聊天/资料库里的 `ContactCard` 同步到本地 SwiftData `Contact`。
/// 目标：
/// - 卡片补充字段（如 phone）后，详情页读取同一个 `Contact` 时能立即看到更新
/// - 仅在“确实有变更”时保存，避免频繁写盘
@MainActor
enum ContactCardLocalSync {
    private static func log(_ message: String) {
#if DEBUG
        print("[ContactCardLocalSync] \(message)")
#endif
    }
    
    /// 根据 card 在本地查找或创建 `Contact`，并把 card 的“有值字段”补齐写回。
    static func findOrCreateContact(from card: ContactCard, allContacts: [Contact], modelContext: ModelContext) -> Contact {
        // 1) 优先按本地 id 命中（我们在创建时会对齐 id）
        if let existing = allContacts.first(where: { $0.id == card.id }) {
            applyCard(card, to: existing, modelContext: modelContext)
            return existing
        }

        // 2) 兜底：按 name + phone 命中（避免历史数据没有对齐 id 的情况）
        let phone = trimmed(card.phone)
        if !phone.isEmpty,
           let existing = allContacts.first(where: { $0.name == card.name && trimmed($0.phoneNumber) == phone })
        {
            applyCard(card, to: existing, modelContext: modelContext)
            return existing
        }

        // 3) 新建（用 card 直接填充，保证详情页可用）
        let newContact = Contact(
            name: card.name,
            remoteId: {
                let rid = trimmed(card.remoteId)
                return rid.isEmpty ? nil : rid
            }(),
            phoneNumber: {
                let v = trimmed(card.phone)
                return v.isEmpty ? nil : v
            }(),
            company: {
                let v = trimmed(card.company)
                return v.isEmpty ? nil : v
            }(),
            identity: {
                let v = trimmed(card.title)
                return v.isEmpty ? nil : v
            }(),
            email: {
                let v = trimmed(card.email)
                return v.isEmpty ? nil : v
            }(),
            birthday: {
                let v = trimmed(card.birthday)
                return v.isEmpty ? nil : v
            }(),
            gender: {
                let v = trimmed(card.gender)
                return v.isEmpty ? nil : v
            }(),
            industry: {
                let v = trimmed(card.industry)
                return v.isEmpty ? nil : v
            }(),
            location: {
                let v = trimmed(card.location)
                return v.isEmpty ? nil : v
            }(),
            notes: {
                // 备注：只使用后端 note/notes（ContactCard.notes）回填，避免把 impression 混进备注
                let v = trimmed(card.notes)
                return v.isEmpty ? nil : v
            }(),
            avatarData: card.avatarData
        )

        // 关键：让 id 跟卡片 id 对齐，后续能稳定复用同一联系人
        newContact.id = card.id
        modelContext.insert(newContact)
        try? modelContext.save()
        
        // 单向同步到系统通讯录：仅新建且有手机号时尝试（不阻塞主流程）
        triggerSystemContactSyncIfNeeded(for: newContact, modelContext: modelContext, allowCreate: true)
        return newContact
    }

    /// 将 card 中“有意义的字段”补齐/覆盖到本地 Contact（不做清空）。
    @discardableResult
    static func applyCard(_ card: ContactCard, to contact: Contact, modelContext: ModelContext) -> Bool {
        var changed = false

        let rid = trimmed(card.remoteId)
        if !rid.isEmpty, trimmed(contact.remoteId) != rid {
            contact.remoteId = rid
            changed = true
        }

        let phone = trimmed(card.phone)
        if !phone.isEmpty, trimmed(contact.phoneNumber) != phone {
            contact.phoneNumber = phone
            changed = true
        }

        let company = trimmed(card.company)
        if !company.isEmpty, trimmed(contact.company) != company {
            contact.company = company
            changed = true
        }

        let title = trimmed(card.title)
        if !title.isEmpty, trimmed(contact.identity) != title {
            contact.identity = title
            changed = true
        }

        let email = trimmed(card.email)
        if !email.isEmpty, trimmed(contact.email) != email {
            contact.email = email
            changed = true
        }
        
        let industry = trimmed(card.industry)
        if !industry.isEmpty, trimmed(contact.industry) != industry {
            contact.industry = industry
            changed = true
        }
        
        let location = trimmed(card.location)
        if !location.isEmpty, trimmed(contact.location) != location {
            contact.location = location
            changed = true
        }
        
        let gender = trimmed(card.gender)
        if !gender.isEmpty, trimmed(contact.gender) != gender {
            contact.gender = gender
            changed = true
        }
        
        let birthday = trimmed(card.birthday)
        if !birthday.isEmpty, trimmed(contact.birthday) != birthday {
            contact.birthday = birthday
            changed = true
        }

        // 备注：只使用后端 note/notes（ContactCard.notes）回填，避免把 impression 混进备注
        let n = trimmed(card.notes)
        if !n.isEmpty {
            let current = trimmed(contact.notes)
            if current.isEmpty {
                contact.notes = n
                changed = true
            } else if !current.contains(n) {
                contact.notes = current + "\n\n" + n
                changed = true
            }
        }

        if let avatar = card.avatarData, avatar != contact.avatarData {
            contact.avatarData = avatar
            changed = true
        }
        
        // 软删除/废弃态同步：卡片被删除后，工具箱联系人列表也应置灰划杠
        if card.isObsolete, !contact.isObsolete {
            contact.isObsolete = true
            changed = true
        }

        if changed {
            contact.lastModified = Date()
            try? modelContext.save()
            
            // 同步到系统通讯录：
            // - 已绑定 identifier：允许更新（例如手机号/公司/备注变化）
            // - 未绑定：至少需要手机号才尝试匹配/创建，避免仅按名字误匹配
            let phone = trimmed(contact.phoneNumber)
            let linked = trimmed(contact.systemContactIdentifier)
            if !linked.isEmpty || !phone.isEmpty {
                // 卡片回写属于“更新链路”：不要因为手机号变更导致系统通讯录重复创建
                triggerSystemContactSyncIfNeeded(for: contact, modelContext: modelContext, allowCreate: false)
            }
        }
        return changed
    }

    private static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func triggerSystemContactSyncIfNeeded(for contact: Contact, modelContext: ModelContext, allowCreate: Bool) {
        let phone = trimmed(contact.phoneNumber)
        let linked = trimmed(contact.systemContactIdentifier)
        
        // 规则：
        // - 已绑定 identifier：允许无手机号也去更新（例如修改公司/备注等）
        // - 未绑定 identifier：至少需要手机号才尝试匹配/创建（避免仅按名字误匹配）
        if linked.isEmpty, phone.isEmpty { return }
        
        log("triggerSystemContactSyncIfNeeded() start name=\(contact.name) phone=\(phone) id=\(contact.id)")
        
        // 重要：不要 detached。通讯录权限弹窗在后台任务里可能不会弹，导致永远拿不到授权。
        Task(priority: .utility) {
            let granted = await ContactsManager.shared.requestAccess()
            guard granted else {
                log("triggerSystemContactSyncIfNeeded() requestAccess denied")
                return
            }
            
            do {
                if allowCreate {
                    let result = try await ContactsManager.shared.syncToSystemContacts(contact: contact)
                    let id: String? = {
                        switch result {
                        case .success(let identifier): return identifier
                        case .duplicate(let identifier): return identifier
                        }
                    }()
                    if let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await MainActor.run {
                            contact.systemContactIdentifier = id
                            try? modelContext.save()
                        }
                        log("triggerSystemContactSyncIfNeeded() upsert ok id=\(id)")
                    } else {
                        log("triggerSystemContactSyncIfNeeded() upsert finished but identifier is nil/empty")
                    }
                } else {
                    // 更新模式：不允许新建，找不到就跳过
                    if let id = try await ContactsManager.shared.updateSystemContact(contact: contact),
                       !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        await MainActor.run {
                            contact.systemContactIdentifier = id
                            try? modelContext.save()
                        }
                        log("triggerSystemContactSyncIfNeeded() update ok id=\(id)")
                    } else {
                        log("triggerSystemContactSyncIfNeeded() update skipped (not found)")
                    }
                }
            } catch {
                log("triggerSystemContactSyncIfNeeded() error=\(error.localizedDescription)")
            }
        }
    }
}


