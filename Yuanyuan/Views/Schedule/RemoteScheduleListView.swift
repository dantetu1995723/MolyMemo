import SwiftUI

/// 后端日程列表（/api/v1/schedules）
struct RemoteScheduleListView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var events: [ScheduleEvent] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil
    
    @State private var selectedEvent: ScheduleEvent? = nil
    
    private func isSameRemote(_ a: ScheduleEvent, _ b: ScheduleEvent) -> Bool {
        let ra = (a.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rb = (b.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ra.isEmpty, !rb.isEmpty { return ra == rb }
        return a.id == b.id
    }
    
    @MainActor
    private func applyUpdatedEvent(_ updated: ScheduleEvent) {
        if let idx = events.firstIndex(where: { isSameRemote($0, updated) }) {
            events[idx] = updated
        } else {
            events.append(updated)
        }
        events.sort(by: { $0.startTime < $1.startTime })
        selectedEvent = updated
    }
    
    @MainActor
    private func applyDeletedEvent(_ deleted: ScheduleEvent) {
        events.removeAll(where: { isSameRemote($0, deleted) })
        if let current = selectedEvent, isSameRemote(current, deleted) {
            selectedEvent = nil
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if let errorText {
                        Section {
                            Text(errorText)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                    }
                    
                    Section {
                        if events.isEmpty, !isLoading {
                            Text("暂无日程")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(events) { e in
                                Button {
                                    openDetail(for: e)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Text(e.title)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(e.timeRange)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                        if !e.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(e.description)
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                        if let rid = e.remoteId, !rid.isEmpty {
                                            Text("id: \(rid)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary.opacity(0.8))
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    } header: {
                        Text("后端日程列表")
                    }
                }
                .listStyle(.insetGrouped)
                
                if isLoading {
                    ProgressView("正在获取日程…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("日程（后端）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") { Task { await reload(forceRefresh: true) } }
                        .disabled(isLoading)
                }
            }
            .task {
                if events.isEmpty {
                    await reload()
                }
            }
            .refreshable {
                await reload(forceRefresh: true)
            }
            .sheet(item: $selectedEvent) { _ in
                // 注意：ScheduleDetailSheet 需要 Binding，所以这里用一个 wrapper
                RemoteScheduleDetailSheet(
                    event: $selectedEvent,
                    onCommittedSave: { updated in
                        Task { @MainActor in
                            applyUpdatedEvent(updated)
                        }
                    },
                    onCommittedDelete: { deleted in
                        Task { @MainActor in
                            applyDeletedEvent(deleted)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    @MainActor
    private func reload(forceRefresh: Bool = false) async {
        errorText = nil
        
        // 先用缓存：fresh 直接返回；stale 先展示再后台刷新
        if !forceRefresh, let cached = await ScheduleService.peekScheduleList() {
            events = cached.value.sorted(by: { $0.startTime < $1.startTime })
            if cached.isFresh { return }
            Task { @MainActor in
                await reload(forceRefresh: true)
            }
            return
        }
        
        // 无缓存时才显示 loading（避免每次进入都转圈）
        if events.isEmpty { isLoading = true }
        defer { isLoading = false }
        
        do {
            let list = try await ScheduleService.fetchScheduleList(forceRefresh: forceRefresh)
            events = list.sorted(by: { $0.startTime < $1.startTime })
        } catch {
            errorText = "获取失败：\(error.localizedDescription)"
        }
    }
    
    private func openDetail(for e: ScheduleEvent) {
        // 先打开弹窗，再在弹窗内部拉详情（这样 UI 响应快）
        selectedEvent = e
    }
}

/// 详情 wrapper：打开后如果有 remoteId，会去请求 `/api/v1/schedules/{id}` 并把结果写回 Binding
private struct RemoteScheduleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    /// 注意：这里用 Optional Binding 来驱动 sheet(item:)
    @Binding var event: ScheduleEvent?
    var onCommittedSave: (ScheduleEvent) -> Void
    var onCommittedDelete: (ScheduleEvent) -> Void
    
    var body: some View {
        Group {
            if let binding = bindingForEvent() {
                ScheduleDetailSheet(
                    event: binding,
                    onDelete: {
                        // 由 ScheduleDetailSheet 内部调用后端删除；这里只负责同步列表状态
                        if let deleted = event {
                            onCommittedDelete(deleted)
                        }
                        dismiss()
                    },
                    onSave: { updated in
                        // ScheduleDetailSheet 内部已调用后端更新；这里只负责同步列表状态
                        event = updated
                        onCommittedSave(updated)
                    }
                )
                .task {
                    await loadDetailIfNeeded()
                }
            } else {
                VStack(spacing: 12) {
                    Text("日程不存在")
                        .foregroundColor(.secondary)
                    Button("关闭") { dismiss() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            }
        }
    }
    
    private func bindingForEvent() -> Binding<ScheduleEvent>? {
        guard event != nil else { return nil }
        return Binding(
            get: { event ?? ScheduleEvent(title: "", description: "", startTime: Date(), endTime: Date()) },
            set: { event = $0 }
        )
    }
    
    @MainActor
    private func loadDetailIfNeeded() async {
        guard let current = event else { return }
        guard let rid = current.remoteId, !rid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // 没有 remoteId 就无法拉详情，保留列表信息
            return
        }
        let trimmed = rid.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 先用缓存：避免每次打开都 loading
        if let cached = await ScheduleService.peekScheduleDetail(remoteId: trimmed) {
            var v = cached.value
            v.id = current.id
            event = v
            if cached.isFresh { return }
            
            Task { @MainActor in
                await refreshSilently(remoteId: trimmed, keepLocalId: current.id)
            }
            return
        }
        
        // 首次无缓存：静默拉取，不展示 loading 弹层（避免进入详情页出现弹窗/浮层）
        do {
            let detail = try await ScheduleService.fetchScheduleDetail(remoteId: trimmed, keepLocalId: current.id)
            event = detail
        } catch {
            print("❌ [RemoteScheduleDetailSheet] load detail failed: \(error)")
        }
    }
    
    @MainActor
    private func refreshSilently(remoteId: String, keepLocalId: UUID) async {
        do {
            let detail = try await ScheduleService.fetchScheduleDetail(remoteId: remoteId, keepLocalId: keepLocalId)
            event = detail
        } catch {
            print("❌ [RemoteScheduleDetailSheet] silent refresh failed: \(error)")
        }
    }
}


