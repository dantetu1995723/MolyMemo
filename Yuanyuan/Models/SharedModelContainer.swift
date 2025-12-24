import Foundation
import SwiftData

/// 统一的 SwiftData 容器工厂：主App / AppIntent / Widget(如需) 共用同一份 Store。
/// 关键点：把 store 放在 App Group 容器里，解决 AppIntent 独立进程无法访问主App沙盒数据的问题。
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
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            throw NSError(domain: "SharedModelContainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取 App Group 容器路径"])
        }
        let storeURL = groupURL.appendingPathComponent(storeFilename)
        return ModelConfiguration(url: storeURL, allowsSave: true)
    }

    /// 尝试把旧位置的 store 迁移到 App Group（只做一次，失败也不阻塞启动）。
    static func migrateLegacyStoreIfNeeded() {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return
        }

        let targetURL = groupURL.appendingPathComponent(storeFilename)
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            return
        }

        // 旧逻辑里默认会落到 Application Support/default.store
        guard let legacyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(storeFilename),
              FileManager.default.fileExists(atPath: legacyURL.path)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: legacyURL, to: targetURL)
            // 只复制不删除：避免极端情况下 copy 成功但主App仍在用旧 store 导致丢数据。
            print("✅ [SharedModelContainer] 已迁移旧数据库到 App Group: \(targetURL.lastPathComponent)")
        } catch {
            print("⚠️ [SharedModelContainer] 迁移旧数据库失败（可忽略）: \(error)")
        }
    }
}


