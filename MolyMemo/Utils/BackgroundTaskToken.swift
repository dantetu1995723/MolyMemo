import UIKit

/// 轻量后台执行护栏：让“正在进行中的网络请求”在 App 退到后台后，尽量继续跑完。
///
/// 说明：
/// - iOS 对后台执行时间有严格限制（通常几十秒级，不保证长任务一定完成）。
/// - 该 token 的职责仅是：为“已发起的请求”申请额外时间，避免切后台立刻被挂起/中断。
///
/// ⚠️ 注意：
/// - `deinit` 里**不能**启动 `Task {}` 去捕获 `self`（会触发 “deallocated with non-zero retain count” 这类崩溃）。
/// - 所以这里在 `deinit` 里只捕获 `taskId` 值，并在主线程结束后台任务。
@MainActor
final class BackgroundTaskToken {
    private var taskId: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        taskId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            guard let self else { return }
            // expiration handler 可能不在主线程；切回主线程结束
            DispatchQueue.main.async {
                self.end()
            }
        }
    }

    func end() {
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        taskId = .invalid
    }

    deinit {
        let id = taskId
        guard id != .invalid else { return }
        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(id)
        }
    }
}

