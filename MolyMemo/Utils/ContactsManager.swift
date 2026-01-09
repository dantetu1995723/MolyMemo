import Foundation
import Contacts
import ContactsUI
import SwiftUI

// 通讯录管理器
class ContactsManager: ObservableObject {
    static let shared = ContactsManager()
    
    private let store = CNContactStore()

    private func log(_ message: String) {
#if DEBUG
        print("[ContactsManager] \(message)")
#endif
    }
    
    private func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func digitsOnly(_ s: String?) -> String {
        trimmed(s).filter { $0.isNumber }
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

    /// 按 identifier 获取“可用于系统联系人详情展示”的 unified contact。
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
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        
        let predicate: NSPredicate
        
        // 如果有手机号，优先用手机号匹配
        let phoneDigits = digitsOnly(phoneNumber)
        if !phoneDigits.isEmpty {
            log("findMatchingSystemContact() by phone digits=\(phoneDigits)")
            predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phoneDigits))
        } else {
            // 否则用名字匹配
            log("findMatchingSystemContact() by name=\(name)")
            predicate = CNContact.predicateForContacts(matchingName: name)
        }
        
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
        log("syncToSystemContacts() start name=\(contact.name) phone=\(trimmed(contact.phoneNumber))")
        
        // 先匹配，避免重复创建
        if let existing = try await findMatchingSystemContact(name: contact.name, phoneNumber: contact.phoneNumber) {
            let id = trimmed(existing.identifier)
            log("syncToSystemContacts() duplicate id=\(id)")
            return .duplicate(identifier: id.isEmpty ? nil : id)
        }
        
        // 创建新的联系人
        let newContact = CNMutableContact()
        
        // 设置姓名（中文姓名处理）
        if contact.name.count > 1 {
            // 假设第一个字是姓
            newContact.familyName = String(contact.name.prefix(1))
            newContact.givenName = String(contact.name.dropFirst())
        } else {
            newContact.givenName = contact.name
        }
        
        // 设置手机号
        if let phoneNumber = contact.phoneNumber, !phoneNumber.isEmpty {
            let phone = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phoneNumber))
            newContact.phoneNumbers = [phone]
        }
        
        // 设置公司
        if let company = contact.company, !company.isEmpty {
            newContact.organizationName = company
        }
        
        // 设置职位
        if let identity = contact.identity, !identity.isEmpty {
            newContact.jobTitle = identity
        }
        
        // 设置备注（包含兴趣爱好和关系）
        var noteComponents: [String] = []
        if let hobbies = contact.hobbies, !hobbies.isEmpty {
            noteComponents.append("兴趣爱好: \(hobbies)")
        }
        if let relationship = contact.relationship, !relationship.isEmpty {
            noteComponents.append("与我关系: \(relationship)")
        }
        if !noteComponents.isEmpty {
            newContact.note = noteComponents.joined(separator: "\n")
        }
        
        // 设置头像
        if let avatarData = contact.avatarData {
            newContact.imageData = avatarData
        }
        
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

