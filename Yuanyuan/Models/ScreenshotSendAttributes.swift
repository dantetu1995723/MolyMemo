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
    }

    var title: String
}


