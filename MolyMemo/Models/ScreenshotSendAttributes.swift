import Foundation
import ActivityKit

/// “发送截图到聊天室” Live Activity（用于灵动岛提示）
struct ScreenshotSendAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case sending
            case sent
            case failed
        }

        var status: Status
        var message: String
        /// App Group 内缩略图相对路径（由主App/AppIntent写入，Widget读取展示）
        var thumbnailRelativePath: String?
    }

    var title: String

    // MARK: - App Group helpers (Widget 与主App共享)

    static let appGroupId = AppIdentifiers.appGroupId

    static func appGroupURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    static func thumbnailURL(relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        return appGroupURL()?.appendingPathComponent(relativePath)
    }
}


