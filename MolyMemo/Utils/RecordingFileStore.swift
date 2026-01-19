import Foundation

/// 录音文件持久化：把临时目录的录音复制到 App Group 容器，避免后台上传时临时文件被系统回收。
enum RecordingFileStore {
    static func appGroupRecordingsFolder() throws -> URL {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupId) else {
            throw NSError(domain: "RecordingFileStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取 App Group 容器目录"])
        }
        let folder = base.appendingPathComponent("MeetingRecordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// 将录音文件复制到 App Group 目录，返回新 URL。
    /// - Note: 使用 copy（不 move），避免影响现有前台链路对临时文件的读取。
    static func persistToAppGroup(originalURL: URL) throws -> URL {
        // 已经在 App Group 里就直接返回
        if let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupId),
           originalURL.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path) {
            return originalURL
        }

        let folder = try appGroupRecordingsFolder()
        let ext = originalURL.pathExtension.isEmpty ? "m4a" : originalURL.pathExtension
        let fileName = "meeting_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).\(ext)"
        let dst = folder.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: dst.path) {
            return dst
        }

        try FileManager.default.copyItem(at: originalURL, to: dst)
        return dst
    }
}

