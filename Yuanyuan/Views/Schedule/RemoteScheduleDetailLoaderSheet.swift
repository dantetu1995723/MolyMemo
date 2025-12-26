import SwiftUI

/// 通用：用于展示 ScheduleDetailSheet，并在打开后（若有 remoteId）自动拉取后端详情覆盖显示
struct RemoteScheduleDetailLoaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    /// 用 Optional Binding 驱动 sheet(item:)
    @Binding var event: ScheduleEvent?
    var onCommittedSave: ((ScheduleEvent) -> Void)? = nil
    var onCommittedDelete: ((ScheduleEvent) -> Void)? = nil
    
    @State private var isLoading: Bool = false
    
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
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView("正在获取详情…")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.top, 12)
                    }
                }
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
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let detail = try await ScheduleService.fetchScheduleDetail(remoteId: rid, keepLocalId: current.id)
            event = detail
        } catch {
            print("❌ [RemoteScheduleDetailLoaderSheet] load detail failed: \(error)")
        }
    }
}


