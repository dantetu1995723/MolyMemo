import Foundation
import SwiftData

/// 统一的 SwiftData 容器工厂：主App / AppIntent / Widget(如需) 共用同一份 Store。
/// 关键点（旧）：把 store 放在 App Group 容器里，解决 AppIntent 独立进程无法访问主App沙盒数据的问题。
/// 关键点（现）：统一后端接入后，不再做本地落盘；SwiftData 只用于进程内状态（内存库）。
enum SharedModelContainer {
    static let appGroupId = "group.com.yuanyuan.shared"
    static let storeFilename = "default.store"

    static func makeContainer() throws -> ModelContainer {
        let config = try makeConfiguration()
        return try ModelContainer(
            for: PersistentChatMessage.self,
               DailyChatSummary.self,
               TodoItem.self,
               Contact.self,
               Expense.self,
               CompanyInfo.self,
               Meeting.self,
            configurations: config
        )
    }

    static func makeConfiguration() throws -> ModelConfiguration {
        // 统一后端接入：禁用落盘（仅保留进程内数据），避免历史本地数据与后端产生冲突。
        return ModelConfiguration(isStoredInMemoryOnly: true)
    }

    /// 尝试把旧位置的 store 迁移到 App Group（只做一次，失败也不阻塞启动）。
    static func migrateLegacyStoreIfNeeded() {
        // 统一后端接入后已禁用本地落盘：迁移逻辑不再需要。
    }
}


