import AppIntents
import UIKit

private let yyPendingLogPrefix = "🧩 [PendingScreenshot]"

/// Moly截图：截图后由主App按“App内发送链路”发送到聊天室（不走输入框预览步骤）
struct MollyScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Moly截图"
    static var description = IntentDescription("仅接收快捷指令传入的截图，并直接发送到Moly聊天室（不读取系统相册）")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "截图",
        description: "直接接收上一步“截屏/拍摄屏幕截图”的输出（不弹文件选择器）。"
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("发送截图到Moly聊天室") {
            \.$screenshot
        }
    }

    func perform() async throws -> some IntentResult {
        #if DEBUG
        func log(_ msg: String) {
            AppGroupDebugLog.append(msg)
            print("\(yyPendingLogPrefix) \(msg)")
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        log("MollyScreenshotIntent start t=\(t0)")
        #endif

        // ✅ 目标：快捷指令动作“秒过”
        // 这里不做任何解码/缩放/JPEG 重压缩，也不生成缩略图/发通知/LiveActivity；
        // 只把原始 bytes 落到 App Group 队列，随后发一个 Darwin 通知让主App去 drain。
        // 注意：IntentFile.data 可能触发系统把截图物化为 Data，存在波动。
        // 这里不要用 Task.detached 去读（某些系统版本下可能触发额外的 sandbox extension 申请路径并打日志），
        // 直接在当前执行器读取即可；我们已确保 perform() 不在 @MainActor。
        let raw: Data = screenshot.data
        guard !raw.isEmpty else {
            #if DEBUG
            log("invalid screenshot input (empty data)")
            #endif
            throw MollyScreenshotError.invalidScreenshotInput
        }

        // ⚠️ 重要：不要访问 screenshot.filename
        // 在快捷指令的运行环境里，IntentFile 可能是一个临时 file URL（WorkflowKit BackgroundShortcutRunner 的 tmp），
        // 系统需要发 sandbox extension 才能读该 URL。你日志里的：
        // `_INIssueSandboxExtensionWithTokenGeneratorBlock ... Operation not permitted`
        // 很可能就与 file URL 访问有关（包括读取 filename/metadata）。
        //
        // 我们这里完全不依赖扩展名：队列端会在 ext=nil 时用默认扩展名（.img），主App decode 仍然用 bytes 识别格式。
        let ext: String? = nil

        #if DEBUG
        let tRead = CFAbsoluteTimeGetCurrent()
        let dtRead = String(format: "%.3f", (tRead - t0))
        log("intent got data bytes=\(raw.count) dt=\(dtRead)s")
        #endif

        let pendingRelPath: String = await Task.detached(priority: .utility) {
            PendingScreenshotQueue.enqueue(rawData: raw, fileExt: ext, thumbnailRelativePath: nil) ?? ""
        }.value
        guard !pendingRelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            #if DEBUG
            log("pendingRelPath empty (cannot write App Group)")
            #endif
            throw BackendChatError.invalidConfig("无法访问 App Group 容器")
        }

        #if DEBUG
        let tWrote = CFAbsoluteTimeGetCurrent()
        let dtWrite = String(format: "%.3f", (tWrote - tRead))
        log("enqueue rel=\(pendingRelPath) (fast path) dt=\(dtWrite)s")
        #endif

        DarwinNotificationCenter.post(ChatDarwinNames.pendingScreenshot)
        #if DEBUG
        log("post darwin \(ChatDarwinNames.pendingScreenshot)")
        #endif
        #if DEBUG
        let tEnd = CFAbsoluteTimeGetCurrent()
        let dtTotal = String(format: "%.3f", (tEnd - t0))
        log("finish intent dtTotal=\(dtTotal)s")
        #endif

        return .result()
    }

    // MARK: - Helpers
}

enum MollyScreenshotError: LocalizedError {
    case invalidScreenshotInput

    var errorDescription: String? {
        switch self {
        case .invalidScreenshotInput:
            return "截图数据无效。请在快捷指令里把“截屏/拍摄屏幕截图”的输出连接到「Moly→Moly截图→截图」参数。"
        }
    }
}

// App 快捷指令提供器
struct YuanyuanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MollyScreenshotIntent(),
            phrases: [
                "\(.applicationName)Moly截图",
                "用\(.applicationName)Moly截图",
                "在\(.applicationName)Moly截图",
                // 兼容旧叫法，避免已有快捷指令短语失效
                "\(.applicationName)Molly截图",
                "用\(.applicationName)Molly截图",
                "在\(.applicationName)Molly截图"
            ],
            shortTitle: "Moly截图",
            systemImageName: "photo.on.rectangle.angled"
        )
        
        AppShortcut(
            intent: StartMeetingRecordingIntent(),
            phrases: [
                "在\(.applicationName)Moly录音",
                "用\(.applicationName)Moly录音",
                "\(.applicationName)Moly录音"
            ],
            shortTitle: "Moly录音",
            systemImageName: "mic.circle.fill"
        )
    }
}

