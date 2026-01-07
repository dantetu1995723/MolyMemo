import Foundation
import SwiftData

/// 统一收口“删除”逻辑，保证列表左滑删除与详情页删除走同一条后端路径。
enum DeleteActions {
    @MainActor
    static func deleteContact(_ contact: Contact, modelContext: ModelContext) async throws {
        let rid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rid.isEmpty {
            try await ContactService.deleteContact(remoteId: rid)
        }
        // 统一为软删除：不真正移除 SwiftData 记录，保持工具箱/聊天室可展示“变灰划杠”的删除态
        contact.isObsolete = true
        contact.lastModified = Date()
        try? modelContext.save()
    }
    
    /// 删除后端日程（若无 remoteId，则视为“仅本地态”直接返回成功，保持与详情页一致）
    @MainActor
    static func deleteRemoteSchedule(_ event: ScheduleEvent) async throws {
        let rid = (event.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rid.isEmpty {
            throw ScheduleService.ScheduleServiceError.parseFailed("remoteId empty")
        }
        try await ScheduleService.deleteSchedule(remoteId: rid)
    }
}


