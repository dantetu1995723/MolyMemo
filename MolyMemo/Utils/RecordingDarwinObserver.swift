import Foundation

/// 录音跨进程命令监听（Darwin Notify -> 主App）
///
/// 注意：Darwin 通知不携带 payload，需要配合 App Group UserDefaults 读取参数。
final class RecordingDarwinObserver {
    static let shared = RecordingDarwinObserver()

    private var token: UnsafeRawPointer?
    private var installed = false

    private init() {}

    func installIfNeeded() {
        guard !installed else { return }
        installed = true

        let t = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        token = t

        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer else { return }
            let obj = Unmanaged<RecordingDarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            obj.handleNotification(name: name)
        }

        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.start, callback: callback)
        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.pause, callback: callback)
        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.resume, callback: callback)
        DarwinNotificationCenter.addObserver(t, name: RecordingDarwinNames.stop, callback: callback)

    }

    func uninstallIfNeeded() {
        guard installed, let t = token else { return }
        DarwinNotificationCenter.removeObserver(t)
        token = nil
        installed = false
    }

    private func handleNotification(name: CFNotificationName?) {
        guard let raw = name?.rawValue as String? else { return }
        DispatchQueue.main.async {
            // 统一走 “pending command + 时间戳去重” 处理器，避免两路触发重复执行。
            RecordingCommandProcessor.shared.processIfNeeded(source: "darwin:\(raw)")
        }
    }
}


