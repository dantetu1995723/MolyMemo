import SwiftUI
import SwiftData
import Foundation

// 联系人数据模型
@Model
final class Contact {
    var id: UUID
    var name: String  // 名字（昵称）- 必填
    var phoneNumber: String?  // 手机号
    var company: String?  // 公司
    var identity: String?  // 身份（职位/职务）
    var hobbies: String?  // 兴趣爱好
    var relationship: String?  // 与我关系
    var email: String?  // 邮箱
    var birthday: String?  // 生日
    var gender: String?  // 性别
    var industry: String?  // 行业
    var location: String?  // 地区
    var notes: String?  // 备注/详细描述
    
    // 附件数据
    @Attribute(.externalStorage) var avatarData: Data?  // 头像
    @Attribute(.externalStorage) var imageData: [Data]?  // 截图附件
    var textAttachments: [String]?  // 文本附件
    
    var createdAt: Date
    var lastModified: Date
    
    init(
        name: String,
        phoneNumber: String? = nil,
        company: String? = nil,
        identity: String? = nil,
        hobbies: String? = nil,
        relationship: String? = nil,
        email: String? = nil,
        birthday: String? = nil,
        gender: String? = nil,
        industry: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        avatarData: Data? = nil,
        imageData: [Data]? = nil,
        textAttachments: [String]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.phoneNumber = phoneNumber
        self.company = company
        self.identity = identity
        self.hobbies = hobbies
        self.relationship = relationship
        self.email = email
        self.birthday = birthday
        self.gender = gender
        self.industry = industry
        self.location = location
        self.notes = notes
        self.avatarData = avatarData
        self.imageData = imageData
        self.textAttachments = textAttachments
        self.createdAt = Date()
        self.lastModified = Date()
    }
    
    // 获取名字的首字母（用于分组）
    var nameInitial: String {
        guard !name.isEmpty else { return "#" }
        
        // 处理中文拼音
        let pinyin = name.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? name
        
        guard let pinyinFirstChar = pinyin.uppercased().first else { return "#" }
        
        // 判断是否是A-Z字母
        if pinyinFirstChar.isLetter && pinyinFirstChar.isASCII {
            return String(pinyinFirstChar)
        }
        
        return "#"
    }
    
    // 显示用的简短描述
    var displayDescription: String? {
        var parts: [String] = []
        
        if let company = company, !company.isEmpty {
            parts.append(company)
        }
        
        if let relationship = relationship, !relationship.isEmpty {
            parts.append(relationship)
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    
    // 是否有附件
    var hasAttachments: Bool {
        let hasImages = imageData?.isEmpty == false
        let hasTexts = textAttachments?.isEmpty == false
        return hasImages || hasTexts
    }
    
    // 附件总数
    var attachmentCount: Int {
        var count = 0
        if let images = imageData {
            count += images.count
        }
        if let texts = textAttachments {
            count += texts.count
        }
        return count
    }
}

