import Foundation

/// 全局标识符集中管理：Bundle ID / App Group / URL Scheme / BGTask 等。
/// 统一入口，避免散落字符串导致改名遗漏。
enum AppIdentifiers {
    /// App Group（主 App / Widget / AppIntent 共享）
    static let appGroupId = "group.com.molymemo.shared"

    /// URL Scheme（用于 onOpenURL / Widget Link / OAuth 回调）
    static let urlScheme = "molymemo"

    /// Keychain service 兜底（当 bundleIdentifier 不可用时）
    static let keychainFallbackService = "com.molymemo.app"

    /// BGTask 允许的 identifier（Info.plist 也需要一致）
    static let bgRefreshTaskId = "com.molymemo.app.refresh"
}


