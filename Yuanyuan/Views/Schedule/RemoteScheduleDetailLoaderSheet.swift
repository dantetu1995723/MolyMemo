import SwiftUI

/// 通用：用于展示 ScheduleDetailSheet，并在打开后（若有 remoteId）自动拉取后端详情覆盖显示
struct RemoteScheduleDetailLoaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    /// 用 Optional Binding 驱动 sheet(item:)
    @Binding var event: ScheduleEvent?
    var onCommittedSave: ((ScheduleEvent) -> Void)? = nil
    var onCommittedDelete: ((ScheduleEvent) -> Void)? = nil
    
    var body: some View {
        Group {
            if let binding = bindingForEvent() {
                ScheduleDetailSheet(
                    event: binding,
                    onDelete: {
                        // 由 ScheduleDetailSheet 内部调用后端删除；这里只负责同步外部列表状态
                        if let deleted = event {
                            onCommittedDelete?(deleted)
                        }
                        dismiss()
                    },
                    onSave: { updated in
                        event = updated
                        onCommittedSave?(updated)
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
            return
        }
        let trimmed = rid.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1) 先用缓存，避免每次打开都 loading
        if let cached = await ScheduleService.peekScheduleDetail(remoteId: trimmed) {
            var v = cached.value
            v.id = current.id
            event = v
            if cached.isFresh { return }
            // 过期：后台静默刷新
            Task {
                await refreshSilently(remoteId: trimmed, keepLocalId: current.id)
            }
            return
        }
        
        // 2) 首次无缓存：静默拉取，不展示 loading 弹层（避免进入详情页出现弹窗/浮层）
        do {
            let detail = try await ScheduleService.fetchScheduleDetail(remoteId: trimmed, keepLocalId: current.id)
            event = detail
        } catch {
            // 静默失败：保留现有信息
        }
    }
    
    @MainActor
    private func refreshSilently(remoteId: String, keepLocalId: UUID) async {
        do {
            let detail = try await ScheduleService.fetchScheduleDetail(remoteId: remoteId, keepLocalId: keepLocalId)
            event = detail
        } catch {
            // 静默失败：不打断用户
        }
    }
}


