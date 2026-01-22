import SwiftUI
import SwiftData
import Foundation

// 报销数据模型
@Model
final class Expense {
    var id: UUID
    /// 账号隔离键（建议用手机号或 userId）。旧库可能为空，迁移时会补齐。
    var ownerKey: String?
    var amount: Double  // 金额
    var title: String  // 抬头/标题
    var category: String?  // 类别（餐饮、交通、住宿等）
    var event: String?  // 事件（报销项目发生情形）
    var occurredAt: Date  // 发生时间
    var reimburseAt: Date?  // 报销时间
    var isReimbursed: Bool  // 是否已报销
    var notes: String?  // 备注
    
    // 附件数据
    @Attribute(.externalStorage) var imageData: [Data]?  // 截图附件（发票、收据等）
    var textAttachments: [String]?  // 文本附件
    
    // 关联的待办事项ID
    var linkedTodoId: UUID?
    
    var createdAt: Date
    var lastModified: Date
    
    init(
        amount: Double,
        title: String,
        category: String? = nil,
        event: String? = nil,
        occurredAt: Date,
        notes: String? = nil,
        imageData: [Data]? = nil,
        textAttachments: [String]? = nil,
        ownerKey: String? = nil
    ) {
        self.id = UUID()
        self.ownerKey = ownerKey
        self.amount = amount
        self.title = title
        self.category = category
        self.event = event
        self.occurredAt = occurredAt
        self.reimburseAt = nil
        self.isReimbursed = false
        self.notes = notes
        self.imageData = imageData
        self.textAttachments = textAttachments
        self.createdAt = Date()
        self.lastModified = Date()
    }
    
    // 格式化金额显示
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "¥0.00"
    }
    
    // 格式化日期显示
    var occurredDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: occurredAt)
    }
    
    var occurredTimeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: occurredAt)
    }
    
    var reimburseDateText: String? {
        guard let date = reimburseAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
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
    
    // 标记为已报销
    func markAsReimbursed() {
        isReimbursed = true
        reimburseAt = Date()
        lastModified = Date()
    }
    
    // 取消报销
    func cancelReimbursement() {
        isReimbursed = false
        reimburseAt = nil
        lastModified = Date()
    }
}

