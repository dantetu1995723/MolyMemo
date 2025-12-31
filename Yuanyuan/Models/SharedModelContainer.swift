import Foundation
import SwiftData

/// 统一的 SwiftData 容器工厂：主App / AppIntent / Widget(如需) 共用同一份 Store。
/// 关键点（旧）：把 store 放在 App Group 容器里，解决 AppIntent 独立进程无法访问主App沙盒数据的问题。
/// 关键点（现）：为支持 AppIntent（快捷指令）后台写入聊天记录，需要恢复为 App Group 落盘同一份 store。
enum SharedModelContainer {
    static let appGroupId = "group.com.yuanyuan.shared"
    static let storeFilename = "default.store"
    // schema 变更兜底：当旧 store 无法用新 schema 打开时，自动切换到新文件继续运行
    static let fallbackStoreFilename = "default_v2.store"

    static func makeContainer() throws -> ModelContainer {
        do {
            let config = try makeConfiguration(filename: storeFilename)
            return try ModelContainer(
                for: PersistentChatMessage.self,
                   TodoItem.self,
                   Contact.self,
                   Expense.self,
                   CompanyInfo.self,
                   Meeting.self,
                   StoredScheduleCardBatch.self,
                   StoredContactCardBatch.self,
                   StoredInvoiceCardBatch.self,
                   StoredMeetingCardBatch.self,
                configurations: config
            )
        } catch {
            // 典型场景：删除/移除 model 后，旧 store schema 不兼容导致容器初始化失败
            // 按你的要求“彻底移除”，这里不做迁移，直接创建新 store 继续运行
            print("⚠️ [SharedModelContainer] 打开旧 store 失败，将创建新 store：\(error)")
            let fallback = try makeConfiguration(filename: fallbackStoreFilename)
            return try ModelContainer(
                for: PersistentChatMessage.self,
                   TodoItem.self,
                   Contact.self,
                   Expense.self,
                   CompanyInfo.self,
                   Meeting.self,
                   StoredScheduleCardBatch.self,
                   StoredContactCardBatch.self,
                   StoredInvoiceCardBatch.self,
                   StoredMeetingCardBatch.self,
                configurations: fallback
            )
        }
    }

    static func makeConfiguration(filename: String) throws -> ModelConfiguration {
        let fm = FileManager.default
        guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            // 兜底：拿不到 App Group 时退回内存库，避免启动崩溃
            return ModelConfiguration(isStoredInMemoryOnly: true)
        }
        let storeURL = groupURL.appendingPathComponent(filename)
        return ModelConfiguration(url: storeURL)
    }

    /// 尝试把旧位置的 store 迁移到 App Group（只做一次，失败也不阻塞启动）。
    static func migrateLegacyStoreIfNeeded() {
        // 当前已统一使用 App Group store：如需迁移旧数据，可在这里实现一次性迁移。
    }
}


