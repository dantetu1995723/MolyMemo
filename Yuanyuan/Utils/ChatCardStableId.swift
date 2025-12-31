import Foundation

/// 聊天卡片“稳定去重键”工具。
///
/// 设计目标：
/// - **不依赖 remoteId**（因为 remoteId 可能在流式后续 chunk 才补齐，导致同一张卡出现两份）
/// - 以业务字段指纹作为 key，使“先给基本字段、后补 remoteId/更多字段”的场景能自然合并
enum ChatCardStableId {
    private static func trimmedLower(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedPhone(_ s: String?) -> String {
        let raw = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        // 仅保留数字与 +，避免 “空格/短横线/括号” 导致同号不同 key
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    // MARK: - Contact
    static func contact(_ card: ContactCard) -> String {
        let phone = normalizedPhone(card.phone)
        if !phone.isEmpty { return "phone:\(phone)" }

        let email = trimmedLower(card.email)
        if !email.isEmpty { return "email:\(email)" }

        let name = trimmedLower(card.name)
        let company = trimmedLower(card.company)
        let title = trimmedLower(card.title)
        return "fp:\(name)|\(company)|\(title)"
    }

    // MARK: - Schedule
    static func schedule(_ event: ScheduleEvent) -> String {
        // ✅ 优先使用 remoteId：同一日程的“正确覆盖/去重”以服务端 id 为准
        let rid = trimmedLower(event.remoteId)
        if !rid.isEmpty { return "rid:\(rid)" }

        let title = trimmedLower(event.title)
        let start = Int(event.startTime.timeIntervalSince1970)
        // ✅ 只用“标题 + 开始时间”做指纹：
        // - end_time 可能为 null（前端会用 endTimeProvided 标记）
        // - 后端可能在后续 chunk 补齐 end_time/remoteId；若把 endTime 纳入指纹会导致同一张卡出现两份
        return "fp:\(title)|\(start)"
    }

    // MARK: - Meeting
    static func meeting(_ card: MeetingCard) -> String {
        let title = trimmedLower(card.title)
        let day = Int(card.date.timeIntervalSince1970 / 86_400) // 粗粒度到天，避免时区抖动
        return "fp:\(title)|\(day)"
    }

    // MARK: - Invoice
    static func invoice(_ card: InvoiceCard) -> String {
        let number = trimmedLower(card.invoiceNumber)
        let merchant = trimmedLower(card.merchantName)
        let amount = String(format: "%.2f", card.amount)
        let day = Int(card.date.timeIntervalSince1970 / 86_400)
        return "fp:\(number)|\(merchant)|\(amount)|\(day)"
    }
}


