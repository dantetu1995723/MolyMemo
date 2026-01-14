import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct MolyMemoApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authStore = AuthStore()
    @Environment(\.scenePhase) private var scenePhase
    
    // SwiftData 容器配置
    let modelContainer: ModelContainer
    
    init() {
        // 启动期只清理临时缓存：不要清 SwiftData store（否则会抹掉 AppIntent 写入的聊天记录）
        LocalDataPurger.purgeCaches(reason: "启动清理临时缓存")

        do {
            modelContainer = try SharedModelContainer.makeContainer()
        } catch {
            fatalError("无法初始化 SwiftData 容器: \(error)")
        }

        // 方案 B：一次性把老 Yuanyuan App Group 的聊天记录迁移到新 store（仅当新 store 为空）
        // 迁移涉及 SwiftData mainContext（@MainActor），这里用主线程任务触发。
        let containerForMigration = modelContainer
        Task { @MainActor in
            YuanyuanGroupMigration.runIfNeeded(targetContainer: containerForMigration)
        }

        // 尽早安装 Darwin 录音命令监听，避免 “通知先发出、监听后注册” 的竞态
        RecordingDarwinObserver.shared.installIfNeeded()
        // 尽早安装 Darwin 聊天更新监听（快捷指令/AppIntent 后台写入聊天后，主App可即时刷新）
        ChatDarwinObserver.shared.installIfNeeded()

        // 让前台也能展示通知横幅（否则前台默认不弹）
        UNUserNotificationCenter.current().delegate = AppNotificationCenterDelegate.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authStore)
                .modelContainer(modelContainer)
                .onAppear {
                    // 不再在启动时加载聊天记录，改为在进入聊天室时懒加载
                    
                    // 立即初始化 LiveRecordingManager（会自动清理残留的Live Activity）
                    _ = LiveRecordingManager.shared

                    // 请求通知权限
                    Task {
                        _ = await CalendarManager.shared.requestNotificationPermission()
                    }
                    
                    // 进入 App 时清空红标（避免一直挂着）
                    Task {
                        await CalendarManager.shared.clearAppBadge()
                    }

                    // 前置请求通讯录权限：仅首次（notDetermined）会弹窗
                    Task { @MainActor in
                        await ContactsManager.shared.requestAccessIfNotDetermined(source: "app:onAppear")
                    }
                    
                    // App首次启动时，开始新session
                    appState.startNewSession()

                    // 兜底：如果 AppIntent 因 openAppWhenRun 启动了主App，但 Darwin 通知在监听注册前发出而丢失，
                    // 这里会主动拉取 pending command，确保“一次点击就生效”。
                    Task { @MainActor in
                        RecordingCommandProcessor.shared.processIfNeeded(source: "app:onAppear")
                    }
                }
                .onOpenURL { url in
                    handleIncomingURL(url, modelContext: modelContainer.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartRecordingFromWidget"))) { notification in
                    
                    // 新流程：快捷指令启动 -> 聊天室插入“开始录音”气泡 -> 启动录音 -> 缩回灵动岛
                    // 兼容旧字段 shouldNavigateToMeeting（旧逻辑会跳会议页）；现在统一走聊天室
                    let shouldNavigateToChatRoom = notification.userInfo?["shouldNavigateToChatRoom"] as? Bool
                        ?? true
                    let publishTranscriptionToUI = notification.userInfo?["publishTranscriptionToUI"] as? Bool ?? true

                    DispatchQueue.main.async {

                        // 尽量关闭其他可能覆盖的界面
                        appState.showSettings = false
                        appState.showLiveRecording = false

                        if shouldNavigateToChatRoom {
                            appState.showChatRoom = true
                            let userMsg = appState.addRecordingStartedUserMessage()
                            appState.saveMessageToStorage(userMsg, modelContext: modelContainer.mainContext)
                        }

                        // 启动录音
                        LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                            return modelContainer?.mainContext
                        }

                        if !LiveRecordingManager.shared.isRecording {
                            LiveRecordingManager.shared.startRecording(publishTranscriptionToUI: publishTranscriptionToUI)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopRecordingFromWidget"))) { notification in
                    
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
                        } else {
                            // 确保有ModelContext来保存
                            LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                                return modelContainer?.mainContext
                            }
                            LiveRecordingManager.shared.stopRecording(modelContext: modelContainer.mainContext)
                        }
                        
                        if !shouldNavigateToChatRoom {
                            // 其他情况：跳转到会议记录界面
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
                    
                    guard let userInfo = notification.userInfo else {
                        return
                    }
                    
                    let title = userInfo["title"] as? String ?? "Moly录音"
                    let date = userInfo["date"] as? Date ?? Date()
                    let duration = userInfo["duration"] as? TimeInterval ?? 0
                    let audioPath = userInfo["audioPath"] as? String ?? ""
                    let suppressChatCard = userInfo["suppressChatCard"] as? Bool ?? false
                    
                    
                    // 先添加一个"处理中"的卡片
                    if !suppressChatCard {
                        DispatchQueue.main.async {
                            appState.clearActiveRecordingStatus()
                            
                            let processingCard = MeetingCard(
                                title: title,
                                date: date,
                                summary: "正在生成会议记录，请稍候...",
                                duration: duration,
                                audioPath: audioPath,
                                isGenerating: true
                            )
                            let agentMsg = appState.addMeetingCardMessage(processingCard)
                            appState.saveMessageToStorage(agentMsg, modelContext: modelContainer.mainContext)
                        }
                    }
                    
                    // 异步调用后端API
                    Task {
                        // 记录 jobId：如果已创建任务但前台被系统挂起/取消，我们不应该把 UI 判成失败
                        var createdJobId: String? = nil
                        do {
                            #if canImport(UIKit)
                            // 兜底：用户按 Home/切后台时，给网络请求一点额外时间（系统通常仅给几十秒，不保证跑完长任务）
                            var bgTask: UIBackgroundTaskIdentifier = .invalid
                            bgTask = UIApplication.shared.beginBackgroundTask(withName: "meetingMinutesGenerate") {
                                if bgTask != .invalid {
                                    UIApplication.shared.endBackgroundTask(bgTask)
                                    bgTask = .invalid
                                }
                            }
                            defer {
                                if bgTask != .invalid {
                                    UIApplication.shared.endBackgroundTask(bgTask)
                                    bgTask = .invalid
                                }
                            }
                            #endif

                            guard !audioPath.isEmpty else {
                                return
                            }
                            
                            let audioURL = URL(fileURLWithPath: audioPath)
                            
                            let result = try await MeetingMinutesService.generateMeetingMinutes(
                                audioFileURL: audioURL,
                                onJobCreated: { jobId in
                                    createdJobId = jobId
                                    // 关键：尽早写入 remoteId，避免用户生成过程中退出 App 后“无法续跑/无法再轮询”
                                    if suppressChatCard {
                                        // 会议纪要列表页录音：通知列表占位卡尽早拿到 remoteId
                                        let postJobCreated = {
                                            NotificationCenter.default.post(
                                                name: NSNotification.Name("MeetingListJobCreated"),
                                                object: nil,
                                                userInfo: ["audioPath": audioPath, "remoteId": jobId]
                                            )
                                        }
                                        // NotificationCenter 的 publisher 默认在“发送线程”回调；
                                        // 为避免 SwiftUI 状态在后台更新，强制在主线程发送。
                                        if Thread.isMainThread {
                                            postJobCreated()
                                        } else {
                                            DispatchQueue.main.async {
                                                postJobCreated()
                                            }
                                        }
                                    } else {
                                        Task { @MainActor in
                                            if let lastIndex = appState.chatMessages.lastIndex(where: { $0.meetings != nil }) {
                                                if var meetings = appState.chatMessages[lastIndex].meetings,
                                                   let meetingIndex = meetings.lastIndex(where: { $0.audioPath == audioPath }) {
                                                    meetings[meetingIndex].remoteId = jobId
                                                    meetings[meetingIndex].isGenerating = true
                                                    appState.chatMessages[lastIndex].meetings = meetings
                                                    appState.saveMessageToStorage(appState.chatMessages[lastIndex], modelContext: modelContainer.mainContext)
                                                }
                                            }
                                        }
                                    }
                                }
                            )
                            
                            
                            // 更新卡片内容
                            await MainActor.run {
                                // 会议记录页录音：不更新聊天室，但仍可预下载提升首次播放体验
                                if suppressChatCard {
                                    let card = MeetingCard(
                                        remoteId: result.id,
                                        title: (result.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (result.title ?? title) : title,
                                        date: result.date ?? date,
                                        summary: result.summary,
                                        duration: result.audioDuration ?? duration,
                                        audioPath: audioPath,
                                        audioRemoteURL: result.audioUrl,
                                        transcriptions: result.transcriptions,
                                        isGenerating: false
                                    )
                                    RecordingPlaybackController.shared.prefetch(meeting: card)
                                    // 通知会议列表：把“生成中”小卡片立刻更新成正常卡片（无需等刷新）
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("MeetingListDidComplete"),
                                        object: nil,
                                        userInfo: [
                                            "audioPath": audioPath,
                                            "remoteId": result.id,
                                            "title": card.title,
                                            "date": card.date,
                                            "duration": card.duration ?? (result.audioDuration ?? duration),
                                            "summary": card.summary
                                        ]
                                    )
                                    return
                                }
                                
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
                                        if let d = result.audioDuration {
                                            meetings[meetingIndex].duration = d
                                        } else {
                                        }
                                        // 🔍 调试：写入 audio_url，确保卡片可直接播放/可预下载
                                        if let u = result.audioUrl, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            meetings[meetingIndex].audioRemoteURL = u
                                        } else {
                                        }
                                        meetings[meetingIndex].isGenerating = false
                                        appState.chatMessages[lastIndex].meetings = meetings
                                        // 同步更新“AI气泡文案”：从生成中 -> 生成完成（与 demo 一致）
                                        appState.chatMessages[lastIndex].content = "已为您创建了一份会议记录文件，长按可调整。"
                                        appState.saveMessageToStorage(appState.chatMessages[lastIndex], modelContext: modelContainer.mainContext)

                                        // 一口气完成：生成完成后立刻预下载（不播放）
                                        let updated = meetings[meetingIndex]
                                        RecordingPlaybackController.shared.prefetch(meeting: updated)
                                    }
                                }
                            }
                            
                        } catch {
                            
                            // 更新卡片显示错误
                            await MainActor.run {
                                // ✅ 关键修复：
                                // 用户在生成过程中切到后台，系统可能会挂起/取消当前进程里的网络任务，
                                // 但后端任务仍会继续跑。此时如果把 UI 直接判成失败，用户会被误导。
                                func isLikelyBackgroundInterruption(_ e: Error) -> Bool {
                                    if e is CancellationError { return true }
                                    if let url = e as? URLError, url.code == .cancelled { return true }
                                    let ns = e as NSError
                                    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
                                    // 兜底：某些系统/库会把取消写进文案
                                    let msg = e.localizedDescription.lowercased()
                                    if msg.contains("cancel") || msg.contains("取消") { return true }
                                    return false
                                }
                                
                                let jid = (createdJobId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                let hasJob = !jid.isEmpty
                                let shouldKeepGenerating = hasJob && isLikelyBackgroundInterruption(error)
                                
                                if suppressChatCard {
                                    // 会议列表占位卡：如果已创建 job 且像是后台中断，就不要判失败（避免误导）
                                    if shouldKeepGenerating {
                                        #if DEBUG
                                        AppGroupDebugLog.append("[MeetingMinutes][bg] suppressChatCard interrupted. keep generating. jobId=\(jid) err=\(error.localizedDescription)")
                                        #endif
                                    } else {
                                        // 会议列表占位卡：生成失败后维持条目，用户可手动删除/刷新
                                        NotificationCenter.default.post(
                                            name: NSNotification.Name("MeetingListDidComplete"),
                                            object: nil,
                                            userInfo: [
                                                "audioPath": audioPath,
                                                "title": "生成失败",
                                                "summary": "⚠️ 会议记录生成失败: \(error.localizedDescription)"
                                            ]
                                        )
                                    }
                                    return
                                }
                                if let lastIndex = appState.chatMessages.lastIndex(where: { $0.meetings != nil }) {
                                    if var meetings = appState.chatMessages[lastIndex].meetings,
                                       let meetingIndex = meetings.lastIndex(where: { $0.audioPath == audioPath }) {
                                        if shouldKeepGenerating {
                                            // 有 jobId：说明后端任务已经开始跑。保持生成中，并提示“回到前台会自动继续刷新”。
                                            if meetings[meetingIndex].remoteId == nil { meetings[meetingIndex].remoteId = jid }
                                            meetings[meetingIndex].isGenerating = true
                                            meetings[meetingIndex].summary = "正在生成会议记录（应用在后台时可能暂停刷新，回到前台会自动继续）。"
                                            // 文案也不要写失败
                                            appState.chatMessages[lastIndex].content = "正在生成会议记录，请稍候..."
                                        } else {
                                            meetings[meetingIndex].summary = "⚠️ 会议记录生成失败: \(error.localizedDescription)"
                                            meetings[meetingIndex].isGenerating = false
                                            // 同步更新“AI气泡文案”：提示失败，避免仍显示“正在生成”
                                            appState.chatMessages[lastIndex].content = "会议记录生成失败，请稍后重试。"
                                        }
                                        appState.chatMessages[lastIndex].meetings = meetings
                                        appState.saveMessageToStorage(appState.chatMessages[lastIndex], modelContext: modelContainer.mainContext)
                                    }
                                }
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecordingDidComplete"))) { notification in
                    
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
                    }
                }
                .task {
                    // 监听AppIntent的执行（从Widget或快捷指令触发）
                    // 如果检测到录音Intent被触发，直接启动Live Activity
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

            // 兜底：从后台/被系统唤起时，主动处理一次 pending command（带时间戳去重）。
            Task { @MainActor in
                RecordingCommandProcessor.shared.processIfNeeded(source: "app:scenePhase.active")
            }
            
            // 如果是从后台返回（不是首次启动），开始新session
            if oldPhase == .background {
                appState.startNewSession()
            }

            // ✅ 进程恢复：从后台回来时，自动把“生成中/曾经误判失败”的会议卡片再拉一次详情自愈
            Task { @MainActor in
                await refreshRecentMeetingCardsIfNeeded()
            }
            
        case .inactive:
            // App即将进入后台（过渡状态）
            break
            
        case .background:
            // App进入后台
            // ✅ 链路简化：不在后台额外发起 “summary” 请求（避免多余请求/工具链干扰聊天体验）
            break
            
        @unknown default:
            break
        }
    }

    /// 前台恢复后，尝试刷新最近的“会议记录生成中/生成失败(但其实后端已完成)”卡片。
    @MainActor
    private func refreshRecentMeetingCardsIfNeeded() async {
        // 只扫最近 N 条，避免全量遍历
        let maxScanMessages = 30
        let msgs = Array(appState.chatMessages.suffix(maxScanMessages))
        guard !msgs.isEmpty else { return }
        
        // 找到“最后一张”需要恢复的会议卡片（优先最新）
        var target: (msgIndex: Int, meetingIndex: Int, rid: String)? = nil
        for (i, msg) in msgs.enumerated().reversed() {
            guard let meetings = msg.meetings, !meetings.isEmpty else { continue }
            for (j, m) in meetings.enumerated().reversed() {
                let rid = (m.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rid.isEmpty else { continue }
                let sum = m.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let looksFailedOrTimeout = sum.contains("生成失败") || sum.contains("超时") || sum.contains("等待会议记录生成超时")
                if m.isGenerating || looksFailedOrTimeout || sum.isEmpty {
                    // 转回到 appState.chatMessages 的真实索引
                    let msgIndex = appState.chatMessages.count - msgs.count + i
                    target = (msgIndex: msgIndex, meetingIndex: j, rid: rid)
                    break
                }
            }
            if target != nil { break }
        }
        guard let t = target else { return }

        #if DEBUG
        AppGroupDebugLog.append("[MeetingMinutes][resume] try refresh rid=\(t.rid)")
        #endif
        
        do {
            let item = try await MeetingMinutesService.getMeetingMinutesDetail(id: t.rid)
            let newTitle = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let newSummary = (item.summary ?? item.meetingSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasDetails = (item.meetingDetails?.isEmpty == false) || (item.transcriptions?.isEmpty == false)
            
            // 没拿到任何内容就不硬改，避免把“生成中”变成空白
            guard !newTitle.isEmpty || !newSummary.isEmpty || hasDetails else { return }
            guard t.msgIndex < appState.chatMessages.count else { return }
            guard var meetings = appState.chatMessages[t.msgIndex].meetings, t.meetingIndex < meetings.count else { return }
            
            if !newTitle.isEmpty { meetings[t.meetingIndex].title = newTitle }
            if !newSummary.isEmpty { meetings[t.meetingIndex].summary = newSummary }
            if let d = item.audioDuration { meetings[t.meetingIndex].duration = d }
            if let u = item.audioUrl, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meetings[t.meetingIndex].audioRemoteURL = u
            }
            if let details = item.meetingDetails, !details.isEmpty {
                meetings[t.meetingIndex].transcriptions = details.compactMap { d in
                    guard let text = d.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let speaker = (d.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? d.speakerName!
                        : ("说话人" + (d.speakerId ?? ""))
                    let time = formatHMS(d.startTime ?? 0)
                    return MeetingTranscription(speaker: speaker, time: time, content: text, startTime: d.startTime, endTime: d.endTime)
                }
            } else if let ts = item.transcriptions, !ts.isEmpty {
                meetings[t.meetingIndex].transcriptions = ts.compactMap { tr in
                    guard let content = tr.content, !content.isEmpty else { return nil }
                    return MeetingTranscription(
                        speaker: tr.speaker ?? "说话人",
                        time: tr.time ?? "00:00:00",
                        content: content,
                        startTime: parseHMSSeconds(tr.time ?? "")
                    )
                }
            }
            
            // 如果已经拿到 summary 或 details，就收敛为完成态
            meetings[t.meetingIndex].isGenerating = false
            appState.chatMessages[t.msgIndex].meetings = meetings
            appState.chatMessages[t.msgIndex].content = "已为您创建了一份会议记录文件，长按可调整。"
            appState.saveMessageToStorage(appState.chatMessages[t.msgIndex], modelContext: modelContainer.mainContext)
            
            // 预下载（不播放）
            RecordingPlaybackController.shared.prefetch(meeting: meetings[t.meetingIndex])
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("[MeetingMinutes][resume] refresh failed rid=\(t.rid) err=\(error.localizedDescription)")
            #endif
        }
    }
    
    private func formatHMS(_ time: TimeInterval) -> String {
        let total = Int(time.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func parseHMSSeconds(_ raw: String) -> TimeInterval? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ":").map { String($0) }
        if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let sec = Double(parts[2]) ?? 0
            return max(0, h * 3600 + m * 60 + sec)
        }
        if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let sec = Double(parts[1]) ?? 0
            return max(0, m * 60 + sec)
        }
        if let v = Double(s) { return max(0, v) }
        return nil
    }
    
    // 处理URL scheme
    private func handleIncomingURL(_ url: URL, modelContext: ModelContext) {
        // 检查是否是 molymemo://
        guard url.scheme == AppIdentifiers.urlScheme else { return }
        
        
        if url.host == "screenshot" || url.path == "/screenshot" {
            // 从剪贴板获取截图并打开聊天室
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.handleScreenshotFromClipboard()
            }
        } else if url.host == "chat" || url.path == "/chat" {
            DispatchQueue.main.async {
                appState.showSettings = false
                appState.showTodoList = false
                appState.showContactList = false
                appState.showExpenseList = false
                appState.showLiveRecording = false
                appState.showMeetingList = false
                appState.showChatRoom = true
            }
        } else if url.host == "start-recording-widget" || url.path == "/start-recording-widget" {
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
            }
        } else if url.host == "start-recording" || url.path == "/start-recording" {
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
            LiveRecordingManager.shared.pauseRecording()
        } else if url.host == "resume-recording" || url.path == "/resume-recording" {
            LiveRecordingManager.shared.resumeRecording()
        } else if url.host == "stop-recording" || url.path == "/stop-recording" {
            LiveRecordingManager.shared.stopRecording(modelContext: modelContext)
        } else if url.host == "meeting-recording" || url.path == "/meeting-recording" {
            // 关闭其他界面，打开会议记录界面
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
                }
            }
        }
    }
}
