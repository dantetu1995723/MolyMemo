import Foundation

/// 结构化输出应用器：把 `BackendChatStructuredOutput`（delta 或整包）合并到一条 `ChatMessage` 上。
///
/// 设计目标：
/// - 复用同一套“去重/追加/覆盖”逻辑（App 内发送 & AppIntent 后台发送一致）
/// - 不依赖 SwiftUI/@Published，纯数据层函数，便于在后台任务里安全使用
struct StructuredOutputApplier {
    static func apply(_ output: BackendChatStructuredOutput, to message: inout ChatMessage) {
        if let taskId = output.taskId, !taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.notes = taskId
        }

        // tool 中间态（用于 loading 卡片）
        message.isContactToolRunning = output.isContactToolRunning
        message.isScheduleToolRunning = output.isScheduleToolRunning

        if output.isDelta {
            applyDelta(output, to: &message)
            return
        }

        applyFinal(output, to: &message)
    }

    // MARK: - Delta

    private static func applyDelta(_ output: BackendChatStructuredOutput, to message: inout ChatMessage) {
        // 1) segments：追加（并对 text 做展示清洗 + 去重卡片）
        var existing = message.segments ?? []
        existing.reserveCapacity(existing.count + max(1, output.segments.count))

        func scheduleStableId(_ event: ScheduleEvent) -> String { ChatCardStableId.schedule(event) }
        func contactStableId(_ card: ContactCard) -> String { ChatCardStableId.contact(card) }
        func meetingStableId(_ card: MeetingCard) -> String { ChatCardStableId.meeting(card) }

        var seenScheduleIds: Set<String> = Set(existing.flatMap { ($0.scheduleEvents ?? []).map(scheduleStableId) })
        var seenContactIds: Set<String> = Set(existing.flatMap { ($0.contacts ?? []).map(contactStableId) })
        var seenInvoiceIds: Set<String> = Set(existing.flatMap { ($0.invoices ?? []).map(ChatCardStableId.invoice) })
        var seenMeetingIds: Set<String> = Set(existing.flatMap { ($0.meetings ?? []).map(meetingStableId) })

        func isBetterSchedule(_ incoming: ScheduleEvent, than existing: ScheduleEvent) -> Bool {
            // 规则：优先“更明确”的那份
            // - 有 remoteId > 没有 remoteId
            // - isFullDay=true > false
            // - endTimeProvided=true > false
            func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let incRid = !trimmed(incoming.remoteId).isEmpty
            let exRid = !trimmed(existing.remoteId).isEmpty
            if incRid != exRid { return incRid }
            if incoming.isFullDay != existing.isFullDay { return incoming.isFullDay }
            if incoming.endTimeProvided != existing.endTimeProvided { return incoming.endTimeProvided }
            // 兜底：后到的覆盖（通常是 card 覆盖 tool）
            return true
        }

        func replaceExistingScheduleIfNeeded(key: String, incoming: ScheduleEvent) {
            // 在已有 segments 里找到同 key 的 event 并替换（用于“card 覆盖 tool / 修正错误时间”）
            for sIdx in existing.indices {
                guard existing[sIdx].kind == .scheduleCards else { continue }
                guard var evs = existing[sIdx].scheduleEvents, !evs.isEmpty else { continue }
                if let eIdx = evs.firstIndex(where: { scheduleStableId($0) == key }) {
                    if isBetterSchedule(incoming, than: evs[eIdx]) {
                        evs[eIdx] = incoming
                        existing[sIdx].scheduleEvents = evs
                    }
                    return
                }
            }
        }

        if !output.segments.isEmpty {
            for seg in output.segments {
                switch seg.kind {
                case .text:
                    let t = BackendChatService.normalizeDisplayText(seg.text ?? "")
                    if !t.isEmpty { existing.append(.text(t)) }

                case .scheduleCards, .contactCards, .invoiceCards, .meetingCards:
                    // ✅ 去重：后端可能同时发 tool 与 card；也可能重试导致同一张卡多次出现
                    switch seg.kind {
                    case .scheduleCards:
                        let incoming = seg.scheduleEvents ?? []
                        var filtered: [ScheduleEvent] = []
                        filtered.reserveCapacity(incoming.count)
                        for e in incoming {
                            let key = scheduleStableId(e)
                            if seenScheduleIds.contains(key) {
                                replaceExistingScheduleIfNeeded(key: key, incoming: e)
                                continue
                            }
                            seenScheduleIds.insert(key)
                            filtered.append(e)
                        }
                        guard !filtered.isEmpty else { continue }
                        var s = seg
                        s.scheduleEvents = filtered
                        existing.append(s)

                    case .contactCards:
                        let incoming = seg.contacts ?? []
                        let filtered = incoming.filter { seenContactIds.insert(contactStableId($0)).inserted }
                        guard !filtered.isEmpty else { continue }
                        var s = seg
                        s.contacts = filtered
                        existing.append(s)

                    case .invoiceCards:
                        let incoming = seg.invoices ?? []
                        let filtered = incoming.filter { seenInvoiceIds.insert(ChatCardStableId.invoice($0)).inserted }
                        guard !filtered.isEmpty else { continue }
                        var s = seg
                        s.invoices = filtered
                        existing.append(s)

                    case .meetingCards:
                        let incoming = seg.meetings ?? []
                        let filtered = incoming.filter { seenMeetingIds.insert(meetingStableId($0)).inserted }
                        guard !filtered.isEmpty else { continue }
                        var s = seg
                        s.meetings = filtered
                        existing.append(s)

                    case .text:
                        break
                    }
                }
            }
        }

        // ✅ 链路简化：不再做“聚合字段 -> 自动补 segment”的兜底。
        // 卡片必须来自后端 segments（card chunk），这里仅负责合并/覆盖与去重。

        message.segments = existing.isEmpty ? nil : existing

        // 2) 文本聚合：只用于复制/搜索（UI 以 segments 为准）
        let incomingText = BackendChatService.normalizeDisplayText(output.text)
        if !incomingText.isEmpty {
            let base = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty {
                message.content = incomingText
            } else if !base.hasSuffix(incomingText) {
                message.content = base + "\n\n" + incomingText
            }
        }

        // 3) 卡片聚合字段：合并去重（用于详情页/复制卡片信息复用）
        if !output.scheduleEvents.isEmpty {
            message.scheduleEvents = mergeSchedulesPreferIncoming(existing: message.scheduleEvents, incoming: output.scheduleEvents)
        }
        if !output.contacts.isEmpty {
            message.contacts = mergeReplacingById(existing: message.contacts, incoming: output.contacts)
        }
        if !output.invoices.isEmpty {
            message.invoices = mergeReplacingById(existing: message.invoices, incoming: output.invoices)
        }
        if !output.meetings.isEmpty {
            message.meetings = mergeReplacingById(existing: message.meetings, incoming: output.meetings)
        }

        // taskId：保持最后一次为准
        if let taskId = output.taskId, !taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.notes = taskId
        }
    }

    // MARK: - Final (non-delta)

    private static func applyFinal(_ output: BackendChatStructuredOutput, to message: inout ChatMessage) {
        let incomingText = BackendChatService.normalizeDisplayText(output.text)
        if !incomingText.isEmpty { message.content = incomingText }

        if !output.segments.isEmpty {
            var normalized: [ChatSegment] = []
            normalized.reserveCapacity(output.segments.count)
            for seg in output.segments {
                switch seg.kind {
                case .text:
                    let t = BackendChatService.normalizeDisplayText(seg.text ?? "")
                    if !t.isEmpty { normalized.append(.text(t)) }
                case .scheduleCards, .contactCards, .invoiceCards, .meetingCards:
                    normalized.append(seg)
                }
            }
            message.segments = normalized.isEmpty ? nil : normalized
        }

        if !output.scheduleEvents.isEmpty { message.scheduleEvents = output.scheduleEvents }
        if !output.contacts.isEmpty { message.contacts = output.contacts }
        if !output.invoices.isEmpty { message.invoices = output.invoices }
        if !output.meetings.isEmpty { message.meetings = output.meetings }
    }

    // MARK: - Small helpers

    private static func mergeReplacingById<T: Identifiable>(existing: [T]?, incoming: [T]) -> [T] where T.ID: Equatable {
        var result = existing ?? []
        for item in incoming {
            if let idx = result.firstIndex(where: { $0.id == item.id }) {
                result[idx] = item
            } else {
                result.append(item)
            }
        }
        return result
    }

    private static func mergeSchedulesPreferIncoming(existing: [ScheduleEvent]?, incoming: [ScheduleEvent]) -> [ScheduleEvent] {
        var result = existing ?? []
        func key(_ e: ScheduleEvent) -> String { ChatCardStableId.schedule(e) }
        for inc in incoming {
            let k = key(inc)
            if let idx = result.firstIndex(where: { key($0) == k }) {
                // 直接用 incoming 覆盖：后续 chunk 通常更完整（card 覆盖 tool）
                result[idx] = inc
            } else {
                result.append(inc)
            }
        }
        return result
    }
}


