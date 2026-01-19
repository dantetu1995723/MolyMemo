import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 将 App 缩回后台（用于快捷指令启动后“自动缩小到灵动岛”体验）。
///
/// 注意：iOS 没有公开 API 直接“回到桌面”。这里用业内常见的 selector 技巧，尽量做成无副作用、失败即忽略。
enum AppMinimizer {
    static func minimizeToHomeIfPossible() {
        #if canImport(UIKit)
        // 避免在 extension 环境误调用
        guard !Bundle.main.bundlePath.hasSuffix(".appex") else { return }

        // 通过 UIControl 触发 UIApplication 的 suspend（失败则无事发生）
        UIControl().sendAction(#selector(NSXPCConnection.suspend), to: UIApplication.shared, for: nil)
        #endif
    }
}

