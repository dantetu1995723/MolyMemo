import Foundation
import SwiftData

/// 统一：把聊天/资料库里的 `ContactCard` 同步到本地 SwiftData `Contact`。
/// 目标：
/// - 卡片补充字段（如 phone）后，详情页读取同一个 `Contact` 时能立即看到更新
/// - 仅在“确实有变更”时保存，避免频繁写盘
@MainActor
enum ContactCardLocalSync {
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

        if changed {
            contact.lastModified = Date()
            try? modelContext.save()
        }
        return changed
    }

    private static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


