import Foundation

#if DEBUG
/// AppIntent 与主App跨进程调试日志：
/// - 写入 App Group 文件，避免 “AppIntent 日志不进 Xcode 控制台” 导致无法定位。
enum AppGroupDebugLog {
    private static let filename = "pending_debug.log"
    private static let maxBytes: Int = 64 * 1024

    private static func fileURL() -> URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupId) else {
            return nil
        }
        return groupURL.appendingPathComponent(filename)
    }

    static func append(_ message: String) {
        guard let url = fileURL() else { return }
        let line = "[\(Date().timeIntervalSince1970)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: [.atomic])
            }

            // 截断到最近 maxBytes，避免无限增长
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber,
               size.intValue > maxBytes,
               let full = try? Data(contentsOf: url) {
                let start = max(0, full.count - maxBytes)
                let tail = full.subdata(in: start..<full.count)
                try tail.write(to: url, options: [.atomic])
            }
        } catch {
            // 调试日志不应影响主流程
        }
    }

    /// 读出并打印最近日志（用于主App控制台显示）
    static func dumpToConsole(prefix: String = "🧾 [AppGroupDebug]") {
        guard let url = fileURL() else {
            return
        }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        for line in text.split(separator: "\n").suffix(40) {
            print("\(prefix) \(line)")
        }
    }
}
#endif


