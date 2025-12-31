import Foundation

/// 监听快捷指令/AppIntent 的“聊天数据已更新”Darwin 通知，并在主App进程内转发为 NotificationCenter 通知。
///
/// 注意：
/// - Darwin 通知不携带 payload；这里用 App Group UserDefaults 传递最后更新的消息 id + 时间戳，并做去重。
final class ChatDarwinObserver {
    static let shared = ChatDarwinObserver()

    private var token: UnsafeRawPointer?
    private var installed: Bool = false

    private init() {}

    func installIfNeeded() {
        guard !installed else { return }
        installed = true

        let t = Unmanaged.passRetained(self).toOpaque()
        token = UnsafeRawPointer(t)

        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer else { return }
            let obj = Unmanaged<ChatDarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            obj.handleNotification(name: name)
        }

        DarwinNotificationCenter.addObserver(t, name: ChatDarwinNames.chatUpdated, callback: callback)
        print("✅ ChatDarwinObserver 已注册 Darwin 聊天更新监听")
    }

    func uninstallIfNeeded() {
        guard installed, let t = token else { return }
        DarwinNotificationCenter.removeObserver(t)
        token = nil
        installed = false
        print("🧹 ChatDarwinObserver 已移除 Darwin 聊天更新监听")
    }

    private func handleNotification(name: CFNotificationName?) {
        guard let name, name.rawValue as String == ChatDarwinNames.chatUpdated else { return }

        guard let defaults = UserDefaults(suiteName: ChatSharedDefaults.suite) else { return }

        let ts = defaults.double(forKey: ChatSharedDefaults.lastUpdateTimestampKey)
        guard ts > 0 else { return }

        let idString = (defaults.string(forKey: ChatSharedDefaults.lastInsertedAgentMessageIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID(uuidString: idString)

        NotificationCenter.default.post(name: .yyChatStorageUpdated, object: id)
    }
}

extension Notification.Name {
    /// 主App进程内：聊天 SwiftData 被后台更新（通常来自快捷指令截图发送）
    static let yyChatStorageUpdated = Notification.Name("yy.chat.storage.updated")
}


