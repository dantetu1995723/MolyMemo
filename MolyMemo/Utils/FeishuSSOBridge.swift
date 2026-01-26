import Foundation
#if canImport(UIKit)
import UIKit
#endif

import LarkSSOSDK

/// 飞书官方「LarkSSOSDK」桥接层（对齐官方 Demo 的 register/send/handleURL 流程）。
enum FeishuSSOBridge {
    /// 飞书开放平台 AppID（带下划线）
    static let appId: String = "cli_a9fa1ef2c4381cb1"

    /// 回跳 scheme：AppID 去掉下划线
    static let callbackScheme: String = "clia9fa1ef2c4381cb1"

    enum SSOError: LocalizedError {
        case noPresentingViewController
        case loginFailed(String)

        var errorDescription: String? {
            switch self {
            case .noPresentingViewController:
                return "无法获取用于展示授权页的界面（presenting VC 为空）"
            case let .loginFailed(msg):
                return "飞书授权失败：\(msg)"
            }
        }
    }

    /// App 启动时调用：注册飞书应用（与官方 Demo 一致）
    static func setupIfPossible() {
        let app = App(server: .feishu, appId: appId, scheme: callbackScheme)
        LarkSSO.register(apps: [app])
        LarkSSO.setupLang("zh")
        _ = LarkSSO.setupLog()

#if DEBUG || targetEnvironment(simulator)
        print("🔐 [FeishuSSO] LarkSSOSDK setup ok. appId=\(appId) scheme=\(callbackScheme)")
#endif
    }

    /// SwiftUI `.onOpenURL`：把回调 URL 交给 SDK 处理
    static func handleOpenURL(_ url: URL) -> Bool {
        // 官方 Demo：无条件交给 SDK handle
        _ = LarkSSO.handleURL(url)
        return url.scheme == callbackScheme
    }

    /// 发起飞书授权，返回授权码（用于后端 `/verify_lark_auth_code`）。
    @MainActor
    static func authorizeForCode(timeoutSeconds: TimeInterval = 20) async throws -> String {
        guard let vc = topMostViewController() else {
            throw SSOError.noPresentingViewController
        }

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            func resumeOnce(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                if didResume { return }
                didResume = true
                switch result {
                case let .success(code):
                    continuation.resume(returning: code)
                case let .failure(err):
                    continuation.resume(throwing: err)
                }
            }

            // 诊断：是否能打开飞书
            let canOpenLark = UIApplication.shared.canOpenURL(URL(string: "lark://")!)
            let canOpenFeishu = UIApplication.shared.canOpenURL(URL(string: "feishu://")!)
#if DEBUG || targetEnvironment(simulator)
            print("🔐 [FeishuSSO] canOpenURL lark://=\(canOpenLark) feishu://=\(canOpenFeishu)")
#endif

            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                resumeOnce(.failure(SSOError.loginFailed("等待飞书回跳超时（\(Int(timeoutSeconds))s）。请确认：已安装并登录飞书、允许跳转、回跳 scheme 配置正确。")))
            }

            final class DelegateBox: NSObject, LarkSSODelegate {
                let onDone: (Result<String, Error>) -> Void
                init(onDone: @escaping (Result<String, Error>) -> Void) { self.onDone = onDone }

                func lkSSODidReceive(response: LarkSSOSDK.SSOResponse) {
                    response.safeHandleResult { code in
                        self.onDone(.success(code))
                    } failure: { err in
#if DEBUG || targetEnvironment(simulator)
                        print("🔐 [FeishuSSO] failed: type=\(err.type) raw=\(err.type.rawValue) desc=\(err.description)")
#endif
                        self.onDone(.failure(SSOError.loginFailed(err.description)))
                    }
                }
            }

            let delegate = DelegateBox(onDone: resumeOnce)
            // 让 delegate 在回调前不被释放：挂在 vc 上
            objc_setAssociatedObject(vc, "feishu_sso_delegate_box", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            LarkSSO.send(request: .feishu, viewController: vc, delegate: delegate)
        }
    }

    @MainActor
    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        guard let keyWindow = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return nil }
        var vc = keyWindow.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

