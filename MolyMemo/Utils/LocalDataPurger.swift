import Foundation

/// 统一后端接入后：彻底清理历史本地落盘数据/文件，避免与后端数据冲突。
/// - 目标：删除「曾经落盘」的数据；运行期内存状态仍可正常工作（不算本地持久化）。
enum LocalDataPurger {
    /// 清理所有本地数据（建议在 App 启动最早期调用一次）。
    static func purgeAll(reason: String) {
        #if DEBUG
        print("🧹 [LocalDataPurger] 开始清理本地数据：\(reason)")
        #endif

        purgeSwiftDataStores()
        purgeMeetingRecordings()
        purgeTemporaryAudioCache()
        // 注意：不要在每次启动时清空 UserDefaults / AppGroup defaults，否则会导致登录态与配置每次都丢失。
        // 如果未来需要“一键清空配置”，应提供用户显式操作入口，而不是启动即清。

        #if DEBUG
        print("🧹 [LocalDataPurger] 清理完成")
        #endif
    }

    /// 启动期清理：只清理临时文件/缓存，不触碰 SwiftData store（否则会抹掉 AppIntent 写入的聊天记录）。
    static func purgeCaches(reason: String) {
        #if DEBUG
        print("🧹 [LocalDataPurger] 开始清理缓存：\(reason)")
        #endif

        purgeMeetingRecordings()
        purgeTemporaryAudioCache()

        #if DEBUG
        print("🧹 [LocalDataPurger] 缓存清理完成")
        #endif
    }

    // MARK: - SwiftData / Store

    private static func purgeSwiftDataStores() {
        let fm = FileManager.default

        // 1) App Group store
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupId) {
            removeStoreArtifacts(in: groupURL)
        }

        // 2) Legacy store（旧逻辑：Application Support）
        if let legacyDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            removeStoreArtifacts(in: legacyDir)
        }
    }

    private static func removeStoreArtifacts(in directory: URL) {
        let fm = FileManager.default
        let prefix = SharedModelContainer.storeFilename

        // 先按目录扫描删除（覆盖 default.store / default.store-wal 等）
        if let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in urls where url.lastPathComponent.hasPrefix(prefix) {
                try? fm.removeItem(at: url)
            }
        }

        // 再补充删除常见派生文件名（兼容不同实现细节）
        let candidates = [
            prefix,
            "\(prefix)-shm",
            "\(prefix)-wal",
            "\(prefix).sqlite",
            "\(prefix).sqlite-shm",
            "\(prefix).sqlite-wal"
        ]
        for name in candidates {
            let url = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Files

    private static func purgeMeetingRecordings() {
        let fm = FileManager.default

        // 新录音目录（临时）
        let tempFolder = fm.temporaryDirectory.appendingPathComponent("MeetingRecordings", isDirectory: true)
        if fm.fileExists(atPath: tempFolder.path) {
            try? fm.removeItem(at: tempFolder)
        }

        // 旧录音目录（Documents）
        if let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let legacyFolder = documentsURL.appendingPathComponent("MeetingRecordings", isDirectory: true)
            if fm.fileExists(atPath: legacyFolder.path) {
                try? fm.removeItem(at: legacyFolder)
            }
        }
    }

    /// 清理播放缓存：`RecordingPlaybackController` 会把远程音频写入 tmp 以便复用播放。
    private static func purgeTemporaryAudioCache() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let urls = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }

        for url in urls where url.lastPathComponent.hasPrefix("yuanyuan_meeting_audio_") {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - UserDefaults
}


