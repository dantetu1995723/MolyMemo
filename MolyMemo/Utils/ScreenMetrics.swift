import UIKit

/// 替代 `UIScreen.main`（iOS 26+ 已废弃）。
/// 通过当前激活的 WindowScene 拿到真实屏幕尺寸；找不到时退化到 `UIScreen.screens.first`。
enum ScreenMetrics {
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
    }

    private static var anyWindowSceneScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
    }
    
    static var bounds: CGRect {
        if let screen = keyWindow?.windowScene?.screen ?? anyWindowSceneScreen {
            return screen.bounds
        }
        return .zero
    }
    
    static var width: CGFloat { bounds.width }
    static var height: CGFloat { bounds.height }
}


