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

        func mergeStreamingText(existing: String, incoming: String) -> String {
            if existing.isEmpty { return incoming }
            if incoming.isEmpty { return existing }
            if incoming.hasPrefix(existing) { return incoming } // 兼容“累计全文”流式
            if existing.hasSuffix(incoming) { return existing } // 兼容重复 delta
            return existing + incoming
        }

        func scheduleStableId(_ event: ScheduleEvent) -> String { ChatCardStableId.schedule(event) }
        func contactStableId(_ card: ContactCard) -> String { ChatCardStableId.contact(card) }
        func meetingStableId(_ card: MeetingCard) -> String { ChatCardStableId.meeting(card) }

        var seenScheduleIds: Set<String> = Set(existing.flatMap { ($0.scheduleEvents ?? []).map(scheduleStableId) })
        var seenContactIds: Set<String> = Set(existing.flatMap { ($0.contacts ?? []).map(contactStableId) })
        var seenInvoiceIds: Set<String> = Set(existing.flatMap { ($0.invoices ?? []).map(ChatCardStableId.invoice) })
        var seenMeetingIds: Set<String> = Set(existing.flatMap { ($0.meetings ?? []).map(meetingStableId) })

        func isBetterContact(_ incoming: ContactCard, than existing: ContactCard) -> Bool {
            // 规则：优先“更完整/更可用”的那份
            // - 有 remoteId > 没有 remoteId（决定能否 GET 详情/PUT 更新/DELETE）
            // - 字段更丰富 > 字段更稀疏
            func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let incRid = !trimmed(incoming.remoteId).isEmpty
            let exRid = !trimmed(existing.remoteId).isEmpty
            if incRid != exRid { return incRid }

            func score(_ c: ContactCard) -> Int {
                var n = 0
                if !trimmed(c.company).isEmpty { n += 1 }
                if !trimmed(c.title).isEmpty { n += 1 }
                if !trimmed(c.phone).isEmpty { n += 1 }
                if !trimmed(c.email).isEmpty { n += 1 }
                if !trimmed(c.industry).isEmpty { n += 1 }
                if !trimmed(c.location).isEmpty { n += 1 }
                if !trimmed(c.birthday).isEmpty { n += 1 }
                if !trimmed(c.gender).isEmpty { n += 1 }
                if !trimmed(c.relationshipType).isEmpty { n += 1 }
                if !trimmed(c.notes).isEmpty { n += 1 }
                if !trimmed(c.impression).isEmpty { n += 1 }
                if !trimmed(c.englishName).isEmpty { n += 1 }
                if c.avatarData != nil { n += 1 }
                return n
            }
            let incScore = score(incoming)
            let exScore = score(existing)
            if incScore != exScore { return incScore > exScore }
            // 兜底：后到的覆盖（通常是“后端补齐字段”的那一份）
            return true
        }

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

        func replaceExistingContactIfNeeded(key: String, incoming: ContactCard) {
            // 在已有 segments 里找到同 key 的 contact 并替换（用于“后端后续补齐 remoteId/行业等字段”）
            for sIdx in existing.indices {
                guard existing[sIdx].kind == .contactCards else { continue }
                guard var cs = existing[sIdx].contacts, !cs.isEmpty else { continue }
                if let cIdx = cs.firstIndex(where: { contactStableId($0) == key }) {
                    if isBetterContact(incoming, than: cs[cIdx]) {
                        cs[cIdx] = incoming
                        existing[sIdx].contacts = cs
                    }
                    return
                }
            }
        }

        if !output.segments.isEmpty {
            for seg in output.segments {
                switch seg.kind {
                case .text:
                    // ✅ 后端现在可能是“逐字/逐 token”分段返回：必须拼接到最后一个 text segment
                    let t = BackendChatService.normalizeDisplayDeltaText(seg.text ?? "")
                    guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    if let last = existing.indices.last, existing[last].kind == .text {
                        let base = existing[last].text ?? ""
                        existing[last].text = mergeStreamingText(existing: base, incoming: t)
                    } else {
                        existing.append(.text(t))
                    }

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
                        var filtered: [ContactCard] = []
                        filtered.reserveCapacity(incoming.count)
                        for c in incoming {
                            let key = contactStableId(c)
                            if seenContactIds.contains(key) {
                                replaceExistingContactIfNeeded(key: key, incoming: c)
                                continue
                            }
                            seenContactIds.insert(key)
                            filtered.append(c)
                        }
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
        let incomingText = BackendChatService.normalizeDisplayDeltaText(output.text)
        if !incomingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 不做 trim，否则英文 token 的前导空格会丢；是否展示由 UI 侧决定
            message.content = mergeStreamingText(existing: message.content, incoming: incomingText)
        }

        // 3) 卡片聚合字段：合并去重（用于详情页/复制卡片信息复用）
        if !output.scheduleEvents.isEmpty {
            message.scheduleEvents = mergeSchedulesPreferIncoming(existing: message.scheduleEvents, incoming: output.scheduleEvents)
        }
        if !output.contacts.isEmpty {
            message.contacts = mergeContactsPreferIncoming(existing: message.contacts, incoming: output.contacts)
        }
        if !output.invoices.isEmpty {
            message.invoices = mergeReplacingById(existing: message.invoices, incoming: output.invoices)
        }
        if !output.meetings.isEmpty {
            message.meetings = mergeReplacingById(existing: message.meetings, incoming: output.meetings)
        }
        
        // 4) 关键：把“聚合字段里更完整的 remoteId”等信息回填到 segments（卡片渲染源）
        // 否则会出现：聚合 scheduleEvents 有 remoteId，但卡片里的 event.remoteId 为空，
        // 从卡片进入详情无法 PUT 更新后端，导致“卡片改了但工具箱列表/通知栏没改”。
        backfillScheduleRemoteIdsFromAggregate(into: &message)
        backfillContactFieldsFromAggregate(into: &message)

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
        
        // 同上：final 输出也需要回填到 segments
        backfillScheduleRemoteIdsFromAggregate(into: &message)
        backfillContactFieldsFromAggregate(into: &message)
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

    private static func mergeContactsPreferIncoming(existing: [ContactCard]?, incoming: [ContactCard]) -> [ContactCard] {
        var result: [String: ContactCard] = [:]
        result.reserveCapacity((existing?.count ?? 0) + incoming.count)

        func key(_ c: ContactCard) -> String { ChatCardStableId.contact(c) }
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func isBetter(_ inc: ContactCard, than ex: ContactCard) -> Bool {
            let incRid = !trimmed(inc.remoteId).isEmpty
            let exRid = !trimmed(ex.remoteId).isEmpty
            if incRid != exRid { return incRid }

            func score(_ c: ContactCard) -> Int {
                var n = 0
                if !trimmed(c.company).isEmpty { n += 1 }
                if !trimmed(c.title).isEmpty { n += 1 }
                if !trimmed(c.phone).isEmpty { n += 1 }
                if !trimmed(c.email).isEmpty { n += 1 }
                if !trimmed(c.industry).isEmpty { n += 1 }
                if !trimmed(c.location).isEmpty { n += 1 }
                if !trimmed(c.birthday).isEmpty { n += 1 }
                if !trimmed(c.gender).isEmpty { n += 1 }
                if !trimmed(c.relationshipType).isEmpty { n += 1 }
                if !trimmed(c.notes).isEmpty { n += 1 }
                if !trimmed(c.impression).isEmpty { n += 1 }
                if !trimmed(c.englishName).isEmpty { n += 1 }
                if c.avatarData != nil { n += 1 }
                return n
            }
            let incScore = score(inc)
            let exScore = score(ex)
            if incScore != exScore { return incScore > exScore }
            return true
        }

        // 先放 existing
        for c in (existing ?? []) {
            let k = key(c)
            result[k] = c
        }
        // incoming 覆盖/补齐
        for c in incoming {
            let k = key(c)
            if let ex = result[k] {
                if isBetter(c, than: ex) {
                    result[k] = c
                }
            } else {
                result[k] = c
            }
        }
        return Array(result.values)
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
    
    /// 将 message.scheduleEvents 里的 remoteId 回填到 message.segments 的 scheduleCards 里（仅补齐缺失字段，不覆盖已有值）。
    private static func backfillScheduleRemoteIdsFromAggregate(into message: inout ChatMessage) {
        guard let segs = message.segments, !segs.isEmpty else { return }
        guard let agg = message.scheduleEvents, !agg.isEmpty else { return }
        
        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // 用本地 id 做最稳定的回填 key（segments 与聚合通常共享同一个本地 id）
        var idToRemoteId: [UUID: String] = [:]
        idToRemoteId.reserveCapacity(agg.count)
        for e in agg {
            let rid = trimmed(e.remoteId)
            guard !rid.isEmpty else { continue }
            idToRemoteId[e.id] = rid
        }
        guard !idToRemoteId.isEmpty else { return }
        
        var updated = segs
        var changed = false
        for i in updated.indices {
            guard updated[i].kind == .scheduleCards else { continue }
            guard var events = updated[i].scheduleEvents, !events.isEmpty else { continue }
            var localChanged = false
            for j in events.indices {
                if trimmed(events[j].remoteId).isEmpty, let rid = idToRemoteId[events[j].id] {
                    events[j].remoteId = rid
                    localChanged = true
                }
            }
            if localChanged {
                updated[i].scheduleEvents = events
                changed = true
            }
        }
        if changed {
            message.segments = updated
        }
    }

    /// 将 message.contacts 里的 remoteId/字段回填到 message.segments 的 contactCards 里（仅补齐缺失字段，不覆盖已有值）。
    private static func backfillContactFieldsFromAggregate(into message: inout ChatMessage) {
        guard let segs = message.segments, !segs.isEmpty else { return }
        guard let agg = message.contacts, !agg.isEmpty else { return }

        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func key(_ c: ContactCard) -> String { ChatCardStableId.contact(c) }

        // 以 stableId 做回填 key：联系人卡片不保证共享同一个 UUID id
        var bestByKey: [String: ContactCard] = [:]
        bestByKey.reserveCapacity(agg.count)
        for c in agg {
            let k = key(c)
            if let ex = bestByKey[k] {
                // 只要有 remoteId/字段更多，就认为更好
                let incRid = !trimmed(c.remoteId).isEmpty
                let exRid = !trimmed(ex.remoteId).isEmpty
                if incRid && !exRid {
                    bestByKey[k] = c
                } else if (!incRid && exRid) {
                    // keep
                } else {
                    // 兜底：后到覆盖（聚合通常是更完整的）
                    bestByKey[k] = c
                }
            } else {
                bestByKey[k] = c
            }
        }
        guard !bestByKey.isEmpty else { return }

        var updated = segs
        var changed = false
        for i in updated.indices {
            guard updated[i].kind == .contactCards else { continue }
            guard var cs = updated[i].contacts, !cs.isEmpty else { continue }
            var localChanged = false
            for j in cs.indices {
                let k = key(cs[j])
                guard let best = bestByKey[k] else { continue }
                // 只补齐缺失字段
                if trimmed(cs[j].remoteId).isEmpty, !trimmed(best.remoteId).isEmpty {
                    cs[j].remoteId = best.remoteId
                    localChanged = true
                }
                if trimmed(cs[j].industry).isEmpty, !trimmed(best.industry).isEmpty {
                    cs[j].industry = best.industry
                    localChanged = true
                }
                if trimmed(cs[j].company).isEmpty, !trimmed(best.company).isEmpty {
                    cs[j].company = best.company
                    localChanged = true
                }
                if trimmed(cs[j].title).isEmpty, !trimmed(best.title).isEmpty {
                    cs[j].title = best.title
                    localChanged = true
                }
                if trimmed(cs[j].phone).isEmpty, !trimmed(best.phone).isEmpty {
                    cs[j].phone = best.phone
                    localChanged = true
                }
                if trimmed(cs[j].email).isEmpty, !trimmed(best.email).isEmpty {
                    cs[j].email = best.email
                    localChanged = true
                }
                if trimmed(cs[j].location).isEmpty, !trimmed(best.location).isEmpty {
                    cs[j].location = best.location
                    localChanged = true
                }
                if trimmed(cs[j].birthday).isEmpty, !trimmed(best.birthday).isEmpty {
                    cs[j].birthday = best.birthday
                    localChanged = true
                }
                if trimmed(cs[j].gender).isEmpty, !trimmed(best.gender).isEmpty {
                    cs[j].gender = best.gender
                    localChanged = true
                }
                if trimmed(cs[j].relationshipType).isEmpty, !trimmed(best.relationshipType).isEmpty {
                    cs[j].relationshipType = best.relationshipType
                    localChanged = true
                }
                if trimmed(cs[j].notes).isEmpty, !trimmed(best.notes).isEmpty {
                    cs[j].notes = best.notes
                    localChanged = true
                }
                if trimmed(cs[j].impression).isEmpty, !trimmed(best.impression).isEmpty {
                    cs[j].impression = best.impression
                    localChanged = true
                }
                if trimmed(cs[j].englishName).isEmpty, !trimmed(best.englishName).isEmpty {
                    cs[j].englishName = best.englishName
                    localChanged = true
                }
                if cs[j].avatarData == nil, let a = best.avatarData {
                    cs[j].avatarData = a
                    localChanged = true
                }
            }
            if localChanged {
                updated[i].contacts = cs
                changed = true
            }
        }
        if changed {
            message.segments = updated
        }
    }
}


