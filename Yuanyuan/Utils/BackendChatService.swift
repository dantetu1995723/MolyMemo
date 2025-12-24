import Foundation
import UIKit

/// 自有后端聊天服务：
/// - `/api/v1/chat/...`：按你们示例的 `content: [...]` 格式（非流式）
/// - 当前版本：仅支持 `/api/v1/chat`（contentV1），避免误切换到兼容接口
final class BackendChatService {
    private init() {}

    // MARK: - Auth / Headers

    private enum AuthKeys {
        static let sessionId = "yuanyuan_auth_session_id"
    }

    private static func currentSessionId() -> String? {
        // 1) 与登录后写入保持一致：BackendChatConfig.apiKey（AuthStore.login 里会写入）
        let fromConfig = BackendChatConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromConfig.isEmpty { return fromConfig }
        // 2) 兜底：AuthStore 写入的 UserDefaults
        let fromDefaults = (UserDefaults.standard.string(forKey: AuthKeys.sessionId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fromDefaults.isEmpty ? nil : fromDefaults
    }
    
    static func sendMessageStream(
        messages: [ChatMessage],
        mode: AppMode,
        onStructuredOutput: (@MainActor (BackendChatStructuredOutput) -> Void)? = nil,
        onComplete: @escaping (String) async -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        do {
            guard let url = BackendChatConfig.endpointURL() else {
                throw BackendChatError.invalidConfig("后端 baseURL/path 无效")
            }
            
            var request = URLRequest(url: url, timeoutInterval: Double.infinity)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            applyDefaultHeaders(to: &request)
            
            // system prompt：尽量复用现有风格，避免切后端后“人格”漂移
            let systemPrompt = mode == .work
            ? "你是圆圆，一位知性、温柔、理性的秘书型助理。说话克制、有条理，先给清晰结论，再补充简明理由和可执行建议，不撒娇、不卖萌。"
            : "你是圆圆，一位知性、温柔、理性的秘书型伙伴。先理解并接住用户情绪，再用理性、结构化的方式分析问题和给出建议，不使用夸张语气词或撒娇说法。"
            
            // 过滤问候 + 仅发送最近几轮，控制 token
            let filtered = messages.filter { !$0.isGreeting }
            // 只发送一组 content（以最新的用户输入为主）
            let lastUser = filtered.last(where: { $0.role == .user })
            let contentPayload = buildContentV1Payload(userMessage: lastUser, systemPrompt: systemPrompt)
            request.httpBody = try JSONSerialization.data(withJSONObject: contentPayload)

            // 线上也需要可见日志：自动脱敏/截断，避免 base64 把控制台刷爆
            print("\n========== 📤 Backend Chat Request (/api/v1/chat) ==========")
            print("URL: \(url.absoluteString)")
            debugPrintHeaders(request)
            debugPrintBody(request)
            print("===========================================================\n")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendChatError.invalidResponse
            }

            let raw = String(data: data, encoding: .utf8) ?? ""
            if httpResponse.statusCode != 200 {
                print("\n========== ❌ Backend Chat Response (/api/v1/chat) ==========")
                print("Status: \(httpResponse.statusCode)")
                debugPrintHTTPHeaders(httpResponse)
                print("Body(\(raw.count)):")
                print(truncate(raw, limit: 1200))
                print("===========================================================\n")
                throw BackendChatError.httpError(statusCode: httpResponse.statusCode, message: raw)
            }

            print("\n========== 📥 Backend Chat Response (/api/v1/chat) ==========")
            print("Status: \(httpResponse.statusCode)")
            debugPrintHTTPHeaders(httpResponse)
            print("Body(\(raw.count)):")
            print(truncate(raw, limit: 1200))
            debugPrintJSONKeys(data)
            print("===========================================================\n")

            if let structured = parseStructuredOutput(from: data) {
                await MainActor.run {
                    onStructuredOutput?(structured)
                }
                let cleaned = removeMarkdownFormatting(structured.text).trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty, structured.scheduleEvents.isEmpty, structured.contacts.isEmpty, structured.invoices.isEmpty, structured.meetings.isEmpty {
                    throw BackendChatError.emptyResponse
                }
#if DEBUG
                if !structured.scheduleEvents.isEmpty {
                    for e in structured.scheduleEvents.prefix(5) {
                        print("🧩 [BackendChat->Structured] schedule title=\(e.title) start=\(e.startTime) end=\(e.endTime) id=\(e.id)")
                    }
                }
                if !structured.contacts.isEmpty {
                    for c in structured.contacts.prefix(3) {
                        print("🧩 [BackendChat->Structured] contact name=\(c.name) phone=\(c.phone ?? "") id=\(c.id)")
                    }
                }
                if !structured.invoices.isEmpty {
                    for i in structured.invoices.prefix(3) {
                        print("🧩 [BackendChat->Structured] invoice merchant=\(i.merchantName) amount=\(i.amount) date=\(i.date) id=\(i.id)")
                    }
                }
#endif
                print("✅ [BackendChat] parsedStructured text(\(cleaned.count)) cards(schedule:\(structured.scheduleEvents.count), contact:\(structured.contacts.count), invoice:\(structured.invoices.count), meeting:\(structured.meetings.count))")
                await onComplete(cleaned)
            } else {
                let text = extractTextFromResponseData(data)
                let cleaned = removeMarkdownFormatting(text).trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty {
                    throw BackendChatError.emptyResponse
                }
                print("✅ [BackendChat] parsedText(\(cleaned.count)) preview: \(truncate(cleaned, limit: 200))")
                await onComplete(cleaned)
            }
        } catch {
            await MainActor.run {
                onError(error)
            }
        }
    }
    
    // MARK: - Parsing

    private static func parseStructuredOutput(from data: Data) -> BackendChatStructuredOutput? {
        // 兼容以下几种常见返回：
        // 1) JSON array: [ {chunk1}, {chunk2}, ... ]
        // 2) JSON object: { ...chunk... }
        // 3) NDJSON: 每行一个 JSON object
        // 4) SSE: data: {json}\n\n
        guard !data.isEmpty else { return nil }
        let raw = String(data: data, encoding: .utf8) ?? ""

        // 先尝试：顶层就是 JSON（数组/对象）
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let array = obj as? [[String: Any]] {
                let out = reduceChunks(array)
                return out.isEmpty ? nil : out
            }
            if let dict = obj as? [String: Any] {
                // 有些后端会包一层 data/messages
                if let inner = dict["data"] as? [String: Any] {
                    if let items = inner["items"] as? [[String: Any]] {
                        let out = reduceChunks(items)
                        return out.isEmpty ? nil : out
                    }
                    if let chunks = inner["chunks"] as? [[String: Any]] {
                        let out = reduceChunks(chunks)
                        return out.isEmpty ? nil : out
                    }
                }
                if let messages = dict["messages"] as? [[String: Any]] {
                    let out = reduceChunks(messages)
                    return out.isEmpty ? nil : out
                }
                let out = reduceChunks([dict])
                return out.isEmpty ? nil : out
            }
        }

        // 再尝试：SSE
        if raw.contains("\ndata:") || raw.hasPrefix("data:") {
            let events = raw
                .components(separatedBy: "\n\n")
                .flatMap { block -> [[String: Any]] in
                    let lines = block.split(separator: "\n")
                    let dataLines = lines.compactMap { line -> String? in
                        let s = String(line)
                        guard s.hasPrefix("data:") else { return nil }
                        return s.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                    }
                    return dataLines.compactMap { jsonString in
                        guard let d = jsonString.data(using: .utf8),
                              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                        else { return nil }
                        return o
                    }
                }
            let out = reduceChunks(events)
            return out.isEmpty ? nil : out
        }

        // 最后尝试：NDJSON
        let ndjsonObjects: [[String: Any]] = raw
            .split(separator: "\n")
            .compactMap { line in
                let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return nil }
                guard let d = s.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                else { return nil }
                return o
            }
        let out = reduceChunks(ndjsonObjects)
        return out.isEmpty ? nil : out
    }

    private static func reduceChunks(_ chunks: [[String: Any]]) -> BackendChatStructuredOutput {
        var output = BackendChatStructuredOutput()
        var textParts: [String] = []

        for chunk in chunks {
            guard let type = chunk["type"] as? String else { continue }
            switch type {
            case "task_id":
                if let taskId = chunk["task_id"] as? String, !taskId.isEmpty {
                    output.taskId = taskId
                }

            case "markdown":
                if let content = chunk["content"] as? String {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 约定：后端有时会额外输出“处理完成”作为收尾提示，正式 UI 不展示
                    if trimmed == "处理完成" { continue }
                    if !trimmed.isEmpty { textParts.append(trimmed) }
                }

            case "tool":
                // 正式 UI 默认不展示 tool chunk（避免刷屏）
                // 但：部分后端会把“创建/更新日程”的结构化结果放在 observation 里，这里兜底解析成卡片
                if let tool = chunk["content"] as? [String: Any] {
                    applyTool(tool, into: &output)
                }
                continue

            case "card":
                guard let content = chunk["content"] as? [String: Any] else { continue }
                applyCard(content, into: &output)

            default:
                // 兼容：如果后端未来直接发 text chunk
                if let content = chunk["content"] as? String {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { textParts.append(trimmed) }
                }
            }
        }

        output.text = textParts.joined(separator: "\n\n")
        return output
    }

    private static func applyTool(_ tool: [String: Any], into output: inout BackendChatStructuredOutput) {
        let name = (tool["name"] as? String)?.lowercased() ?? ""
        let status = (tool["status"] as? String)?.lowercased() ?? ""
        guard status == "success" else { return }

        // 后端常见：observation 是一个 JSON 字符串
        guard let obsString = tool["observation"] as? String,
              let obsData = obsString.data(using: .utf8),
              let obsObj = try? JSONSerialization.jsonObject(with: obsData) as? [String: Any]
        else { return }

        // 仅做最小兜底：日程创建/更新
        if name == "schedules_create" || name == "schedules_update" {
            if let data = obsObj["data"] as? [String: Any] {
                if let event = parseScheduleEventFromToolData(data) {
                    output.scheduleEvents.append(event)
                }
            }
            return
        }
    }

    private static func parseScheduleEventFromToolData(_ dict: [String: Any]) -> ScheduleEvent? {
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let description = (dict["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let start = parseISODate(dict["start_time"]) else {
#if DEBUG
            print("🧩 [BackendChat->ToolSchedule] parse start_time failed: \(String(describing: dict["start_time"])) title=\(title)")
#endif
            return nil
        }
        let end = parseISODate(dict["end_time"]) ?? start.addingTimeInterval(3600)

        var event = ScheduleEvent(title: title, description: description, startTime: start, endTime: end)
        if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
            event.id = id
        }
#if DEBUG
        print("🧩 [BackendChat->ToolSchedule] parsed schedule id=\(event.id) title=\(event.title) start=\(event.startTime) end=\(event.endTime)")
#endif
        return event
    }

    private static func applyCard(_ card: [String: Any], into output: inout BackendChatStructuredOutput) {
        let cardType = (card["card_type"] as? String)?.lowercased() ?? ""
        let cardIdString = card["card_id"] as? String
        let cardId = cardIdString.flatMap { UUID(uuidString: $0) }
        let data = card["data"]

        switch cardType {
        case "schedule":
            if let dict = data as? [String: Any] {
                if let event = parseScheduleEvent(dict, forceId: cardId) {
                    output.scheduleEvents.append(event)
                }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let event = parseScheduleEvent(d, forceId: nil) {
                        output.scheduleEvents.append(event)
                    }
                }
            }

        case "contact", "contacts", "person", "people":
            if let dict = data as? [String: Any] {
                if let c = parseContact(dict, forceId: cardId) {
                    output.contacts.append(c)
                }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let c = parseContact(d, forceId: nil) {
                        output.contacts.append(c)
                    }
                }
            }

        case "invoice", "reimbursement", "expense":
            // 你们前端现有“报销卡片”用的是 InvoiceCard（发票/报销记录）
            if let dict = data as? [String: Any] {
                if let i = parseInvoice(dict, forceId: cardId) {
                    output.invoices.append(i)
                }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let i = parseInvoice(d, forceId: nil) {
                        output.invoices.append(i)
                    }
                }
            }

        case "meeting":
            if let dict = data as? [String: Any] {
                if let m = parseMeeting(dict, forceId: cardId) {
                    output.meetings.append(m)
                }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let m = parseMeeting(d, forceId: nil) {
                        output.meetings.append(m)
                    }
                }
            }

        default:
            break
        }
    }

    private static func parseScheduleEvent(_ dict: [String: Any], forceId: UUID?) -> ScheduleEvent? {
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = (dict["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }

        guard let start = parseISODate(dict["start_time"]) else { return nil }
        let end = parseISODate(dict["end_time"]) ?? start.addingTimeInterval(3600) // 后端可能返回 null，前端需要一个合理的 endTime

        var event = ScheduleEvent(title: title, description: description, startTime: start, endTime: end)
        if let id = forceId { event.id = id }
        return event
    }

    private static func parseContact(_ dict: [String: Any], forceId: UUID?) -> ContactCard? {
        let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        var card = ContactCard(
            name: name,
            englishName: dict.string(forAnyOf: ["english_name", "englishName"]),
            company: dict.string(forAnyOf: ["company"]),
            title: dict.string(forAnyOf: ["title", "position", "job_title"]),
            phone: dict.string(forAnyOf: ["phone", "phone_number", "mobile"]),
            email: dict.string(forAnyOf: ["email"]),
            avatarData: nil,
            rawImage: nil
        )
        if let id = forceId { card.id = id }
        // avatar/rawImage 若后端给 base64，后续再接；这里先不猜测字段，避免误解析造成崩溃/内存暴涨
        return card
    }

    private static func parseInvoice(_ dict: [String: Any], forceId: UUID?) -> InvoiceCard? {
        let invoiceNumber = dict.string(forAnyOf: ["invoice_number", "invoiceNumber", "number"]) ?? ""
        let merchantName = dict.string(forAnyOf: ["merchant_name", "merchantName", "merchant"]) ?? ""
        let type = dict.string(forAnyOf: ["type", "category"]) ?? ""

        let amount: Double = {
            if let n = dict["amount"] as? Double { return n }
            if let n = dict["amount"] as? Int { return Double(n) }
            if let s = dict["amount"] as? String { return Double(s) ?? 0 }
            return 0
        }()
        let date = parseISODate(dict["date"]) ?? Date()
        let notes = dict.string(forAnyOf: ["notes", "note", "remark"])

        guard !merchantName.isEmpty || !invoiceNumber.isEmpty else { return nil }

        var card = InvoiceCard(
            invoiceNumber: invoiceNumber.isEmpty ? "未知" : invoiceNumber,
            merchantName: merchantName.isEmpty ? "未知商户" : merchantName,
            amount: amount,
            date: date,
            type: type.isEmpty ? "其他" : type,
            notes: notes
        )
        if let id = forceId { card.id = id }
        return card
    }

    private static func parseMeeting(_ dict: [String: Any], forceId: UUID?) -> MeetingCard? {
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let summary = (dict["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let date = parseISODate(dict["date"]) ?? Date()

        var card = MeetingCard(remoteId: dict.string(forAnyOf: ["id", "remote_id", "remoteId"]),
                               title: title,
                               date: date,
                               summary: summary.isEmpty ? "（无摘要）" : summary)
        if let id = forceId { card.id = id }
        if let gen = dict["is_generating"] as? Bool { card.isGenerating = gen }
        if let url = dict.string(forAnyOf: ["audio_url", "audioRemoteURL", "audio_remote_url"]) { card.audioRemoteURL = url }
        if let d = dict["audio_duration"] as? Double { card.duration = d }
        if let d = dict["audio_duration"] as? Int { card.duration = Double(d) }
        return card
    }

    private static func parseISODate(_ any: Any?) -> Date? {
        guard let sAny = any else { return nil }
        if let s = sAny as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: trimmed) { return d }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let d = f2.date(from: trimmed) { return d }
            // 兼容后端常见“无时区 ISO8601”（按本地时区理解）
            let tz = TimeZone.current
            let posix = Locale(identifier: "en_US_POSIX")

            func tryFormat(_ format: String) -> Date? {
                let df = DateFormatter()
                df.locale = posix
                df.timeZone = tz
                df.dateFormat = format
                return df.date(from: trimmed)
            }

            // e.g. 2025-12-25T10:00:00 / 2025-12-25T10:00
            if let d = tryFormat("yyyy-MM-dd'T'HH:mm:ss") { return d }
            if let d = tryFormat("yyyy-MM-dd'T'HH:mm") { return d }
            // e.g. 2025-12-25T10:00:00.123
            if let d = tryFormat("yyyy-MM-dd'T'HH:mm:ss.SSS") { return d }
            // 兼容 "yyyy-MM-dd HH:mm:ss"
            if let d = tryFormat("yyyy-MM-dd HH:mm:ss") { return d }
#if DEBUG
            if trimmed.contains("T") || trimmed.contains("-") {
                print("🧩 [BackendChat->DateParse] failed: '\(trimmed)'")
            }
#endif
            return nil
        }
        return nil
    }
    
    private static func extractTextFromResponseData(_ data: Data) -> String {
        // 尽量容错：优先从 JSON 常见字段提取，否则 fallback 到原始文本
        if data.isEmpty { return "" }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let content = obj["content"] as? String { return content }
            if let text = obj["text"] as? String { return text }
            if let answer = obj["answer"] as? String { return answer }
            if let dataObj = obj["data"] as? [String: Any] {
                if let content = dataObj["content"] as? String { return content }
                if let text = dataObj["text"] as? String { return text }
                if let answer = dataObj["answer"] as? String { return answer }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Utils
    
    private static func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxSize else { return image }
        
        let scale = maxSize / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    private static func buildContentV1Payload(userMessage: ChatMessage?, systemPrompt: String) -> [String: Any] {
        var content: [[String: Any]] = []
        
        // 按示例：text
        let text = userMessage?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            content.append([
                "type": "text",
                "text": text
            ])
        } else {
            // 如果只有图片，没有文字，也补一句占位，避免后端判空
            if let images = userMessage?.images, !images.isEmpty {
                content.append([
                    "type": "text",
                    "text": "请分析这张图片"
                ])
            }
        }
        
        // shortcut（可选）
        let shortcut = BackendChatConfig.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shortcut.isEmpty {
            content.append([
                "type": "shortcut",
                "shortcut": ["shortcut": shortcut]
            ])
        }
        
        // image_url（当前 ChatMessage 只支持图片，所以先落地图片）
        if let images = userMessage?.images, !images.isEmpty {
            for image in images {
                let resized = resizeImage(image, maxSize: 2048)
                guard let data = resized.jpegData(compressionQuality: 0.95) else { continue }
                let base64 = data.base64EncodedString()
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                ])
            }
        }
        
        // 你们示例还支持 audio/video/file；目前 App 的 ChatMessage 没有这些输入源，后续需要的话再补数据通道
        
        // 注意：示例里没有 system 字段，这里先不发 systemPrompt，避免后端不认识字段导致报错
        _ = systemPrompt
        
        return ["content": content]
    }
    
    private static func applyDefaultHeaders(to request: inout URLRequest) {
        // 这些 header 你示例里都带了：即使为空也带上，尽量兼容后端校验
        let sessionId = (currentSessionId() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-App-Id")
        request.setValue(appVersionString(), forHTTPHeaderField: "X-App-Version")
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-OS-Type")
        request.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-OS-Version")
        
        // 地理信息：当前工程未接入定位，先留空
        request.setValue("", forHTTPHeaderField: "X-Longitude")
        request.setValue("", forHTTPHeaderField: "X-Latitude")
        request.setValue("", forHTTPHeaderField: "X-Address")
        request.setValue("", forHTTPHeaderField: "X-City")
        request.setValue("", forHTTPHeaderField: "X-Country")
    }
    
    // MARK: - Debug helpers
    
    private static func debugPrintHeaders(_ request: URLRequest) {
        print("Headers:")
        let headers = request.allHTTPHeaderFields ?? [:]
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
            if k.lowercased() == "authorization" {
                print("  \(k): Bearer ***")
            } else {
                print("  \(k): \(v)")
            }
        }
    }
    
    private static func debugPrintBody(_ request: URLRequest) {
        guard let body = request.httpBody, !body.isEmpty else {
            print("Body: <empty>")
            return
        }
        let str = String(data: body, encoding: .utf8) ?? ""
        let redacted = redactBase64(str)
        print("Body(\(str.count)):")
        print(truncate(redacted, limit: 1200))
    }
    
    private static func debugPrintHTTPHeaders(_ response: HTTPURLResponse) {
        print("Response headers:")
        for (kAny, vAny) in response.allHeaderFields {
            let k = String(describing: kAny)
            let v = String(describing: vAny)
            print("  \(k): \(v)")
        }
    }
    
    private static func debugPrintJSONKeys(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        if let dict = obj as? [String: Any] {
            print("JSON keys: \(dict.keys.sorted())")
            if let inner = dict["data"] as? [String: Any] {
                print("JSON data.* keys: \(inner.keys.sorted())")
            }
        }
    }
    
    private static func truncate(_ s: String, limit: Int) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + " ...<truncated>"
    }
    
    private static func redactBase64(_ s: String) -> String {
        // 把 data:*;base64,xxxxx 大段替换掉，避免控制台爆炸
        // 覆盖 image/audio/video/file 常见 data uri
        let pattern = "data:[^\\s\\\"]+;base64,[A-Za-z0-9+/=]+"
        return s.replacingOccurrences(of: pattern, with: "data:*;base64,***", options: .regularExpression)
    }
    
    private static func appVersionString() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if short.isEmpty { return build }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }
    
    /// 复用 QwenMaxService 的清理逻辑（保持输出一致），这里做最小实现以免跨文件依赖
    private static func removeMarkdownFormatting(_ text: String) -> String {
        var result = text
        
        result = result.replacingOccurrences(of: "```[a-zA-Z]*\\n", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "```", with: "")
        result = result.replacingOccurrences(of: "\\*\\*([^\\*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*([^\\*\\n]+)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        
        let lines = result.components(separatedBy: "\n")
        let cleanedLines = lines.map { line -> String in
            var cleanedLine = line
            if let range = cleanedLine.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            if let range = cleanedLine.range(of: "^>\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            if let range = cleanedLine.range(of: "^[\\*\\-\\+]\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            if let range = cleanedLine.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            return cleanedLine
        }
        
        return cleanedLines.joined(separator: "\n")
    }
}

// MARK: - Small helpers

private extension Dictionary where Key == String, Value == Any {
    func string(forAnyOf keys: [String]) -> String? {
        for k in keys {
            if let v = self[k] as? String {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }
}

enum BackendChatError: LocalizedError {
    case invalidConfig(String)
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidConfig(let msg):
            return "后端配置有误：\(msg)"
        case .invalidResponse:
            return "服务器响应无效"
        case .httpError(let statusCode, let message):
            return "请求失败 (\(statusCode)): \(message)"
        case .emptyResponse:
            return "服务器返回空内容"
        }
    }
}


