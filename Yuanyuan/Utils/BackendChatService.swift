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
        includeShortcut: Bool = true,
        onStructuredOutput: (@MainActor (BackendChatStructuredOutput) -> Void)? = nil,
        onComplete: @escaping (String) async -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        do {
            guard let url = BackendChatConfig.endpointURL() else {
                throw BackendChatError.invalidConfig("后端 baseURL/path 无效")
            }

            // ✅ 用于对齐“我这次发出的请求”和“后端返回的每个 chunk”
            // - 不影响后端逻辑（header 仅用于 debug 追踪）
            // - 你贴的 log 看起来像“缓存残留”，大概率是后端重复推送了相同进度文案；加上 requestId 后能一眼确认
            let requestId = UUID().uuidString
            
            var request = URLRequest(url: url, timeoutInterval: Double.infinity)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            applyDefaultHeaders(to: &request)
            request.setValue(requestId, forHTTPHeaderField: "X-Client-Request-Id")
            
            // system prompt：尽量复用现有风格，避免切后端后“人格”漂移
            let systemPrompt = mode == .work
            ? "你是圆圆，一位知性、温柔、理性的秘书型助理。说话克制、有条理，先给清晰结论，再补充简明理由和可执行建议，不撒娇、不卖萌。"
            : "你是圆圆，一位知性、温柔、理性的秘书型伙伴。先理解并接住用户情绪，再用理性、结构化的方式分析问题和给出建议，不使用夸张语气词或撒娇说法。"
            
            // 过滤问候 + 仅发送最近几轮，控制 token
            let filtered = messages.filter { !$0.isGreeting }
            // 只发送一组 content（以最新的用户输入为主）
            let lastUser = filtered.last(where: { $0.role == .user })
            let contentPayload = buildContentV1Payload(
                userMessage: lastUser,
                systemPrompt: systemPrompt,
                includeShortcut: includeShortcut
            )
            request.httpBody = try JSONSerialization.data(withJSONObject: contentPayload)

#if DEBUG
            // 你要求的“实时后端聊天 print”：请求开始 + 基本信息（不输出 base64）
            let hasImage = !(lastUser?.images.isEmpty ?? true)
            let textLen = lastUser?.content.count ?? 0
            print("🚀 [BackendChat][rid=\(requestId)] start url=\(url.absoluteString) includeShortcut=\(includeShortcut) mode=\(mode) lastUser(textLen=\(textLen) hasImage=\(hasImage))")
#endif

            // ✅ 即时前端输出：边收边解析，每来一个 json chunk 就回调一次（追加 segments）
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendChatError.invalidResponse
            }

#if DEBUG
            print("📡 [BackendChat][rid=\(requestId)] http status=\(httpResponse.statusCode)")
