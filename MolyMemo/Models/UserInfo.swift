import Foundation

struct UserInfoResponse: Codable {
    let code: Int
    let message: String
    let data: UserInfo
}

struct UserInfo: Codable {
    let id: String
    let username: String?
    let email: String?
    let phone: String?
    let city: String?
    let wechat: String?
    let company: String?
    let birthday: String?
    let industry: String?
    let longitude: Double?
    let latitude: Double?
    let address: String?
    let country: String?
    let locationUpdatedAt: String?
    let wechatWorkInfo: JSONValue?
    let dingtalkInfo: JSONValue?
    let feishuInfo: JSONValue?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, email, phone, city, wechat, company, birthday, industry, longitude, latitude, address, country
        case locationUpdatedAt = "location_updated_at"
        case wechatWorkInfo = "wechat_work_info"
        case dingtalkInfo = "dingtalk_info"
        case feishuInfo = "feishu_info"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
