import Foundation
import Contacts
import ContactsUI
import SwiftUI

// 通讯录管理器
class ContactsManager: ObservableObject {
    static let shared = ContactsManager()
    
    private let store = CNContactStore()
    
    // NOTE: 备注现在按你的需求"直写到系统备注"，不再做 [MolyMemo] block 合并。

    private func log(_ message: String) {
#if DEBUG || targetEnvironment(simulator)
        print("[ContactsManager] \(message)")
#endif
    }
    
    private func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func digitsOnly(_ s: String?) -> String {
        trimmed(s).filter { $0.isNumber }
    }
    
    private func isUnauthorizedKeysError(_ error: Error) -> Bool {
        // iOS 18+：部分联系人字段（如 note）可能触发 CNError.Code.unauthorizedKeys
        let ns = error as NSError
        return ns.domain == CNErrorDomain && ns.code == CNError.Code.unauthorizedKeys.rawValue
    }
    
    private func normalizedName(_ s: String) -> String {
        // 统一：忽略空格/换行、大小写差异（用于英文/混合名）
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .lowercased()
    }
    
    private func systemDisplayName(_ c: CNContact) -> String {
        if let formatted = CNContactFormatter.string(from: c, style: .fullName) {
            let t = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        // 兜底：系统通常用 family+given 展示（中文无空格）
        let fallback = "\(c.familyName)\(c.givenName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback
    }

    /// 按 identifier 拉取联系人；可选是否 unify（合并链接联系人）。
    /// - Note: `unifiedContact(withIdentifier:)` 总是 unify=true；在 iOS 18+ 某些权限组合下，
    ///         unify 可能把“未授权的关联记录”合并进来，导致请求 note 等 key 直接 unauthorized。
    private func fetchContactByIdentifier(_ identifier: String,
                                          keysToFetch: [CNKeyDescriptor],
                                          unifyResults: Bool) throws -> CNContact? {
        let id = trimmed(identifier)
        guard !id.isEmpty else { return nil }

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.unifyResults = unifyResults
        request.predicate = CNContact.predicateForContacts(withIdentifiers: [id])

        var result: CNContact? = nil
        try store.enumerateContacts(with: request) { c, stop in
            result = c
            stop.pointee = true
        }
        return result
    }
    
    private func upsertMobilePhone(_ phoneNumber: String?, to mutable: CNMutableContact) {
        let phone = trimmed(phoneNumber)
        guard !phone.isEmpty else { return }
        
        let newValue = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
        var numbers = mutable.phoneNumbers
        
        if let idx = numbers.firstIndex(where: { ($0.label ?? "") == CNLabelPhoneNumberMobile }) {
            numbers[idx] = newValue
        } else if !numbers.isEmpty {
            numbers.insert(newValue, at: 0)
        } else {
            numbers = [newValue]
        }
        mutable.phoneNumbers = numbers
    }
    
    private func upsertPrimaryEmail(_ email: String?, to mutable: CNMutableContact) {
        let e = trimmed(email)
        guard !e.isEmpty else { return }
        let newValue = CNLabeledValue(label: CNLabelWork, value: e as NSString)
        var emails = mutable.emailAddresses
        if emails.isEmpty {
            emails = [newValue]
        } else {
            emails[0] = newValue
        }
        mutable.emailAddresses = emails
    }
    
    private func upsertLocation(_ location: String?, to mutable: CNMutableContact) {
        let loc = trimmed(location)
        guard !loc.isEmpty else { return }
        
        // `postalAddresses` 的元素类型是 `CNLabeledValue<CNPostalAddress>`，
        // 这里显式构造 `CNPostalAddress`，避免泛型不变导致的类型不匹配。
        let addr: CNPostalAddress = {
            let m = CNMutablePostalAddress()
            // 地区是自由文本：避免误拆分省市区，先放 street（系统展示也更直观）
            m.street = loc
            return (m.copy() as? CNPostalAddress) ?? m
        }()
        
        let newValue = CNLabeledValue(label: CNLabelWork, value: addr)
        var addrs = mutable.postalAddresses
        if addrs.isEmpty {
            addrs = [newValue]
        } else {
            addrs[0] = newValue
        }
        mutable.postalAddresses = addrs
    }
    
    private func applyBirthday(_ birthday: String?, to mutable: CNMutableContact) {
        let b = trimmed(birthday)
        guard !b.isEmpty else { return }
        
        // 仅处理 yyyy-MM-dd（人脉详情页当前保存的主格式）；其它格式先不强行写，避免错日期
        let parts = b.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]),
              (1...12).contains(m),
              (1...31).contains(d)
        else { return }
        
