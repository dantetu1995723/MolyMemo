import SwiftUI
import SwiftData
import UIKit

@main
struct YuanyuanApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authStore = AuthStore()
    @Environment(\.scenePhase) private var scenePhase
    
    // SwiftData 容器配置
    let modelContainer: ModelContainer
    
    init() {
        do {
            // 尝试正常初始化
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            modelContainer = try ModelContainer(
                for: PersistentChatMessage.self, DailyChatSummary.self, TodoItem.self, Contact.self, Expense.self, CompanyInfo.self, Meeting.self,
                configurations: configuration
            )
            print("✅ SwiftData 容器初始化成功")
        } catch {
            print("❌ 容器初始化失败，尝试删除旧数据库重建: \(error)")
            
            // 如果初始化失败（通常是模型变化导致），删除旧数据库
            do {
                // 获取默认存储URL
                if let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("default.store") {
                    try? FileManager.default.removeItem(at: storeURL)
                    print("🗑️ 已删除旧数据库")
                }
                
                // 重新创建容器
                let configuration = ModelConfiguration(
                    isStoredInMemoryOnly: false,
                    allowsSave: true
                )
                modelContainer = try ModelContainer(
                    for: PersistentChatMessage.self, DailyChatSummary.self, TodoItem.self, Contact.self, Expense.self, CompanyInfo.self, Meeting.self,
                    configurations: configuration
                )
                print("✅ 重建容器成功")
            } catch {
                print("❌ 重建容器失败: \(error)")
                fatalError("无法初始化 SwiftData 容器: \(error)")
            }
        }

        // 尽早安装 Darwin 录音命令监听，避免 “通知先发出、监听后注册” 的竞态
        RecordingDarwinObserver.shared.installIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authStore)
                .modelContainer(modelContainer)
                .onAppear {
                    print("🚀 ContentView onAppear - App 启动")
                    // 不再在启动时加载聊天记录，改为在进入聊天室时懒加载
                    
                    // 立即初始化 LiveRecordingManager（会自动清理残留的Live Activity）
                    _ = LiveRecordingManager.shared
                    print("✅ LiveRecordingManager 已初始化，残留Activity已清理")

                    // 请求通知权限
                    Task {
                        _ = await CalendarManager.shared.requestNotificationPermission()
                    }
                    
                    // App首次启动时，开始新session
                    appState.startNewSession()

                    // 兜底：如果 AppIntent 因 openAppWhenRun 启动了主App，但 Darwin 通知在监听注册前发出而丢失，
                    // 这里会主动拉取 pending command，确保“一次点击就生效”。
                    Task { @MainActor in
                        RecordingCommandProcessor.shared.processIfNeeded(source: "app:onAppear")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerScreenshotAnalysis"))) { notification in
                    print("🎯 收到截图分析触发通知")

                    // 获取预分类结果
                    let category = notification.object as? ScreenshotCategory
                    if let category = category {
                        print("📊 收到预分类结果: \(category.rawValue)")
                    }

                    // 延迟执行，确保 App 完全启动
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("📲 开始执行 handleScreenshotFromClipboard")
                        appState.handleScreenshotFromClipboard(category: category)
                    }
                }
                .onOpenURL { url in
                    print("📱 收到URL: \(url)")
                    handleIncomingURL(url, modelContext: modelContainer.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartRecordingFromWidget"))) { notification in
                    print("🎤 收到快捷指令录音触发通知")
                    
                    // 新流程：快捷指令启动 -> 聊天室插入“开始录音”气泡 -> 启动录音 -> 缩回灵动岛
                    // 兼容旧字段 shouldNavigateToMeeting（旧逻辑会跳会议页）；现在统一走聊天室
                    let shouldNavigateToChatRoom = notification.userInfo?["shouldNavigateToChatRoom"] as? Bool
                        ?? true
                    let autoMinimize = notification.userInfo?["autoMinimize"] as? Bool ?? true
                    let publishTranscriptionToUI = notification.userInfo?["publishTranscriptionToUI"] as? Bool ?? true

                    DispatchQueue.main.async {
                        print("🚀 快捷指令启动录音（聊天室模式） shouldNavigateToChatRoom=\(shouldNavigateToChatRoom) autoMinimize=\(autoMinimize) publishTranscriptionToUI=\(publishTranscriptionToUI)")

                        // 尽量关闭其他可能覆盖的界面
                        appState.showSettings = false
                        appState.showLiveRecording = false

                        if shouldNavigateToChatRoom {
                            appState.showChatRoom = true
                            let userMsg = appState.addRecordingStartedUserMessage()
                            appState.saveMessageToStorage(userMsg, modelContext: modelContainer.mainContext)
                            print("💬 已插入动态录音气泡")
                        }

                        // 启动录音
                        LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                            return modelContainer?.mainContext
                        }

                        if !LiveRecordingManager.shared.isRecording {
                            LiveRecordingManager.shared.startRecording(publishTranscriptionToUI: publishTranscriptionToUI)
                            print("✅ 录音已启动")
                        }

                        // 等待气泡渲染并稳定后，再自动挂后台（延长到1.5秒，确保用户看清气泡）
                        if autoMinimize {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if LiveRecordingManager.shared.isRecording {
                                    print("🏝️ 录音气泡已就绪，自动挂起App")
                                    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
                                }
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopRecordingFromWidget"))) { notification in
                    print("🛑 收到Widget停止录音通知 - 保存到会议纪要")
                    
                    let shouldNavigateToChatRoom = notification.userInfo?["shouldNavigateToChatRoom"] as? Bool ?? false
                    
                    DispatchQueue.main.async {
                        // 如果来自灵动岛“完成”，先立刻切到聊天室并给用户一个“已收到”的气泡反馈，
                        // 让用户明确知道系统在生成卡片（同时也避免 ChatView 首次空消息时插入 demo 卡片）。
                        if shouldNavigateToChatRoom {
                            appState.showSettings = false
                            appState.showTodoList = false
                            appState.showContactList = false
                            appState.showExpenseList = false
                            appState.showLiveRecording = false
                            appState.showMeetingList = false
                            appState.showChatRoom = true
                            
                            // 使用统一的停止流程
                            appState.stopRecordingAndShowGenerating(modelContext: modelContainer.mainContext)
                            print("🛑 已执行统一停止录音流程")
                        } else {
                            // 确保有ModelContext来保存
                            LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                                return modelContainer?.mainContext
                            }
                            LiveRecordingManager.shared.stopRecording(modelContext: modelContainer.mainContext)
                            print("✅ 录音已停止并保存（不跳转聊天室）")
                        }
                        
                        if !shouldNavigateToChatRoom {
                            // 其他情况：跳转到会议纪要界面
                            appState.showChatRoom = false
                            appState.showSettings = false
                            appState.showTodoList = false
                            appState.showContactList = false
                            appState.showExpenseList = false
                            appState.showLiveRecording = false
                            appState.showMeetingList = true
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecordingNeedsUpload"))) { notification in
                    print("📤 ========== 收到录音上传请求 ==========")
                    
                    guard let userInfo = notification.userInfo else {
                        print("❌ userInfo为空")
                        return
                    }
                    
                    let title = userInfo["title"] as? String ?? "Moly录音"
                    let date = userInfo["date"] as? Date ?? Date()
                    let duration = userInfo["duration"] as? TimeInterval ?? 0
                    let audioPath = userInfo["audioPath"] as? String ?? ""
                    
                    print("📤 [YuanyuanApp] 标题: \(title)")
                    print("📤 [YuanyuanApp] 音频路径: \(audioPath)")
                    print("📤 [YuanyuanApp] 时长: \(duration)秒")
                    
                    // 先添加一个"处理中"的卡片
                    DispatchQueue.main.async {
                        appState.clearActiveRecordingStatus()
                        
                        let processingCard = MeetingCard(
                            title: title,
                            date: date,
                            summary: "正在生成会议纪要，请稍候...",
                            duration: duration,
                            audioPath: audioPath,
                            isGenerating: true
                        )
                        let agentMsg = appState.addMeetingCardMessage(processingCard)
                        appState.saveMessageToStorage(agentMsg, modelContext: modelContainer.mainContext)
                        print("📤 [YuanyuanApp] 已添加处理中卡片")
                    }
                    
                    // 异步调用后端API
                    Task {
                        do {
                            guard !audioPath.isEmpty else {
                                print("❌ [YuanyuanApp] 音频路径为空")
                                return
                            }
                            
                            let audioURL = URL(fileURLWithPath: audioPath)
                            print("📤 [YuanyuanApp] 开始调用后端API...")
                            
                            let result = try await MeetingMinutesService.generateMeetingMinutes(
                                audioFileURL: audioURL
                            )
                            
                            print("✅ [YuanyuanApp] 后端返回成功!")
                            print("✅ [YuanyuanApp] 摘要长度: \(result.summary.count)")
                            
                            // 更新卡片内容
                            await MainActor.run {
                                // 找到最后一条会议卡片消息并更新
                                if let lastIndex = appState.chatMessages.lastIndex(where: { $0.meetings != nil }) {
                                    if var meetings = appState.chatMessages[lastIndex].meetings,
                                       let meetingIndex = meetings.lastIndex(where: { $0.audioPath == audioPath }) {
                                        if let newTitle = result.title, !newTitle.isEmpty {
                                            meetings[meetingIndex].title = newTitle
                                        }
                                        if let newDate = result.date {
                                            meetings[meetingIndex].date = newDate
                                        }
                                        meetings[meetingIndex].remoteId = result.id
                                        meetings[meetingIndex].summary = result.summary
                                        meetings[meetingIndex].transcriptions = result.transcriptions
                                        // 🔍 调试：只用后端 audio_duration 更新卡片时长
                                        print("🔍 [YuanyuanApp] 生成完成返回 audio_duration=\(String(describing: result.audioDuration))")
                                        if let d = result.audioDuration {
                                            meetings[meetingIndex].duration = d
                                            print("🔍 [YuanyuanApp] 已写入 meetings[\(meetingIndex)].duration=\(d)")
                                        } else {
                                            print("⚠️ [YuanyuanApp] result.audioDuration=nil，本次不更新卡片时长")
                                        }
                                        // 🔍 调试：写入 audio_url，确保卡片可直接播放/可预下载
                                        print("🔍 [YuanyuanApp] 生成完成返回 audio_url=\(String(describing: result.audioUrl))")
                                        if let u = result.audioUrl, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            meetings[meetingIndex].audioRemoteURL = u
                                            print("🔍 [YuanyuanApp] 已写入 meetings[\(meetingIndex)].audioRemoteURL=\(u)")
                                        } else {
                                            print("⚠️ [YuanyuanApp] result.audioUrl=nil，本次不更新 audioRemoteURL")
                                        }
                                        meetings[meetingIndex].isGenerating = false
                                        appState.chatMessages[lastIndex].meetings = meetings
                                        appState.saveMessageToStorage(appState.chatMessages[lastIndex], modelContext: modelContainer.mainContext)
                                        print("✅ [YuanyuanApp] 会议卡片已更新")

                                        // 一口气完成：生成完成后立刻预下载（不播放）
                                        let updated = meetings[meetingIndex]
                                        RecordingPlaybackController.shared.prefetch(meeting: updated)
                                    }
                                }
                            }
                            
                        } catch {
                            print("❌ ========== 后端上传失败 ==========")
                            print("❌ [YuanyuanApp] 错误: \(error)")
                            
                            // 更新卡片显示错误
                            await MainActor.run {
                                if let lastIndex = appState.chatMessages.lastIndex(where: { $0.meetings != nil }) {
                                    if var meetings = appState.chatMessages[lastIndex].meetings,
                                       let meetingIndex = meetings.lastIndex(where: { $0.audioPath == audioPath }) {
                                        meetings[meetingIndex].summary = "⚠️ 会议纪要生成失败: \(error.localizedDescription)"
                                        meetings[meetingIndex].isGenerating = false
                                        appState.chatMessages[lastIndex].meetings = meetings
                                        appState.saveMessageToStorage(appState.chatMessages[lastIndex], modelContext: modelContainer.mainContext)
                                        print("❌ [YuanyuanApp] 已更新错误状态")
                                    }
                                }
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecordingDidComplete"))) { notification in
                    print("🎙️ 收到录音完成通知 - 生成聊天卡片")
                    
                    guard let userInfo = notification.userInfo else { return }
                    
                    let title = userInfo["title"] as? String ?? "Moly录音"
                    let date = userInfo["date"] as? Date ?? Date()
                    let summary = userInfo["summary"] as? String ?? ""
                    let duration = userInfo["duration"] as? TimeInterval
                    let audioPath = userInfo["audioPath"] as? String
                    
                    DispatchQueue.main.async {
                        // 清理活动录音状态（如果还没清理）
                        appState.clearActiveRecordingStatus()
                        
                        // 创建会议卡片
                        let meetingCard = MeetingCard(
                            title: title,
                            date: date,
                            summary: summary,
                            duration: duration,
                            audioPath: audioPath
                        )
                        
                        // 添加到聊天消息
                        let agentMsg = appState.addMeetingCardMessage(meetingCard)
                        appState.saveMessageToStorage(agentMsg, modelContext: modelContainer.mainContext)
                        print("✅ 会议卡片已添加到聊天室")
                    }
                }
                .task {
                    // 监听AppIntent的执行（从Widget或快捷指令触发）
                    // 如果检测到录音Intent被触发，直接启动Live Activity
                    print("📱 App启动，检查是否有待处理的Intent")
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }
    
    // MARK: - App生命周期处理
    
    /// 处理场景阶段变化
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App进入前台
            print("🌅 App进入前台")

            // 兜底：从后台/被系统唤起时，主动处理一次 pending command（带时间戳去重）。
            Task { @MainActor in
                RecordingCommandProcessor.shared.processIfNeeded(source: "app:scenePhase.active")
            }
            
            // 如果是从后台返回（不是首次启动），开始新session
            if oldPhase == .background {
                appState.startNewSession()
            }
            
        case .inactive:
            // App即将进入后台（过渡状态）
            print("🌙 App进入inactive状态")
            
        case .background:
            // App进入后台
            print("💤 App进入后台")
            
            // 生成当前session的聊天总结
            appState.generateSessionSummary(modelContext: modelContainer.mainContext)
            
        @unknown default:
            break
        }
    }
    
    // 处理URL scheme
    private func handleIncomingURL(_ url: URL, modelContext: ModelContext) {
        // 检查是否是yuanyuan://
        guard url.scheme == "yuanyuan" else { return }
        
        print("📱 处理URL: \(url.absoluteString)")
        
        if url.host == "screenshot" || url.path == "/screenshot" {
            print("📸 触发截图分享")
            // 从剪贴板获取截图并打开聊天室
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.handleScreenshotFromClipboard()
            }
        } else if url.host == "start-recording-widget" || url.path == "/start-recording-widget" {
            print("🎤 Widget触发录音（聊天室模式）")
            DispatchQueue.main.async {
                appState.showSettings = false
                appState.showLiveRecording = false
                appState.showChatRoom = true

                let userMsg = appState.addRecordingStartedUserMessage()
                appState.saveMessageToStorage(userMsg, modelContext: modelContainer.mainContext)

                LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                    return modelContainer?.mainContext
                }
                if !LiveRecordingManager.shared.isRecording {
                    // Widget/快捷指令触发：默认不向 UI 发布实时转写
                    LiveRecordingManager.shared.startRecording(publishTranscriptionToUI: false)
                }

                // URL 触发默认也缩回灵动岛，保持一致体验
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if LiveRecordingManager.shared.isRecording {
                        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
                    }
                }
            }
        } else if url.host == "start-recording" || url.path == "/start-recording" {
            print("🎤 触发录音（聊天室模式）")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                appState.showSettings = false
                appState.showLiveRecording = false
                appState.showChatRoom = true

                let userMsg = appState.addRecordingStartedUserMessage()
                appState.saveMessageToStorage(userMsg, modelContext: modelContainer.mainContext)

                LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                    return modelContainer?.mainContext
                }
                if !LiveRecordingManager.shared.isRecording {
                    // URL 触发录音：默认不向 UI 发布实时转写（与 Widget/快捷指令保持一致）
                    LiveRecordingManager.shared.startRecording(publishTranscriptionToUI: false)
                }
            }
        } else if url.host == "pause-recording" || url.path == "/pause-recording" {
            print("⏸️ 暂停录音")
            LiveRecordingManager.shared.pauseRecording()
        } else if url.host == "resume-recording" || url.path == "/resume-recording" {
            print("▶️ 继续录音")
            LiveRecordingManager.shared.resumeRecording()
        } else if url.host == "stop-recording" || url.path == "/stop-recording" {
            print("🛑 停止录音")
            LiveRecordingManager.shared.stopRecording(modelContext: modelContext)
        } else if url.host == "meeting-recording" || url.path == "/meeting-recording" {
            print("📝 跳转到会议纪要界面")
            // 关闭其他界面，打开会议纪要界面
            DispatchQueue.main.async {
                // 确保导航到会议界面
                appState.showChatRoom = false
                appState.showSettings = false
                appState.showTodoList = false
                appState.showContactList = false
                appState.showExpenseList = false
                appState.showLiveRecording = false
                
                // 延迟一下确保界面已加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.showMeetingList = true
                    print("✅ 已触发跳转到会议界面")
                }
            }
        }
    }
}
