import Foundation
import UIKit

/// AppIntent -> 主App 的“待发送截图”队列（App Group 文件队列）。
/// 目的：避免依赖 App Group UserDefaults（真机上可能出现 CFPreferences Container:(null) 导致读写失效）。
enum PendingScreenshotQueue {
    private static let dirName = "pending_screenshots"

    static func appGroupURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupId)
    }

    static func directoryURL() -> URL? {
        appGroupURL()?.appendingPathComponent(dirName, isDirectory: true)
    }

    /// 写入一条待发送截图（jpg），返回相对路径（相对 App Group 根目录）。
    static func enqueue(image: UIImage) -> String? {
        guard let groupURL = appGroupURL(),
              let dir = directoryURL() else { return nil }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("PendingScreenshotQueue mkdir failed: \(error)")
            #endif
            return nil
        }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let name = "pending_\(ts)_\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(name)

        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("PendingScreenshotQueue write failed: \(error)")
            #endif
            return nil
        }

        #if DEBUG
        AppGroupDebugLog.append("PendingScreenshotQueue wrote bytes=\(data.count) file=\(name)")
        #endif

        // 返回相对路径
        return "\(dirName)/\(name)"
    }

    /// 列出当前队列（按文件名时间戳升序）。
    static func listPendingRelativePaths(limit: Int = 8) -> [String] {
        guard let dir = directoryURL() else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }

        let jpgs = items
            .filter { $0.hasSuffix(".jpg") && $0.hasPrefix("pending_") }
            .sorted()
            .prefix(max(0, limit))

        return jpgs.map { "\(dirName)/\($0)" }
    }

    static func loadImage(relativePath: String) -> UIImage? {
        guard let groupURL = appGroupURL() else { return nil }
        let url = groupURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func remove(relativePath: String) {
        guard let groupURL = appGroupURL() else { return }
        let url = groupURL.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }
}