        var comp = DateComponents()
        comp.year = y
        comp.month = m
        comp.day = d
        mutable.birthday = comp
    }
    
    private func upsertAppNotesDirectly(to mutable: CNMutableContact, appContact: Contact) {
        // 关键：必须先检查 note key 是否已 fetch，否则访问 .note 会崩溃（CNPropertyNotFetchedException）
        guard mutable.isKeyAvailable(CNContactNoteKey) else {
            log("upsertAppNotesDirectly() note key not available, skip")
            return
        }
        // 需求：直接把 App 的 notes 写到系统通讯录的备注字段
        let n = trimmed(appContact.notes)
        mutable.note = n
        log("upsertAppNotesDirectly() set note='\(n.prefix(30))...'")
    }
    
    private func applyAppContactFields(_ appContact: Contact, to mutable: CNMutableContact, isMolyManaged: Bool) {
        // 姓名：
        // 按你的需求：统一把"全名"写入 givenName（familyName 置空），避免拆分造成锚点丢失
        let n = appContact.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty {
            mutable.givenName = n
            mutable.familyName = ""
        }
        
        // 手机号（支持更新）
        if mutable.isKeyAvailable(CNContactPhoneNumbersKey) {
            upsertMobilePhone(appContact.phoneNumber, to: mutable)
        }
        
        // 公司/职位
        let company = trimmed(appContact.company)
        if !company.isEmpty, mutable.isKeyAvailable(CNContactOrganizationNameKey) { mutable.organizationName = company }
        
        let title = trimmed(appContact.identity)
        if !title.isEmpty, mutable.isKeyAvailable(CNContactJobTitleKey) { mutable.jobTitle = title }
        
        // 邮箱
        if mutable.isKeyAvailable(CNContactEmailAddressesKey) {
            upsertPrimaryEmail(appContact.email, to: mutable)
        }
        
        // 行业：系统通讯录没有"行业"字段，使用 departmentName（更接近语义）
        let industry = trimmed(appContact.industry)
        if !industry.isEmpty, mutable.isKeyAvailable(CNContactDepartmentNameKey) { mutable.departmentName = industry }
        
        // 地区：自由文本写到 postalAddresses
        if mutable.isKeyAvailable(CNContactPostalAddressesKey) {
            upsertLocation(appContact.location, to: mutable)
        }
        
        // 生日
        if mutable.isKeyAvailable(CNContactBirthdayKey) {
            applyBirthday(appContact.birthday, to: mutable)
        }
        
        // 头像
        if let avatarData = appContact.avatarData, mutable.isKeyAvailable(CNContactImageDataKey) { mutable.imageData = avatarData }
        
        // 备注
        upsertAppNotesDirectly(to: mutable, appContact: appContact)
    }
    
    // 请求通讯录权限
    func requestAccess() async -> Bool {
        let status = checkAuthorizationStatus()
        log("requestAccess() status=\(status.rawValue)")
        do {
            // iOS 18+ 需要使用新的权限请求方式
            if #available(iOS 18.0, *) {
                let granted = try await store.requestAccess(for: .contacts)
                // 等待一下让权限生效
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                log("requestAccess() granted=\(granted)")
                return granted
            } else {
                let granted = try await store.requestAccess(for: .contacts)
                log("requestAccess() granted=\(granted)")
                return granted
            }
        } catch {
            log("requestAccess() error=\(error.localizedDescription)")
            return false
        }
    }

    /// 启动时前置请求：仅当状态为 `.notDetermined` 才会触发系统弹窗
    /// - Important: 需要在主线程调用，确保系统权限弹窗可展示
    @MainActor
    func requestAccessIfNotDetermined(source: String) async {
        let status = checkAuthorizationStatus()
        log("requestAccessIfNotDetermined(source=\(source)) status=\(status.rawValue)")
        guard status == .notDetermined else { return }
        _ = await requestAccess()
    }
    
    // 检查当前权限状态
    func checkAuthorizationStatus() -> CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }
    
    // 获取所有联系人
    func fetchAllContacts() async throws -> [CNContact] {
        let status = checkAuthorizationStatus()
        
        guard status == .authorized else {
            throw ContactsError.notAuthorized
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [CNContact] = []
        
        try store.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }
        
        return contacts
    }

    /// 按 identifier 获取"可用于系统联系人详情展示"的 unified contact。
    /// - Note: keys 使用 `CNContactViewController.descriptorForRequiredKeys()`，避免详情页缺字段/崩溃。
    func fetchSystemContactForDetail(identifier: String) async throws -> CNContact {
        let status = checkAuthorizationStatus()
        guard status == .authorized else {
            log("fetchSystemContactForDetail() not authorized")
            throw ContactsError.notAuthorized
        }
        let id = trimmed(identifier)
        guard !id.isEmpty else {
            log("fetchSystemContactForDetail() empty identifier")
            throw ContactsError.fetchFailed
        }
        // iOS 26 / Swift 6：descriptorForRequiredKeys() 变为 MainActor 隔离
        let descriptor: CNKeyDescriptor = await MainActor.run { CNContactViewController.descriptorForRequiredKeys() }
        let keys: [CNKeyDescriptor] = [descriptor]
        log("fetchSystemContactForDetail() id=\(id)")
        return try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
    }
    
    // 将CNContact转换为Contact模型
    func convertToContact(_ cnContact: CNContact) -> Contact {
        // 组合姓名
        let fullName = "\(cnContact.familyName)\(cnContact.givenName)".trimmingCharacters(in: .whitespaces)
        let name = fullName.isEmpty ? "未命名" : fullName
        
        // 获取第一个电话号码
        let phoneNumber = cnContact.phoneNumbers.first?.value.stringValue
        
        // 获取公司
        let company = cnContact.organizationName.isEmpty ? nil : cnContact.organizationName
        
        // 获取头像
        var avatarData: Data? = nil
        if cnContact.imageDataAvailable {
            avatarData = cnContact.imageData
        }
        
        return Contact(
            name: name,
            phoneNumber: phoneNumber,
            company: company,
            avatarData: avatarData
        )
    }
    
    // MARK: - 同步到系统通讯录
    
    private func containsMolyMarker(_ contact: CNContact) -> Bool {
        // 备注已改为"直写 App notes -> system note"，不再使用 [MolyMemo] 标记。
        // 保留该函数以避免大范围改动旧逻辑，但始终返回 false。
        return false
    }
    
    /// 用「名字 + MolyMemo 标记」找系统联系人（仅用于避免重复创建/丢失 identifier 的兜底）。
    private func findMolySystemContactByName(_ name: String) -> CNContact? {
        let n = trimmed(name)
        guard !n.isEmpty else { return nil }
        
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor
        ]
        
        do {
            let predicate = CNContact.predicateForContacts(matchingName: n)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            let molyContacts = contacts.filter { containsMolyMarker($0) }
            if molyContacts.count == 1 {
                let c = molyContacts[0]
                log("findMolySystemContactByName() matched 1 moly contact id=\(c.identifier)")
                return c
            }
            if molyContacts.count > 1 {
                log("findMolySystemContactByName() multiple moly matches, skip. count=\(molyContacts.count)")
            }
            return nil
        } catch {
            log("findMolySystemContactByName() error=\(error.localizedDescription)")
            return nil
        }
    }
    
    /// 更新系统通讯录里的"已存在联系人"，不允许创建新联系人。
    /// - Returns: 成功更新时返回系统联系人 identifier；无法定位系统联系人则返回 nil
    func updateSystemContact(contact: Contact, source: String? = nil) async throws -> String? {
        let status = checkAuthorizationStatus()
        guard status == .authorized else {
            log("updateSystemContact() not authorized source=\(trimmed(source))")
            throw ContactsError.notAuthorized
        }
        
        let linkedId = trimmed(contact.systemContactIdentifier)
        log("updateSystemContact() start source=\(trimmed(source)) name=\(contact.name) phone=\(trimmed(contact.phoneNumber)) systemId=\(linkedId)")
        
        // 1) 强锚点：按 identifier 更新
        if !linkedId.isEmpty {
            do {
                let updatedId = try updateByIdentifier(linkedId, appContact: contact)
                log("updateSystemContact() updated by identifier ok id=\(updatedId)")
                return updatedId
            } catch {
                // identifier 可能失效（用户删除了联系人），继续走弱匹配
                log("updateSystemContact() update by identifier failed, fallback. id=\(linkedId) error=\(error.localizedDescription)")
            }
        }
        
        // 2) 弱匹配（不创建）：先按手机号找；找不到再按名字找
        if let candidate = findCandidateForUpdate(name: contact.name, phoneNumber: contact.phoneNumber) {
            let id = trimmed(candidate.identifier)
            guard !id.isEmpty else { return nil }
            
            if let mutable = candidate.mutableCopy() as? CNMutableContact {
                let moly = containsMolyMarker(candidate)
                applyAppContactFields(contact, to: mutable, isMolyManaged: moly)
                let saveRequest = CNSaveRequest()
                saveRequest.update(mutable)
                try store.execute(saveRequest)
                log("updateSystemContact() updated candidate id=\(id)")
                return id
            }
            log("updateSystemContact() candidate mutableCopy failed id=\(id)")
        } else {
            log("updateSystemContact() no candidate found (phone/name not unique or no match)")
        }
        
        log("updateSystemContact() not found, skip (no create)")
        return nil
    }
    
    private func updateByIdentifier(_ identifier: String, appContact: Contact) throws -> String {
        let id = trimmed(identifier)
        guard !id.isEmpty else { throw ContactsError.fetchFailed }
        
        // 包含 note 的 keyset（首选）
        let keysetWithNote: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor
        ]
        // 不包含 note 的 keyset（note 被系统限制时回退）
        let keysetNoNote: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor
        ]
        // 可能被系统限制的字段：birthday / postal / email（不同系统/权限组合差异很大）
        let keysetNoBirthday: [CNKeyDescriptor] = keysetNoNote.filter { ($0 as? NSString) != CNContactBirthdayKey as NSString }
        let keysetNoPostal: [CNKeyDescriptor] = keysetNoBirthday.filter { ($0 as? NSString) != CNContactPostalAddressesKey as NSString }
        let keysetNoEmail: [CNKeyDescriptor] = keysetNoPostal.filter { ($0 as? NSString) != CNContactEmailAddressesKey as NSString }
        // 最保底：确保姓名/手机号/公司/职位可更新
        let keysetMinimal: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor
        ]
        
        let keysets: [(name: String, keys: [CNKeyDescriptor])] = [
            ("withNote(full)", keysetWithNote),
            ("noNote", keysetNoNote),
            ("noBirthday", keysetNoBirthday),
            ("noPostal", keysetNoPostal),
            ("noEmail", keysetNoEmail),
            ("minimal(name+phone+company+title)", keysetMinimal)
        ]
        
        let existing: CNContact
        var lastError: Error? = nil
        var fetchedKeysetName: String? = nil
        var fetchedContact: CNContact? = nil
        for (name, keys) in keysets {
            do {
                // 先用 unifyResults=false 抓取，避免合并“未授权关联记录”导致 note 等 key unauthorized
                if let c = try fetchContactByIdentifier(id, keysToFetch: keys, unifyResults: false) {
                    fetchedContact = c
                    fetchedKeysetName = "\(name)+unify:false"
                    break
                }
                // 再兜底 unifyResults=true（等价于 unifiedContact）
                if let c = try fetchContactByIdentifier(id, keysToFetch: keys, unifyResults: true) {
                    fetchedContact = c
                    fetchedKeysetName = "\(name)+unify:true"
                    break
                }
            } catch {
                lastError = error
                if isUnauthorizedKeysError(error) {
                    log("updateByIdentifier() keyset '\(name)' unauthorized, try next. id=\(id)")
                    continue
                }
                throw error
            }
        }
        if let fetchedContact {
            existing = fetchedContact
            log("updateByIdentifier() fetched ok via keyset '\(fetchedKeysetName ?? "unknown")' id=\(id)")
        } else {
            throw lastError ?? ContactsError.fetchFailed
        }
        
        guard let mutable = existing.mutableCopy() as? CNMutableContact else { throw ContactsError.fetchFailed }
        
        // 已绑定 identifier：按你的需求统一"givenName=全名 + familyName 置空"，修复历史拆分导致后续匹配失败
        applyAppContactFields(appContact, to: mutable, isMolyManaged: true)
        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        try store.execute(saveRequest)
        log("updateByIdentifier() updated id=\(id)")
        return id
    }
    
    /// "更新模式"下的候选查找：允许手机号存在时也回退到名字匹配，但必须足够确定（避免误更新）。
    private func findCandidateForUpdate(name: String, phoneNumber: String?) -> CNContact? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor
        ]
        
        // 1) 手机号匹配（若存在）
        let phoneDigits = digitsOnly(phoneNumber)
        if !phoneDigits.isEmpty {
            do {
                let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phoneDigits))
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                log("findCandidateForUpdate() phoneDigits=\(phoneDigits) candidates=\(contacts.count)")
                if contacts.count == 1 {
                    log("findCandidateForUpdate() matched by phone (unique) id=\(contacts[0].identifier)")
                    return contacts[0]
                }
                // 多个候选：只接受"确切包含相同 digits 的那个"
                if let exact = contacts.first(where: { digitsOnly($0.phoneNumbers.first?.value.stringValue) == phoneDigits }) {
                    log("findCandidateForUpdate() matched by phone (exact) id=\(exact.identifier)")
                    return exact
                }
                log("findCandidateForUpdate() phone candidates not unique / no exact match")
            } catch {
                log("findCandidateForUpdate() phone search error=\(error.localizedDescription)")
            }
        }
        
        // 2) 回退：同名 + MolyMemo 标记（仅唯一命中）
        if let moly = findMolySystemContactByName(name) {
            return moly
        }
        
        // 3) 回退：名字精确匹配（仅唯一命中）
        let n = trimmed(name)
        guard !n.isEmpty else { return nil }
        do {
            let predicate = CNContact.predicateForContacts(matchingName: n)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            log("findCandidateForUpdate() name=\(n) candidates=\(contacts.count)")
            let target = normalizedName(n)
            let exact = contacts.filter { normalizedName(systemDisplayName($0)) == target }
            if exact.count == 1 {
                log("findCandidateForUpdate() matched by name (unique) id=\(exact[0].identifier)")
                return exact[0]
            }
            if exact.count > 1 {
                log("findCandidateForUpdate() name exact matches >1, skip")
            } else {
                log("findCandidateForUpdate() name exact match not found")
            }
        } catch {
            log("findCandidateForUpdate() name search error=\(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// 查找系统通讯录中是否已存在相同联系人（优先手机号，其次名字）。
    /// - Returns: 匹配到的 CNContact（若无则为 nil）
    func findMatchingSystemContact(name: String, phoneNumber: String?) async throws -> CNContact? {
        let status = checkAuthorizationStatus()
        guard status == .authorized else {
            log("findMatchingSystemContact() not authorized")
            throw ContactsError.notAuthorized
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor
        ]

        // 如果有手机号，优先用手机号匹配
        let phoneDigits = digitsOnly(phoneNumber)
        if !phoneDigits.isEmpty {
            log("findMatchingSystemContact() by phone digits=\(phoneDigits)")
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phoneDigits))
            do {
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                log("findMatchingSystemContact() phone candidates=\(contacts.count)")
                if let exact = contacts.first(where: { digitsOnly($0.phoneNumbers.first?.value.stringValue) == phoneDigits }) {
                    log("findMatchingSystemContact() matched by phone id=\(exact.identifier)")
                    return exact
                }
                // 兜底：手机号对不上/搜不到时，允许回退到名字，但只在"足够确定"时命中
                if let candidate = findCandidateForUpdate(name: name, phoneNumber: nil) {
                    return candidate
                }
                return contacts.first
            } catch {
                log("findMatchingSystemContact() phone search error=\(error.localizedDescription)")
                return findCandidateForUpdate(name: name, phoneNumber: nil)
            }
        }
        
        // 否则用名字匹配（不带手机号场景）
        log("findMatchingSystemContact() by name=\(name)")
        let predicate = CNContact.predicateForContacts(matchingName: name)
        
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            log("findMatchingSystemContact() candidates=\(contacts.count)")
            
            // 检查是否有完全匹配的联系人
            for contact in contacts {
                let fullName = "\(contact.familyName)\(contact.givenName)".trimmingCharacters(in: .whitespaces)
                
                // 名字匹配
                if fullName == name {
                    log("findMatchingSystemContact() matched by name id=\(contact.identifier)")
                    return contact
                }
                
                // 如果有手机号，检查手机号是否匹配
                if !phoneDigits.isEmpty {
                    for contactPhone in contact.phoneNumbers {
                        let contactPhoneNumber = contactPhone.value.stringValue.filter { $0.isNumber }
                        if contactPhoneNumber == phoneDigits {
                            log("findMatchingSystemContact() matched by phone id=\(contact.identifier)")
                            return contact
                        }
                    }
                }
            }
            
            log("findMatchingSystemContact() no match")
            return nil
        } catch {
            log("findMatchingSystemContact() error=\(error.localizedDescription)")
            return nil
        }
    }
    
    // 同步联系人到系统通讯录
    func syncToSystemContacts(contact: Contact) async throws -> SyncResult {
        let status = checkAuthorizationStatus()
        guard status == .authorized else {
            log("syncToSystemContacts() not authorized")
            throw ContactsError.notAuthorized
        }
        log("syncToSystemContacts() start name=\(contact.name) phone=\(trimmed(contact.phoneNumber)) systemId=\(trimmed(contact.systemContactIdentifier))")
        
        // 1) 若已绑定系统联系人 identifier：直接更新该联系人（包含手机号更新）
        let linkedId = trimmed(contact.systemContactIdentifier)
        if !linkedId.isEmpty {
            do {
                let keys: [CNKeyDescriptor] = [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactEmailAddressesKey as CNKeyDescriptor,
                    CNContactOrganizationNameKey as CNKeyDescriptor,
                    CNContactDepartmentNameKey as CNKeyDescriptor,
                    CNContactJobTitleKey as CNKeyDescriptor,
                    CNContactPostalAddressesKey as CNKeyDescriptor,
                    CNContactBirthdayKey as CNKeyDescriptor,
                    CNContactNoteKey as CNKeyDescriptor,
                    CNContactImageDataKey as CNKeyDescriptor,
                    CNContactImageDataAvailableKey as CNKeyDescriptor
                ]
                
                let existing = try store.unifiedContact(withIdentifier: linkedId, keysToFetch: keys)
                guard let mutable = existing.mutableCopy() as? CNMutableContact else {
                    log("syncToSystemContacts() failed to mutableCopy for id=\(linkedId)")
                    return .success(identifier: linkedId)
                }
                
                let moly = containsMolyMarker(existing)
                applyAppContactFields(contact, to: mutable, isMolyManaged: moly)
                
                let saveRequest = CNSaveRequest()
                saveRequest.update(mutable)
                try store.execute(saveRequest)
                log("syncToSystemContacts() updated existing system contact id=\(linkedId)")
                return .success(identifier: linkedId)
            } catch {
                // identifier 可能已失效（用户删除了系统联系人）：继续走匹配/创建
                log("syncToSystemContacts() update by identifier failed, fallback. id=\(linkedId) error=\(error.localizedDescription)")
            }
        }
        
        // 先匹配，避免重复创建
        if let existing = try await findMatchingSystemContact(name: contact.name, phoneNumber: contact.phoneNumber) {
            let id = trimmed(existing.identifier)
            log("syncToSystemContacts() matched existing id=\(id)")
            
            if let mutable = existing.mutableCopy() as? CNMutableContact {
                let moly = containsMolyMarker(existing)
                applyAppContactFields(contact, to: mutable, isMolyManaged: moly)
                let saveRequest = CNSaveRequest()
                saveRequest.update(mutable)
                do {
                    try store.execute(saveRequest)
                    log("syncToSystemContacts() updated matched system contact id=\(id)")
                    return .success(identifier: id.isEmpty ? nil : id)
                } catch {
                    log("syncToSystemContacts() update matched error=\(error.localizedDescription)")
                    // 更新失败：保底返回 identifier，避免调用侧重复创建
                    return .duplicate(identifier: id.isEmpty ? nil : id)
                }
            } else {
                // mutableCopy 失败：保底返回 identifier
                return .duplicate(identifier: id.isEmpty ? nil : id)
            }
        }
        
        // 创建新的联系人
        let newContact = CNMutableContact()
        // 新建：按你的需求，姓名始终"全写到 givenName"，不拆分
        applyAppContactFields(contact, to: newContact, isMolyManaged: true)
        
        // 保存到通讯录
        let saveRequest = CNSaveRequest()
        saveRequest.add(newContact, toContainerWithIdentifier: nil)
        
        do {
            try store.execute(saveRequest)
            let id = trimmed(newContact.identifier)
            log("syncToSystemContacts() saved id=\(id)")
            return .success(identifier: id.isEmpty ? nil : id)
        } catch {
            log("syncToSystemContacts() save error=\(error.localizedDescription)")
            throw ContactsError.saveFailed
        }
    }
}

// 同步结果
enum SyncResult {
    case success(identifier: String?)      // 同步成功（可能拿到系统联系人 identifier）
    case duplicate(identifier: String?)    // 已存在重复联系人（尽量返回 identifier）
}

// 错误类型
enum ContactsError: Error, LocalizedError {
    case notAuthorized
    case fetchFailed
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有通讯录访问权限"
        case .fetchFailed:
            return "获取联系人失败"
        case .saveFailed:
            return "保存联系人失败"
        }
    }
}

// 系统联系人包装类（用于列表显示）
struct SystemContact: Identifiable {
    let id = UUID()
    let cnContact: CNContact
    var isSelected: Bool = false
    var isDuplicate: Bool = false  // 是否与已有联系人重复

    var displayName: String {
        let fullName = "\(cnContact.familyName)\(cnContact.givenName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? "未命名" : fullName
    }

    var phoneNumber: String? {
        return cnContact.phoneNumbers.first?.value.stringValue
    }

    var company: String? {
        let org = cnContact.organizationName
        return org.isEmpty ? nil : org
    }
}
