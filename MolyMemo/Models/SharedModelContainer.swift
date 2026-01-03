import Foundation
import SwiftData

/// 统一的 SwiftData 容器工厂：主App / AppIntent / Widget(如需) 共用同一份 Store。
/// 关键点（旧）：把 store 放在 App Group 容器里，解决 AppIntent 独立进程无法访问主App沙盒数据的问题。
/// 关键点（现）：为支持 AppIntent（快捷指令）后台写入聊天记录，需要恢复为 App Group 落盘同一份 store。
enum SharedModelContainer {
    static let appGroupId = AppIdentifiers.appGroupId
    static let storeFilename = "default.store"
    // schema 变更兜底：当旧 store 无法用新 schema 打开时，自动切换到新文件继续运行
    static let fallbackStoreFilename = "default_v2.store"
    private static let activeStoreKey = "swiftdata.activeStoreFilename"

    static func makeContainer() throws -> ModelContainer {
        // ✅ 关键：主App / AppIntent / Widget 必须使用“同一份”store 文件。
        // 如果某个进程因为 schema 不兼容/瞬态错误切换到了 fallback 文件，但其他进程仍在读旧文件，
        // 就会出现“快捷指令写入了，但进App看不到/不刷新”的分叉。
        //
        // 这里用 App Group UserDefaults 记录当前激活的 store 文件名，确保所有进程一致。
        let defaults = UserDefaults(suiteName: appGroupId)
        let preferred = (defaults?.string(forKey: activeStoreKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [String] = {
            if !preferred.isEmpty {
                return [preferred, storeFilename, fallbackStoreFilename].dedup()
            } else {
                return [storeFilename, fallbackStoreFilename]
            }
        }()

        var lastError: Error?
        for name in candidates {
            do {
                let config = try makeConfiguration(filename: name)
                let container = try ModelContainer(
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
                // 成功后写入“全局一致”的 active store
                defaults?.set(name, forKey: activeStoreKey)
                return container
            } catch {
                lastError = error
                continue
            }
        }

        // 所有候选都失败：抛出最后一次错误
        throw lastError ?? NSError(domain: "SharedModelContainer", code: -1)
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

private extension Array where Element == String {
    func dedup() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in self {
            guard !seen.contains(s) else { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }
}


