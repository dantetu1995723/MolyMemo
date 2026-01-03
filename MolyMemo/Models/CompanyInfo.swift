import SwiftUI
import SwiftData
import Foundation

// 公司开票信息数据模型
@Model
final class CompanyInfo {
    var id: UUID
    var companyName: String  // 公司名称（抬头）
    var taxNumber: String?  // 税号
    var phoneNumber: String?  // 手机号
    var email: String?  // 邮箱
    var address: String?  // 地址
    var bankName: String?  // 开户行
    var bankAccount: String?  // 银行账号
    
    var createdAt: Date
    var lastModified: Date
    
    init(
        companyName: String,
        taxNumber: String? = nil,
        phoneNumber: String? = nil,
        email: String? = nil,
        address: String? = nil,
        bankName: String? = nil,
        bankAccount: String? = nil
    ) {
        self.id = UUID()
        self.companyName = companyName
        self.taxNumber = taxNumber
        self.phoneNumber = phoneNumber
        self.email = email
        self.address = address
        self.bankName = bankName
        self.bankAccount = bankAccount
        self.createdAt = Date()
        self.lastModified = Date()
    }
    
    // 是否有基本信息（公司名称和税号）
    var hasBasicInfo: Bool {
        return !companyName.isEmpty && taxNumber != nil && !taxNumber!.isEmpty
    }
}

