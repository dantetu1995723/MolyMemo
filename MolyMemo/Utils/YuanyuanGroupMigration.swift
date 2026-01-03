import Foundation
import SwiftData

/// 方案 B：从老 App Group（Yuanyuan）迁移聊天数据到新 App Group（MolyMemo）。
///
/// 说明：
/// - iOS 不允许跨 App 沙盒读取数据；只有在两个 target 都声明同一个 App Group 时才能访问其容器。
/// - 这里做“一次性迁移”：读取 `group.com.yuanyuan.shared` 的 SwiftData store，拷贝聊天消息与卡片批次到新 store。
/// - 用 App Group 文件 marker 去重，避免重复迁移导致数据翻倍。
enum YuanyuanGroupMigration {
    static let legacyGroupId = "group.com.yuanyuan.shared"
    private static let markerFileName = ".migrated_from_yuanyuan_group_v1"

    /// 在主 App 启动后调用：若检测到老 store 且未迁移，则执行迁移。
    @MainActor
    static func runIfNeeded(targetContainer: ModelContainer) {
        guard let targetGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupId) else {
            print("🧳 [Migration] target group unavailable: \(AppIdentifiers.appGroupId)")
            return
        }

        let markerURL = targetGroupURL.appendingPathComponent(markerFileName)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            return
        }

        guard let legacyGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: legacyGroupId) else {
            print("🧳 [Migration] legacy group unavailable: \(legacyGroupId)")
            return
        }

        // 选择老 store 文件（优先 v2，防止旧工程也走过 fallback）
        let legacyCandidates = [
            legacyGroupURL.appendingPathComponent(SharedModelContainer.fallbackStoreFilename),
            legacyGroupURL.appendingPathComponent(SharedModelContainer.storeFilename),
        ]
        guard let legacyStoreURL = legacyCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            // 没有老 store：写 marker，避免每次启动都扫描
            try? Data("no_legacy_store".utf8).write(to: markerURL, options: [.atomic])
            return
        }

        // 如果新 store 已经有数据，就不自动迁移（避免把两边都用过的用户合并出重复历史）
        let targetContext = targetContainer.mainContext
        if (try? targetContext.fetchCount(FetchDescriptor<PersistentChatMessage>())) ?? 0 > 0 {
            try? Data("skipped_target_not_empty".utf8).write(to: markerURL, options: [.atomic])
            print("🧳 [Migration] skipped: target already has chat data")
            return
        }

        do {
            let legacyConfig = ModelConfiguration(url: legacyStoreURL)
            let legacyContainer = try ModelContainer(
                for: PersistentChatMessage.self,
                   StoredScheduleCardBatch.self,
                   StoredContactCardBatch.self,
                   StoredInvoiceCardBatch.self,
                   StoredMeetingCardBatch.self,
                configurations: legacyConfig
            )
            let legacyContext = legacyContainer.mainContext

            let msgCount = try migrateChatMessages(from: legacyContext, to: targetContext)
            let batchCount = try migrateCardBatches(from: legacyContext, to: targetContext)
            try targetContext.save()

            let summary = "ok messages=\(msgCount) batches=\(batchCount) legacyStore=\(legacyStoreURL.lastPathComponent)"
            try Data(summary.utf8).write(to: markerURL, options: [.atomic])
            print("🧳 [Migration] \(summary)")
        } catch {
            print("🧳 [Migration] failed: \(error)")
            // 不写 marker：让用户修复签名/权限后还能再试一次
        }
    }

    private static func migrateChatMessages(from legacy: ModelContext, to target: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<PersistentChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let items = try legacy.fetch(descriptor)
        for m in items {
            // 直接拷贝字段（外部存储字段也会跟随 Data 拷贝）
            let copied = PersistentChatMessage(
                id: m.id,
                roleRawValue: m.roleRawValue,
                content: m.content,
                timestamp: m.timestamp,
                isGreeting: m.isGreeting,
                messageTypeRawValue: m.messageTypeRawValue,
                encodedImageData: m.encodedImageData,
                encodedSegments: m.encodedSegments,
                isInterrupted: m.isInterrupted
            )
            target.insert(copied)
        }
        return items.count
    }

    private static func migrateCardBatches(from legacy: ModelContext, to target: ModelContext) throws -> Int {
        var total = 0

        let schedules = try legacy.fetch(FetchDescriptor<StoredScheduleCardBatch>())
        for b in schedules {
            let decoded = b.decodedEvents()
            target.insert(StoredScheduleCardBatch(events: decoded, sourceMessageId: b.sourceMessageId, createdAt: b.createdAt))
        }
        total += schedules.count

        let contacts = try legacy.fetch(FetchDescriptor<StoredContactCardBatch>())
        for b in contacts {
            let decoded = b.decodedContacts()
            target.insert(StoredContactCardBatch(contacts: decoded, sourceMessageId: b.sourceMessageId, createdAt: b.createdAt))
        }
        total += contacts.count

        let invoices = try legacy.fetch(FetchDescriptor<StoredInvoiceCardBatch>())
        for b in invoices {
            let decoded = b.decodedInvoices()
            target.insert(StoredInvoiceCardBatch(invoices: decoded, sourceMessageId: b.sourceMessageId, createdAt: b.createdAt))
        }
        total += invoices.count

        let meetings = try legacy.fetch(FetchDescriptor<StoredMeetingCardBatch>())
        for b in meetings {
            let decoded = b.decodedMeetings()
            target.insert(StoredMeetingCardBatch(meetings: decoded, sourceMessageId: b.sourceMessageId, createdAt: b.createdAt))
        }
        total += meetings.count

        return total
    }
}


