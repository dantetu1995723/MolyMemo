import AppIntents
import SwiftUI
import UIKit

// 截图分析意图
struct ScreenshotAnalysisIntent: AppIntent {
    static var title: LocalizedStringResource = "截图分析"
    static var description = IntentDescription("快速将截图发送给AI小助手分析")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        print("🎯 截图分析 Intent 被触发")

        // 🆕 改用相册获取最近一张照片（避免剪贴板权限弹窗）
        var category: ScreenshotCategory? = nil

        #if os(iOS)
        // 延迟1秒，确保截图已保存到相册
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // 从相册获取最近一张照片
        if let image = await PhotoManager.shared.fetchLatestPhoto() {
            print("📸 成功从相册获取最近一张照片，开始快速分类...")

            do {
                // 快速分类
                let result = try await ScreenshotClassifier.classifyScreenshot(image: image)
                category = result.category
                print("✅ 快速分类完成: \(category?.rawValue ?? "未知"), 置信度: \(String(format: "%.2f", result.confidence))")
            } catch {
                print("⚠️ 快速分类失败: \(error)，将在聊天室中进行完整分析")
                category = nil
            }
        } else {
            print("⚠️ 无法从相册获取照片")
        }
        #endif

        // 通知 App 处理截图，并传递分类结果
        NotificationCenter.default.post(
            name: NSNotification.Name("TriggerScreenshotAnalysis"),
            object: category
        )

        return .result()
    }
}

// App 快捷指令提供器
struct YuanyuanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScreenshotAnalysisIntent(),
            phrases: [
                "\(.applicationName)截图分析",
                "在\(.applicationName)发送截图",
                "用\(.applicationName)分析截图"
            ],
            shortTitle: "截图分析",
            systemImageName: "photo.on.rectangle.angled"
        )

        AppShortcut(
            intent: SendLatestScreenshotToChatIntent(),
            phrases: [
                "\(.applicationName)发送最新截图",
                "用\(.applicationName)把截图发到聊天室",
                "\(.applicationName)截图后发送到聊天室"
            ],
            shortTitle: "截图发送",
            systemImageName: "paperplane.fill"
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