#endif

            // 非 200：读完整 body 作为错误信息
            if httpResponse.statusCode != 200 {
                var errorData = Data()
                for try await b in bytes {
                    errorData.append(b)
                }
                let raw = String(data: errorData, encoding: .utf8) ?? ""
                throw BackendChatError.httpError(statusCode: httpResponse.statusCode, message: raw)
            }

            enum StreamFormat { case unknown, sse, ndjson }
            var format: StreamFormat = .unknown
            var sseDataLines: [String] = []
            var rawFallbackLines: [String] = []

            // 仅用于最终 onComplete 的文本聚合（UI 以 segments 为准）
            var accumulatedTextParts: [String] = []

            func emitDeltaChunk(_ obj: [String: Any]) async {
                let delta = parseChunkDelta(obj)
                if delta.segments.isEmpty,
                   delta.scheduleEvents.isEmpty,
                   delta.contacts.isEmpty,
                   delta.invoices.isEmpty,
                   delta.meetings.isEmpty,
                   !delta.isContactToolRunning,
                   !delta.isScheduleToolRunning,
                   (delta.taskId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return
                }
                // 用于最终完成：把 delta.text 的每段累积起来
                let t = normalizeDisplayText(delta.text)
                if !t.isEmpty { accumulatedTextParts.append(t) }
                await MainActor.run { onStructuredOutput?(delta) }
            }

            func flushSSEEventIfNeeded() async {
                guard !sseDataLines.isEmpty else { return }
                let joined = sseDataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                sseDataLines.removeAll(keepingCapacity: true)
                guard !joined.isEmpty else { return }
                if joined == "[DONE]" { return }
#if DEBUG
                if BackendChatConfig.debugLogChunkSummary {
                    print("🧱 [BackendChat][rid=\(requestId)] chunk[sse] \(joined)")
                }
#endif
                guard let d = joined.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                else { return }
                await emitDeltaChunk(o)
            }

            do {
                for try await line in bytes.lines {
                    if Task.isCancelled { throw CancellationError() }

                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedLine.isEmpty { rawFallbackLines.append(trimmedLine) }

                    // 自动探测：先看到 data: 按 SSE，否则按 NDJSON
                    if format == .unknown, trimmedLine.hasPrefix("data:") { format = .sse }
                    else if format == .unknown, trimmedLine.hasPrefix("{") { format = .ndjson }

                    switch format {
                    case .sse:
                        // 空行：一个 event 结束
                        if trimmedLine.isEmpty {
                            await flushSSEEventIfNeeded()
                            continue
                        }
                        if trimmedLine.hasPrefix("data:") {
                            let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !payload.isEmpty else { continue }
                            sseDataLines.append(payload)
                            // 常见：单行就是完整 json，尽快 flush
                            if sseDataLines.count == 1,
                               let d = payload.data(using: .utf8),
                               (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) != nil {
                                await flushSSEEventIfNeeded()
                            }
                        }

                    case .ndjson:
                        guard !trimmedLine.isEmpty else { continue }
#if DEBUG
                        if BackendChatConfig.debugLogChunkSummary {
                            print("🧱 [BackendChat][rid=\(requestId)] chunk[ndjson] \(trimmedLine)")
                        }
#endif
                        guard let d = trimmedLine.data(using: .utf8),
                              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                        else { continue }
                        await emitDeltaChunk(o)

                    case .unknown:
                        continue
                    }
                }
                if format == .sse { await flushSSEEventIfNeeded() }
            } catch is CancellationError {
                // 用户中止：不回调 onError
#if DEBUG
                print("🛑 [BackendChat] cancelled")
#endif
                return
            }

            // 最终完成：优先用流式累积文本；若为空再兜底整包解析
            let cleaned = normalizeDisplayText(accumulatedTextParts.joined(separator: "\n\n"))
            if !cleaned.isEmpty {
#if DEBUG
                print("✅ [BackendChat][rid=\(requestId)] complete(textLen=\(cleaned.count))")
#endif
                await onComplete(cleaned)
                return
            }

            let rawFallback = rawFallbackLines.joined(separator: "\n")
            let fallbackData = rawFallback.data(using: .utf8) ?? Data()
            if let structured = parseStructuredOutput(from: fallbackData) {
                await MainActor.run { onStructuredOutput?(structured) }
                let cleanedFallback = normalizeDisplayText(structured.text)
                if cleanedFallback.isEmpty { throw BackendChatError.emptyResponse }
#if DEBUG
                print("✅ [BackendChat][rid=\(requestId)] complete(fallback textLen=\(cleanedFallback.count) segments=\(structured.segments.count))")
#endif
                await onComplete(cleanedFallback)
            } else {
                let text = extractTextFromResponseData(fallbackData)
                let cleanedText = normalizeDisplayText(text)
                if cleanedText.isEmpty { throw BackendChatError.emptyResponse }
#if DEBUG
                print("✅ [BackendChat][rid=\(requestId)] complete(raw textLen=\(cleanedText.count))")
#endif
                await onComplete(cleanedText)
            }
        } catch {
#if DEBUG
            print("❌ [BackendChat] error: \(error)")
#endif
            await MainActor.run {
                onError(error)
            }
        }
    }

    /// 把单个后端 json chunk 解析成“增量输出”（delta）：用于即时追加到 UI
    private static func parseChunkDelta(_ chunk: [String: Any]) -> BackendChatStructuredOutput {
        var out = BackendChatStructuredOutput()
        out.isDelta = true

        guard let type = chunk["type"] as? String else { return out }
        switch type {
        case "task_id":
            if let taskId = chunk["task_id"] as? String, !taskId.isEmpty {
                out.taskId = taskId
            }
            return out

        case "markdown":
            guard let content = chunk["content"] as? String else { return out }
            // ✅ 后端有时会把工具链路的“中间态 JSON”当 markdown 直接吐给前端：
            //    { "show_content": "...", "action": {...}, ... } + 后续 observation dump
            // 目标：只展示 show_content（给用户看的那句），其余隐藏，避免 UI 出现大段 JSON。
            let extractedShowContent = extractShowContentIfPresent(content)
            let trimmed = (extractedShowContent ?? content).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "处理完成" { return out }
            out.text = trimmed
            out.segments = [.text(trimmed)]
            return out

        case "tool":
            if let tool = chunk["content"] as? [String: Any] {
                let toolName = (tool["name"] as? String)?.lowercased() ?? ""
                let toolStatus = (tool["status"] as? String)?.lowercased() ?? ""
                if toolName == "contacts_create" || toolName == "contacts_update" {
                    out.isContactToolRunning = (toolStatus == "start")
                    if toolStatus == "success" || toolStatus == "error" || toolStatus == "failed" {
                        out.isContactToolRunning = false
                    }
                }
                if toolName == "schedules_create" || toolName == "schedules_update" {
                    out.isScheduleToolRunning = (toolStatus == "start")
                    if toolStatus == "success" || toolStatus == "error" || toolStatus == "failed" {
                        out.isScheduleToolRunning = false
                    }
                }
                applyTool(tool, into: &out)
            }
            return out

        case "card":
            guard let content = chunk["content"] as? [String: Any] else { return out }
            let segs = parseCardSegments(content, into: &out)
            if !segs.isEmpty { out.segments = segs }
            return out

        default:
            if let content = chunk["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return out }
                out.text = trimmed
                out.segments = [.text(trimmed)]
            }
            return out
        }
    }

    /// 若 markdown 文本包含 `"show_content": "..."`，提取该字段给 UI 展示。
    /// - 兼容：文本不一定是合法 JSON（可能拼接了后续 observation），所以用正则做“轻解析”。
    private static func extractShowContentIfPresent(_ raw: String) -> String? {
        guard raw.contains("\"show_content\"") else { return nil }
        // 捕获 show_content 的字符串值（不试图完整处理所有转义场景；足够覆盖当前后端格式）
        let pattern = "\"show_content\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              match.numberOfRanges >= 2
        else { return nil }
        let captured = ns.substring(with: match.range(at: 1))
        let cleaned = captured.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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

#if DEBUG
        if BackendChatConfig.debugLogFullResponse || BackendChatConfig.debugDumpResponseToFile {
            print("🔎 [BackendChat] parseStructuredOutput raw(\(raw.count)):")
            debugPrintResponseBody(raw)
        }
#endif

        // 先尝试：顶层就是 JSON（数组/对象）
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let array = obj as? [[String: Any]] {
#if DEBUG
                debugPrintChunkTypeSummary(array, source: "top-level array")
#endif
                let out = reduceChunks(array)
                return out.isEmpty ? nil : out
            }
            if let dict = obj as? [String: Any] {
                // 有些后端会包一层 data/messages
                if let inner = dict["data"] as? [String: Any] {
                    if let items = inner["items"] as? [[String: Any]] {
#if DEBUG
                        debugPrintChunkTypeSummary(items, source: "dict.data.items")
#endif
                        let out = reduceChunks(items)
                        return out.isEmpty ? nil : out
                    }
                    if let chunks = inner["chunks"] as? [[String: Any]] {
#if DEBUG
                        debugPrintChunkTypeSummary(chunks, source: "dict.data.chunks")
#endif
                        let out = reduceChunks(chunks)
                        return out.isEmpty ? nil : out
                    }
                }
                if let messages = dict["messages"] as? [[String: Any]] {
#if DEBUG
                    debugPrintChunkTypeSummary(messages, source: "dict.messages")
#endif
                    let out = reduceChunks(messages)
                    return out.isEmpty ? nil : out
                }
#if DEBUG
                debugPrintChunkTypeSummary([dict], source: "top-level dict")
#endif
                let out = reduceChunks([dict])
                return out.isEmpty ? nil : out
            }
        }

        // 再尝试：SSE
        if raw.contains("\ndata:") || raw.hasPrefix("data:") {
            var events: [[String: Any]] = []
            let blocks = raw.components(separatedBy: "\n\n")
#if DEBUG
            if BackendChatConfig.debugLogStreamEvents {
                print("📡 [BackendChat] detected SSE blocks=\(blocks.count)")
            }
#endif

            for (bIndex, block) in blocks.enumerated() {
                let lines = block.split(separator: "\n")
                for lineSub in lines {
                    let line = String(lineSub)
                    guard line.hasPrefix("data:") else { continue }
                    let jsonString = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                    guard !jsonString.isEmpty else { continue }

#if DEBUG
                    if BackendChatConfig.debugLogStreamEvents {
                        let s = truncate(redactBase64(jsonString), limit: 520)
                        print("📡 [SSE data] block=\(bIndex) \(s)")
                    }
#endif

                    guard let d = jsonString.data(using: .utf8),
                          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                    else {
#if DEBUG
                        if BackendChatConfig.debugLogStreamEvents {
                            print("⚠️ [BackendChat] SSE json parse failed at block=\(bIndex) preview: \(truncate(jsonString, limit: 220))")
                        }
#endif
                        continue
                    }

#if DEBUG
                    debugPrintSingleChunkSummary(o, source: "sse", index: events.count)
                    // 某些后端会把 event/type 打在 SSE event 行里，这里顺手打印一下，便于对照
                    if BackendChatConfig.debugLogStreamEvents, line.contains("event:") {
                        print("📡 [SSE meta] block=\(bIndex) line=\(truncate(line, limit: 220))")
                    }
#endif
                    events.append(o)
                }
            }

#if DEBUG
            debugPrintChunkTypeSummary(events, source: "sse aggregated")
#endif
            let out = reduceChunks(events)
            return out.isEmpty ? nil : out
        }

        // 最后尝试：NDJSON
        var ndjsonObjects: [[String: Any]] = []
        let ndLines = raw.split(separator: "\n")
