import Foundation
import Contacts
import SwiftUI

// 通讯录管理器
class ContactsManager: ObservableObject {
    static let shared = ContactsManager()
    
    private let store = CNContactStore()
    
    // 请求通讯录权限
    func requestAccess() async -> Bool {
        do {
            // iOS 18+ 需要使用新的权限请求方式
            if #available(iOS 18.0, *) {
                let granted = try await store.requestAccess(for: .contacts)
                print(granted ? "✅ 通讯录权限已授予" : "⚠️ 通讯录权限被拒绝")
                // 等待一下让权限生效
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                return granted
            } else {
                let granted = try await store.requestAccess(for: .contacts)
                print(granted ? "✅ 通讯录权限已授予" : "⚠️ 通讯录权限被拒绝")
                return granted
            }
        } catch {
            print("❌ 请求通讯录权限失败: \(error)")
            return false
        }
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
        
        print("✅ 从通讯录获取了 \(contacts.count) 个联系人")
        return contacts
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
    
    // 检查通讯录中是否已存在相同联系人
    func checkDuplicate(name: String, phoneNumber: String?) async throws -> Bool {
        let status = checkAuthorizationStatus()
        guard status == .authorized else {
            throw ContactsError.notAuthorized
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        
        let predicate: NSPredicate
        
        // 如果有手机号，优先用手机号匹配
        if let phone = phoneNumber?.filter({ $0.isNumber }), !phone.isEmpty {
            predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone))
        } else {
            // 否则用名字匹配
            predicate = CNContact.predicateForContacts(matchingName: name)
        }
        
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            
            // 检查是否有完全匹配的联系人
            for contact in contacts {
                let fullName = "\(contact.familyName)\(contact.givenName)".trimmingCharacters(in: .whitespaces)
                
                // 名字匹配
                if fullName == name {
                    return true
                }
                
                // 如果有手机号，检查手机号是否匹配
                if let phone = phoneNumber?.filter({ $0.isNumber }), !phone.isEmpty {
                    for contactPhone in contact.phoneNumbers {
                        let contactPhoneNumber = contactPhone.value.stringValue.filter { $0.isNumber }
                        if contactPhoneNumber == phone {
                            return true
                        }
                    }
                }
            }
            
            return false
        } catch {
            print("❌ 检查重复联系人失败: \(error)")
            return false
        }
    }
    
    // 同步联系人到系统通讯录
    func syncToSystemContacts(contact: Contact) async throws -> SyncResult {
        let status = checkAuthorizationStatus()
        guard status == .authorized else {
            throw ContactsError.notAuthorized
        }
        
        // 检查是否重复
        let isDuplicate = try await checkDuplicate(name: contact.name, phoneNumber: contact.phoneNumber)
        if isDuplicate {
            return .duplicate
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
            print("✅ 联系人「\(contact.name)」已同步到系统通讯录")
            return .success
        } catch {
            print("❌ 保存联系人到系统通讯录失败: \(error)")
            throw ContactsError.saveFailed
        }
    }
}

// 同步结果
enum SyncResult {
    case success      // 同步成功
    case duplicate    // 已存在重复联系人
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

