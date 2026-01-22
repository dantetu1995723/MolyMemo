import SwiftUI
import SwiftData
import Foundation

// 联系人数据模型
@Model
final class Contact {
    var id: UUID
    /// 账号隔离键（建议用手机号或 userId）。旧库可能为空，迁移时会补齐。
    var ownerKey: String?
    /// 后端 contact id（字符串/数字/uuid 都可能）；用于与后端详情/更新/删除对齐
    var remoteId: String?
    /// 系统通讯录（CNContact）identifier：仅用于单向同步/匹配系统联系人详情
    var systemContactIdentifier: String?
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
    /// 背景速览（后端字段：background）
    var background: String?  // 背景速览
    var notes: String?  // 备注/详细描述
    
    // 附件数据
    @Attribute(.externalStorage) var avatarData: Data?  // 头像
    @Attribute(.externalStorage) var imageData: [Data]?  // 截图附件
    var textAttachments: [String]?  // 文本附件
    
    var createdAt: Date
    var lastModified: Date
    
    /// 软删除/废弃标记：用于“删除=变灰划杠”而不真正移除（保持与聊天室卡片一致）
    var isObsolete: Bool = false
    
    init(
        name: String,
        ownerKey: String? = nil,
        remoteId: String? = nil,
        systemContactIdentifier: String? = nil,
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
        background: String? = nil,
        notes: String? = nil,
        avatarData: Data? = nil,
        imageData: [Data]? = nil,
        textAttachments: [String]? = nil
    ) {
        self.id = UUID()
        self.ownerKey = ownerKey
        self.remoteId = remoteId
        self.systemContactIdentifier = systemContactIdentifier
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
        self.background = background
        self.notes = notes
        self.avatarData = avatarData
        self.imageData = imageData
        self.textAttachments = textAttachments
        self.createdAt = Date()
        self.lastModified = Date()
        self.isObsolete = false
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