#if DEBUG
        if BackendChatConfig.debugLogStreamEvents {
            print("🧱 [BackendChat] detected NDJSON lines=\(ndLines.count)")
        }
#endif
        for (i, lineSub) in ndLines.enumerated() {
            let s = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }

#if DEBUG
            if BackendChatConfig.debugLogStreamEvents {
                print("🧱 [NDJSON line] \(i): \(truncate(redactBase64(s), limit: 520))")
            }
#endif

            guard let d = s.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else {
#if DEBUG
                if BackendChatConfig.debugLogStreamEvents {
                    print("⚠️ [BackendChat] NDJSON json parse failed at line=\(i) preview: \(truncate(s, limit: 220))")
                }
#endif
                continue
            }
#if DEBUG
            debugPrintSingleChunkSummary(o, source: "ndjson", index: ndjsonObjects.count)
#endif
            ndjsonObjects.append(o)
        }

#if DEBUG
        debugPrintChunkTypeSummary(ndjsonObjects, source: "ndjson aggregated")
#endif
        let out = reduceChunks(ndjsonObjects)
        return out.isEmpty ? nil : out
    }

    private static func reduceChunks(_ chunks: [[String: Any]]) -> BackendChatStructuredOutput {
        var output = BackendChatStructuredOutput()
        var textParts: [String] = []

        for (idx, chunk) in chunks.enumerated() {
            guard let type = chunk["type"] as? String else { continue }
#if DEBUG
            if BackendChatConfig.debugLogChunkSummary {
                debugPrintSingleChunkSummary(chunk, source: "reduce", index: idx)
            }
#endif
            switch type {
            case "task_id":
                if let taskId = chunk["task_id"] as? String, !taskId.isEmpty {
                    output.taskId = taskId
                }

            case "markdown":
                guard let content = chunk["content"] as? String else { continue }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "处理完成" { continue }
                guard !trimmed.isEmpty else { continue }
                textParts.append(trimmed)
                output.segments.append(.text(trimmed))

            case "tool":
                // UI 不展示 tool chunk；但保留 tool 中间态与 observation 兜底解析
                if let tool = chunk["content"] as? [String: Any] {
                    let toolName = (tool["name"] as? String)?.lowercased() ?? ""
                    let toolStatus = (tool["status"] as? String)?.lowercased() ?? ""
                    if toolName == "contacts_create" || toolName == "contacts_update" {
                        if toolStatus == "start" {
                            output.isContactToolRunning = true
                        } else if toolStatus == "success" || toolStatus == "error" || toolStatus == "failed" {
                            output.isContactToolRunning = false
                        }
                    }
                    if toolName == "schedules_create" || toolName == "schedules_update" {
                        if toolStatus == "start" {
                            output.isScheduleToolRunning = true
                        } else if toolStatus == "success" || toolStatus == "error" || toolStatus == "failed" {
                            output.isScheduleToolRunning = false
                        }
                    }
                    applyTool(tool, into: &output)
                }

            case "card":
                guard let content = chunk["content"] as? [String: Any] else { continue }
                let segs = parseCardSegments(content, into: &output)
                if !segs.isEmpty {
                    output.segments.append(contentsOf: segs)
                }

            default:
                // 兼容：如果后端未来直接发 text chunk
                if let content = chunk["content"] as? String {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    textParts.append(trimmed)
                    output.segments.append(.text(trimmed))
                }
            }
        }

        // 用双换行拼接文本 chunk（与“分段”一致），便于复制/搜索
        output.text = textParts.joined(separator: "\n\n")
        return output
    }

    /// 将一个 card chunk 解析成可渲染分段，同时回填到聚合字段（scheduleEvents/contacts/...）
    private static func parseCardSegments(_ card: [String: Any], into output: inout BackendChatStructuredOutput) -> [ChatSegment] {
        let cardType = (card["card_type"] as? String)?.lowercased() ?? ""
        let cardIdString = card["card_id"] as? String
        let cardId = cardIdString.flatMap { UUID(uuidString: $0) }
        let data = card["data"]

        func appendUnique<T: Identifiable>(_ incoming: [T], to list: inout [T]) where T.ID: Equatable {
            for item in incoming {
                if list.contains(where: { $0.id == item.id }) { continue }
                list.append(item)
            }
        }

        switch cardType {
        case "schedule":
            var events: [ScheduleEvent] = []
            if let dict = data as? [String: Any] {
                if let e = parseScheduleEvent(dict, forceId: cardId) { events.append(e) }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let e = parseScheduleEvent(d, forceId: nil) { events.append(e) }
                }
            }
            if !events.isEmpty {
                // 聚合字段仍做去重合并（便于详情/删除等逻辑复用）
                for e in events { upsertScheduleEvent(e, into: &output, preferIncoming: true) }
                return [.scheduleCards(events)]
            }
            return []

        case "contact", "contacts", "person", "people":
            var cards: [ContactCard] = []
            if let dict = data as? [String: Any] {
                if let c = parseContact(dict, forceId: cardId) { cards.append(c) }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let c = parseContact(d, forceId: nil) { cards.append(c) }
                }
            }
            if !cards.isEmpty {
                appendUnique(cards, to: &output.contacts)
                return [.contactCards(cards)]
            }
            return []

        case "invoice", "reimbursement", "expense":
            var cards: [InvoiceCard] = []
            if let dict = data as? [String: Any] {
                if let i = parseInvoice(dict, forceId: cardId) { cards.append(i) }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let i = parseInvoice(d, forceId: nil) { cards.append(i) }
                }
            }
            if !cards.isEmpty {
                appendUnique(cards, to: &output.invoices)
                return [.invoiceCards(cards)]
            }
            return []

        case "meeting":
            var cards: [MeetingCard] = []
            if let dict = data as? [String: Any] {
                if let m = parseMeeting(dict, forceId: cardId) { cards.append(m) }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let m = parseMeeting(d, forceId: nil) { cards.append(m) }
                }
            }
            if !cards.isEmpty {
                appendUnique(cards, to: &output.meetings)
                return [.meetingCards(cards)]
            }
            return []

        default:
            return []
        }
    }

    private static func applyTool(_ tool: [String: Any], into output: inout BackendChatStructuredOutput) {
        let name = (tool["name"] as? String)?.lowercased() ?? ""
        let status = (tool["status"] as? String)?.lowercased() ?? ""
#if DEBUG
        if BackendChatConfig.debugLogChunkSummary {
            let obsLen = (tool["observation"] as? String)?.count ?? 0
            print("🛠️ [BackendChat->Tool] name=\(name) status=\(status) observationLen=\(obsLen)")
        }
#endif
        // ✅ 链路简化：tool chunk 只负责“运行状态/日志”，不再解析 observation 来兜底生成卡片。
        // 卡片必须来自后端 card chunk，避免出现“兜底卡片时间/字段不准”与重复覆盖复杂度。
        _ = name
        _ = status
    }
    
    /// scheduleEvents 去重合并：以 remoteId 优先，其次 id。可指定是否用 incoming 覆盖 existing。
    private static func upsertScheduleEvent(_ incoming: ScheduleEvent, into output: inout BackendChatStructuredOutput, preferIncoming: Bool) {
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let incomingRid = trimmed(incoming.remoteId)
        
        // 优先按 remoteId 匹配（最稳定）
        if !incomingRid.isEmpty, let idx = output.scheduleEvents.firstIndex(where: { trimmed($0.remoteId) == incomingRid }) {
            if preferIncoming { output.scheduleEvents[idx] = incoming }
            return
        }
        
        // 兜底按本地 id 匹配（例如后端没给 remoteId 或格式不对）
        if let idx = output.scheduleEvents.firstIndex(where: { $0.id == incoming.id }) {
            if preferIncoming { output.scheduleEvents[idx] = incoming }
            return
        }
        
        output.scheduleEvents.append(incoming)
    }

    private static func parseContactFromToolData(_ dict: [String: Any]) -> ContactCard? {
        let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        var card = ContactCard(
            name: name,
            englishName: dict.string(forAnyOf: ["english_name", "englishName"]),
            company: dict.string(forAnyOf: ["company"]),
            title: dict.string(forAnyOf: ["position", "title", "job_title"]),
            phone: dict.string(forAnyOf: ["phone", "phone_number", "mobile"]),
            email: dict.string(forAnyOf: ["email"]),
            notes: dict.string(forAnyOf: ["notes", "note", "remark"]),
            impression: dict.string(forAnyOf: ["impression"]),
            avatarData: nil,
            rawImage: nil
        )

        // tool 返回 id：字段名可能是 id/contact_id/remote_id/remoteId；值可能是 uuid / 数字 / 字符串
        // remoteId 用于后续详情/更新/删除；若它本身是 UUID 且 card.id 未被强制指定，则用它稳定映射本地 id
        if let rid = dict.string(forAnyOf: ["id", "contact_id", "remote_id", "remoteId"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rid.isEmpty
        {
            card.remoteId = rid
            if let u = UUID(uuidString: rid) {
                card.id = u
            }
        } else if let idInt = dict["id"] as? Int {
            card.remoteId = String(idInt)
        } else if let idDouble = dict["id"] as? Double {
            card.remoteId = String(Int(idDouble))
        } else if let idInt = dict["contact_id"] as? Int {
            card.remoteId = String(idInt)
        } else if let idDouble = dict["contact_id"] as? Double {
            card.remoteId = String(Int(idDouble))
        }
        return card
    }

    private static func parseScheduleEventFromToolData(_ dict: [String: Any]) -> ScheduleEvent? {
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let description = (dict["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // ✅ full_day 优先：按本地时区的 00:00~24:00 语义落地（endTime 存次日 00:00，但 UI 展示为 24:00）
        if let fullDayStart = parseFullDayStart(dict["full_day"]) {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: fullDayStart) ?? fullDayStart.addingTimeInterval(86_400)
            var event = ScheduleEvent(title: title, description: description, startTime: fullDayStart, endTime: end)
            event.isFullDay = true
            event.endTimeProvided = true
            if let idString = dict["id"] as? String {
                let trimmed = idString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { event.remoteId = trimmed }
                if let id = UUID(uuidString: trimmed) { event.id = id }
            } else if let idInt = dict["id"] as? Int {
                event.remoteId = String(idInt)
            } else if let idDouble = dict["id"] as? Double {
                event.remoteId = String(Int(idDouble))
            }
            return event
        }

        guard let start = parseISODate(dict["start_time"]) else {
#if DEBUG
            if BackendChatConfig.debugLogChunkSummary {
                print("🧩 [BackendChat->ToolSchedule] parse start_time failed: \(String(describing: dict["start_time"])) title=\(title)")
            }
#endif
            return nil
        }
        // end_time 可能为 null：不要默认 +1h 误导展示
        let parsedEnd = parseISODate(dict["end_time"])
        let end = parsedEnd ?? start

        var event = ScheduleEvent(title: title, description: description, startTime: start, endTime: end)
        event.endTimeProvided = (parsedEnd != nil)
        if let idString = dict["id"] as? String {
            let trimmed = idString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { event.remoteId = trimmed }
            if let id = UUID(uuidString: trimmed) { event.id = id }
        } else if let idInt = dict["id"] as? Int {
            event.remoteId = String(idInt)
        } else if let idDouble = dict["id"] as? Double {
            event.remoteId = String(Int(idDouble))
        }
#if DEBUG
        if BackendChatConfig.debugLogChunkSummary {
            print("🧩 [BackendChat->ToolSchedule] parsed schedule id=\(event.id) title=\(event.title) start=\(event.startTime) end=\(event.endTime)")
        }
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
                    // card 优先：覆盖同日程的 tool 兜底结果
                    upsertScheduleEvent(event, into: &output, preferIncoming: true)
                }
            } else if let arr = data as? [[String: Any]] {
                for d in arr {
                    if let event = parseScheduleEvent(d, forceId: nil) {
                        upsertScheduleEvent(event, into: &output, preferIncoming: true)
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

        // ✅ full_day 优先：按本地时区的 00:00~24:00 语义落地
        if let fullDayStart = parseFullDayStart(dict["full_day"]) {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: fullDayStart) ?? fullDayStart.addingTimeInterval(86_400)
            var event = ScheduleEvent(title: title, description: description, startTime: fullDayStart, endTime: end)
            event.isFullDay = true
            event.endTimeProvided = true
            // remoteId：尽量从后端字段拿到，用于后续拉详情
            if let rid = dict.string(forAnyOf: ["id", "schedule_id", "remote_id", "remoteId"])?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rid.isEmpty
            {
                event.remoteId = rid
                if forceId == nil, let u = UUID(uuidString: rid) {
                    event.id = u
                }
            }
            if let id = forceId { event.id = id }
            return event
        }

        guard let start = parseISODate(dict["start_time"]) else { return nil }
        // end_time 可能返回 null：不要默认 +1h 误导展示
        let parsedEnd = parseISODate(dict["end_time"])
        let end = parsedEnd ?? start

        var event = ScheduleEvent(title: title, description: description, startTime: start, endTime: end)
        event.endTimeProvided = (parsedEnd != nil)
        // remoteId：尽量从后端字段拿到，用于后续拉详情
        if let rid = dict.string(forAnyOf: ["id", "schedule_id", "remote_id", "remoteId"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rid.isEmpty
        {
            event.remoteId = rid
            // 若后端 id 本身是 UUID，且外部没有强制本地 id，则用它来稳定映射
            if forceId == nil, let u = UUID(uuidString: rid) {
                event.id = u
            }
        }
        if let id = forceId { event.id = id }
        return event
    }

    /// 解析后端 `full_day`（形如 "yyyy-MM-dd"），并落到本地时区当天 00:00。
    private static func parseFullDayStart(_ any: Any?) -> Date? {
        guard let sAny = any as? String else { return nil }
        let s = sAny.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let posix = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = posix
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        guard let d = df.date(from: s) else { return nil }
        return Calendar.current.startOfDay(for: d)
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
            // 生日：兼容多种后端字段命名（只认“独立字段”，不从 notes 解析）
            birthday: dict.string(forAnyOf: ["birthday", "birth", "birthdate", "birth_date", "birthDay", "birth_day", "date_of_birth", "dob", "birthday_text", "birthdayText", "birthday_display", "birthdayDisplay"]),
            gender: dict.string(forAnyOf: ["gender", "sex"]),
            industry: dict.string(forAnyOf: ["industry"]),
            location: dict.string(forAnyOf: ["location", "region", "city", "address"]),
            relationshipType: dict.string(forAnyOf: ["relationship_type", "relationshipType", "relationship"]),
            notes: dict.string(forAnyOf: ["notes", "note", "remark"]),
            impression: dict.string(forAnyOf: ["impression"]),
            avatarData: nil,
            rawImage: nil
        )
        if let id = forceId { card.id = id }
        
        // remoteId：尽量从后端字段拿到（用于后续拉详情/更新/删除）
        if let rid = dict.string(forAnyOf: ["id", "contact_id", "remote_id", "remoteId"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rid.isEmpty
        {
            card.remoteId = rid
            // 若后端 id 本身是 UUID，且外部没有强制本地 id，则用它来稳定映射
            if forceId == nil, let u = UUID(uuidString: rid) {
                card.id = u
            }
        } else if let idInt = dict["id"] as? Int {
            card.remoteId = String(idInt)
        } else if let idDouble = dict["id"] as? Double {
            card.remoteId = String(Int(idDouble))
        }
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
            
            // ✅ 兼容后端常见：秒后小数位数不固定（如 2025-12-31T08:56:08.7990000）
            // ISO8601DateFormatter(withFractionalSeconds) 在部分系统上对 >3 位小数解析不稳定，
            // 这里先把小数统一归一化到毫秒（3 位），再走 ISO8601 解析。
            let normalized = normalizeISO8601FractionalSecondsToMillis(trimmed)
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: normalized) { return d }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let d = f2.date(from: normalized) { return d }
            // 兼容后端常见“无时区 ISO8601”（按本地时区理解）
            let tz = TimeZone.current
            let posix = Locale(identifier: "en_US_POSIX")

            func tryFormat(_ format: String) -> Date? {
                let df = DateFormatter()
                df.locale = posix
                df.timeZone = tz
                df.dateFormat = format
                return df.date(from: normalized)
            }

            // e.g. 2025-12-25T10:00:00 / 2025-12-25T10:00
            if let d = tryFormat("yyyy-MM-dd'T'HH:mm:ss") { return d }
            if let d = tryFormat("yyyy-MM-dd'T'HH:mm") { return d }
            // e.g. 2025-12-25T10:00:00.123
            if let d = tryFormat("yyyy-MM-dd'T'HH:mm:ss.SSS") { return d }
            // 兼容 "yyyy-MM-dd HH:mm:ss"
            if let d = tryFormat("yyyy-MM-dd HH:mm:ss") { return d }
#if DEBUG
            if normalized.contains("T") || normalized.contains("-") {
                print("🧩 [BackendChat->DateParse] failed: '\(normalized)' (raw='\(trimmed)')")
            }
#endif
            return nil
        }
        return nil
    }

    /// 把 ISO8601 时间字符串的小数秒归一化到 3 位（毫秒），保留时区后缀（Z / ±HH:mm）。
    /// - 示例：`2025-12-31T08:56:08.7990000` -> `2025-12-31T08:56:08.799`
    private static func normalizeISO8601FractionalSecondsToMillis(_ s: String) -> String {
        var base = s
        var tzSuffix = ""
        
        if base.hasSuffix("Z") {
            tzSuffix = "Z"
            base.removeLast()
        } else if let r = base.range(of: "[+-]\\d{2}:\\d{2}$", options: .regularExpression) {
            tzSuffix = String(base[r])
            base.removeSubrange(r)
        }
        
        guard let dot = base.firstIndex(of: ".") else { return s }
        let fracStart = base.index(after: dot)
        guard fracStart < base.endIndex else { return s }
        let frac = String(base[fracStart..<base.endIndex])
        guard !frac.isEmpty, frac.allSatisfy({ $0.isNumber }) else { return s }
        
        let millis: String = {
            if frac.count == 3 { return frac }
            if frac.count > 3 { return String(frac.prefix(3)) }
            // 1~2 位：右侧补 0
            return frac.padding(toLength: 3, withPad: "0", startingAt: 0)
        }()
        
        let head = String(base[..<dot])
        return head + "." + millis + tzSuffix
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
    
    private static func buildContentV1Payload(userMessage: ChatMessage?, systemPrompt: String, includeShortcut: Bool) -> [String: Any] {
        var content: [[String: Any]] = []
        
        // 按示例：text
        let text = userMessage?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            content.append([
                "type": "text",
                "text": text
            ])
        }
        
        // shortcut（可选）
        if includeShortcut {
            let shortcut = BackendChatConfig.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !shortcut.isEmpty {
                content.append([
                    "type": "shortcut",
                    "shortcut": ["shortcut": shortcut]
                ])
            }
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

    /// Debug：输出后端响应 body（可完整打印/落盘），避免控制台被 `...<truncated>` 截断。
    private static func debugPrintResponseBody(_ raw: String) {
#if DEBUG
        if BackendChatConfig.debugDumpResponseToFile {
            if let path = dumpStringToDocuments(raw, prefix: "yy_backend_response") {
                print("📄 [BackendChat] full response saved: \(path)")
            }
        }

        if BackendChatConfig.debugLogFullResponse {
            printLongString(raw, chunkSize: 900)
            return
        }
#endif
        // 默认：仍保持截断，避免刷爆控制台
        print(truncate(raw, limit: 1200))
    }

#if DEBUG
    private static func printLongString(_ s: String, chunkSize: Int) {
        guard chunkSize > 0 else {
            print(s)
            return
        }
        let chars = Array(s)
        if chars.isEmpty {
            print("")
            return
        }
        var i = 0
        while i < chars.count {
            let end = min(i + chunkSize, chars.count)
            print(String(chars[i..<end]))
            i = end
        }
    }

    private static func dumpStringToDocuments(_ s: String, prefix: String) -> String? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let ts = Int(Date().timeIntervalSince1970)
        let fileURL = dir.appendingPathComponent("\(prefix)_\(ts).txt")
        do {
            try s.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.path
        } catch {
            print("⚠️ [BackendChat] dump response failed: \(error)")
            return nil
        }
    }
#endif
    
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
    
    /// 统一的展示文本清洗：流式阶段与最终完成阶段保持一致，避免最后一次替换导致 UI 重新打字。
    static func normalizeDisplayText(_ text: String) -> String {
        removeMarkdownFormatting(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 清理 markdown 格式（保持输出一致），做最小实现以免跨文件依赖
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

#if DEBUG
    private static func debugPrintChunkTypeSummary(_ chunks: [[String: Any]], source: String) {
        guard BackendChatConfig.debugLogStreamEvents else { return }
        var counts: [String: Int] = [:]
        for c in chunks {
            let t = (c["type"] as? String) ?? "<nil>"
            counts[t, default: 0] += 1
        }
        let summary = counts
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        print("📊 [BackendChat] chunkSummary(\(source)) total=\(chunks.count) \(summary)")
    }

    private static func debugPrintSingleChunkSummary(_ chunk: [String: Any], source: String, index: Int) {
        guard BackendChatConfig.debugLogChunkSummary else { return }
        // 需求：控制台 chunk 打印改为后端 chunk 的原始 JSON 内容（不做摘要/preview）
        if let data = try? JSONSerialization.data(withJSONObject: chunk, options: []),
           let json = String(data: data, encoding: .utf8) {
            print("🧱 [BackendChat] chunk[\(source)#\(index)] \(json)")
        } else {
            print("🧱 [BackendChat] chunk[\(source)#\(index)] \(chunk)")
        }
    }
#endif
}

// MARK: - Small helpers

private extension Dictionary where Key == String, Value == Any {
    func string(forAnyOf keys: [String]) -> String? {
        func coerceToString(_ any: Any?) -> String? {
            guard let any else { return nil }
            if any is NSNull { return nil }
            if let s = any as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if let n = any as? Int { return String(n) }
            if let n = any as? Double {
                if n.rounded() == n { return String(Int(n)) }
                return String(n)
            }
            if let b = any as? Bool { return b ? "true" : "false" }
            if let dict = any as? [String: Any] {
                let preferred = ["text", "content", "value", "impression", "notes", "note", "remark"]
                for k in preferred {
                    if let v = coerceToString(dict[k]) { return v }
                }
                return nil
            }
            if let arr = any as? [Any] {
                let parts = arr.compactMap { coerceToString($0) }.filter { !$0.isEmpty }
                if parts.isEmpty { return nil }
                return parts.joined(separator: "\n")
            }
            let s = String(describing: any).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        for k in keys {
            if let t = coerceToString(self[k]) { return t }
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


