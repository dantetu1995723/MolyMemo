import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct MolyMemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var authStore = AuthStore()
    @Environment(\.scenePhase) private var scenePhase
    
    // SwiftData 容器配置
    let modelContainer: ModelContainer
    
    init() {
        // 强制 App 语言为简体中文（影响系统编辑菜单：粘贴/选择/自动填充等胶囊文案）
        // 说明：这是通过 AppleLanguages/AppleLocale 指定 App 语言环境；若你希望跟随系统语言，删掉这一段即可。
        Self.enforceSimplifiedChineseLanguage()

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

    private static func enforceSimplifiedChineseLanguage() {
        let defaults = UserDefaults.standard
        let desiredLanguages = ["zh-Hans"]

        if let current = defaults.array(forKey: "AppleLanguages") as? [String],
           current.first == desiredLanguages.first {
            return
        }

        defaults.set(desiredLanguages, forKey: "AppleLanguages")
        defaults.set("zh_CN", forKey: "AppleLocale")
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
                    let autoMinimize = notification.userInfo?["autoMinimize"] as? Bool ?? false
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
                            // 快捷指令/Widget：与工具箱一致——默认生成聊天室卡片；会议列表占位由“会议页内发起”控制
                            LiveRecordingManager.shared.startRecording(publishTranscriptionToUI: publishTranscriptionToUI, uploadToChat: true, updateMeetingList: false)
                        }

                        // ✅ 快捷指令体验：启动后自动缩回灵动岛/回到桌面
                        // 放一点点延迟，确保录音与 Live Activity 已经起来（否则会出现“没显示灵动岛”错觉）
                        if autoMinimize {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                                AppMinimizer.minimizeToHomeIfPossible()
                            }
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
                    // 统一：本地路径标准化，避免 fileURL / path / 相对路径导致“找不到生成中卡片”而一直 loading
                    func normalizeLocalAudioPath(_ raw: String) -> String {
                        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !s.isEmpty else { return "" }
                        if let u = URL(string: s), u.isFileURL {
                            return u.standardizedFileURL.path
                        }
                        return URL(fileURLWithPath: s).standardizedFileURL.path
                    }
                    let audioPath = normalizeLocalAudioPath(userInfo["audioPath"] as? String ?? "")
                    // 新字段：更清晰的去向控制（优先）
                    let uploadToChat = userInfo["uploadToChat"] as? Bool
                        ?? ((userInfo["suppressChatCard"] as? Bool).map { !$0 } ?? true)
                    let updateMeetingList = userInfo["updateMeetingList"] as? Bool
                        ?? (userInfo["suppressChatCard"] as? Bool ?? false)
                    
                    @MainActor
                    func updateMeetingCardInChat(
                        audioPath: String,
                        remoteIdCandidates: [String],
                        messageContent: String? = nil,
                        _ mutate: (inout MeetingCard) -> Void
                    ) -> Bool {
                        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                        let ridSet = Set(remoteIdCandidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                        let ap = audioPath.trimmingCharacters(in: .whitespacesAndNewlines)

                        func normalized(_ raw: String?) -> String {
                            let s = trimmed(raw)
                            guard !s.isEmpty else { return "" }
                            if let u = URL(string: s), u.isFileURL { return u.standardizedFileURL.path }
                            return URL(fileURLWithPath: s).standardizedFileURL.path
                        }
                        let apNorm = normalized(ap)

                        func isMatch(_ card: MeetingCard) -> Bool {
                            let rid = trimmed(card.remoteId)
                            if !rid.isEmpty, ridSet.contains(rid) { return true }
                            let cap = normalized(card.audioPath)
                            if !apNorm.isEmpty, !cap.isEmpty, cap == apNorm { return true }
                            return false
                        }

                        for msgIndex in appState.chatMessages.indices.reversed() {
                            var msg = appState.chatMessages[msgIndex]
                            var changed = false

                            // 1) 聚合字段 meetings
                            if var meetings = msg.meetings, !meetings.isEmpty {
                                for i in meetings.indices.reversed() {
                                    if isMatch(meetings[i]) {
                                        mutate(&meetings[i])
                                        msg.meetings = meetings
                                        changed = true
                                        break
                                    }
                                }
                            }

                            // 2) 分段字段 segments（meetingCards 段）
                            if !changed, var segs = msg.segments, !segs.isEmpty {
                                outer: for s in segs.indices {
                                    guard segs[s].kind == .meetingCards, var cards = segs[s].meetings, !cards.isEmpty else { continue }
                                    for i in cards.indices.reversed() {
                                        if isMatch(cards[i]) {
                                            mutate(&cards[i])
                                            segs[s].meetings = cards
                                            msg.segments = segs
                                            changed = true
                                            break outer
                                        }
                                    }
                                }
                            }

                            if changed {
                                if let c = messageContent {
                                    msg.content = c
                                }
                                appState.chatMessages[msgIndex] = msg
                                appState.saveMessageToStorage(msg, modelContext: modelContainer.mainContext)
                                return true
                            }
                        }
                        return false
                    }

                    
                    // 先添加一个"处理中"的卡片
                    if uploadToChat {
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

                            // 即使音频文件缺失，也要给出明确结果（而不是静默不生成）
                            guard !audioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                await MainActor.run {
                                    if updateMeetingList {
                                        NotificationCenter.default.post(
                                            name: NSNotification.Name("MeetingListDidComplete"),
                                            object: nil,
                                            userInfo: [
                                                "audioPath": audioPath,
                                                "title": "生成失败",
                                                "summary": "⚠️ 录音文件缺失，无法生成会议记录。"
                                            ]
                                        )
                                        return
                                    }
                                    
                                    if uploadToChat {
                                        let didUpdate = updateMeetingCardInChat(
                                            audioPath: audioPath,
                                            remoteIdCandidates: [],
                                            messageContent: "会议记录生成失败，请稍后重试。"
                                        ) { card in
                                            card.summary = "⚠️ 录音文件缺失，无法生成会议记录。"
                                            card.isGenerating = false
                                        }
                                        if !didUpdate {
                                            // 没找到对应生成中卡片：补插失败态卡片
                                            let fail = MeetingCard(
                                                title: title,
                                                date: date,
                                                summary: "⚠️ 录音文件缺失，无法生成会议记录。",
                                                duration: duration,
                                                audioPath: audioPath,
                                                isGenerating: false
                                            )
                                            let msg = appState.addMeetingCardMessage(fail)
                                            appState.saveMessageToStorage(msg, modelContext: modelContainer.mainContext)
                                        }
                                    }
                                }
                                return
                            }
                            
                            let audioURL = URL(fileURLWithPath: audioPath)
                            
                            let result = try await MeetingMinutesService.generateMeetingMinutes(
                                audioFileURL: audioURL,
                                onJobCreated: { jobId in
                                    createdJobId = jobId
                                    // 关键：尽早写入 remoteId，避免用户生成过程中退出 App 后“无法续跑/无法再轮询”
                                    if updateMeetingList {
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
                                    }
                                    // ✅ 无论是否更新会议列表，只要聊天室要生成卡片，就应尽早写回 remoteId
                                    guard uploadToChat else { return }
                                    Task { @MainActor in
                                        _ = updateMeetingCardInChat(
                                            audioPath: audioPath,
                                            remoteIdCandidates: [jobId]
                                        ) { card in
                                            card.remoteId = jobId
                                            card.isGenerating = true
                                        }
                                    }
                                }
                            )
                            
                            // ✅ 兜底：后端可能返回“成功但没有有效内容”（summary/转写为空）。
                            // 前端仍需收敛为“完成态卡片”，避免一直 loading。
                            let hasMeaningfulTranscriptions: Bool = {
                                guard let ts = result.transcriptions, !ts.isEmpty else { return false }
                                return ts.contains(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            }()
                            let trimmedSummary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                            let hasMeaningfulSummary = !trimmedSummary.isEmpty
                            let summaryForUI: String = {
                                if hasMeaningfulSummary { return result.summary }
                                if hasMeaningfulTranscriptions { return "会议记录已生成（暂无摘要）。" }
                                return "会议记录已生成，但未识别到有效内容。"
                            }()
                            
                            // 更新卡片内容（列表占位 + 聊天室卡片）
                            await MainActor.run {
                                // 会议列表占位：如果需要，先把列表条目更新到完成态（不影响聊天室同步更新）
                                if updateMeetingList {
                                    let card = MeetingCard(
                                        remoteId: result.id,
                                        title: (result.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (result.title ?? title) : title,
                                        date: result.date ?? date,
                                        summary: summaryForUI,
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
                                }
                                
                                if uploadToChat {
                                    let ridResult = (result.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let ridCreated = (createdJobId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let didUpdate = updateMeetingCardInChat(
                                        audioPath: audioPath,
                                        remoteIdCandidates: [ridResult, ridCreated],
                                        messageContent: "已为您创建了一份会议记录文件，长按可调整。"
                                    ) { card in
                                        if let newTitle = result.title, !newTitle.isEmpty { card.title = newTitle }
                                        if let newDate = result.date { card.date = newDate }
                                        card.remoteId = result.id
                                        card.summary = summaryForUI
                                        card.transcriptions = result.transcriptions
                                        if let d = result.audioDuration { card.duration = d }
                                        if let u = result.audioUrl, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { card.audioRemoteURL = u }
                                        card.isGenerating = false
                                    }
                                    if !didUpdate {
                                        // 兜底：补插一张完成态卡片，避免 UI 卡住
                                        let fallbackCard = MeetingCard(
                                            remoteId: result.id,
                                            title: (result.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (result.title ?? title) : title,
                                            date: result.date ?? date,
                                            summary: summaryForUI,
                                            duration: result.audioDuration ?? duration,
                                            audioPath: audioPath,
                                            audioRemoteURL: result.audioUrl,
                                            transcriptions: result.transcriptions,
                                            isGenerating: false
                                        )
                                        let agentMsg = appState.addMeetingCardMessage(fallbackCard)
                                        appState.saveMessageToStorage(agentMsg, modelContext: modelContainer.mainContext)
                                        RecordingPlaybackController.shared.prefetch(meeting: fallbackCard)
                                    } else {
                                        // 预下载：更新后的卡片引用不易直接拿到，这里用 audioPath/rid 交给播放器内部自行命中缓存即可
                                        //（保留为空；真正播放时会按 remoteId/audioURL 预取）
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
                                
                                if updateMeetingList {
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
                                }
                                if uploadToChat {
                                    let content = shouldKeepGenerating ? "正在生成会议记录，请稍候..." : "会议记录生成失败，请稍后重试。"
                                    _ = updateMeetingCardInChat(
                                        audioPath: audioPath,
                                        remoteIdCandidates: [jid],
                                        messageContent: content
                                    ) { card in
                                        if shouldKeepGenerating {
                                            if (card.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { card.remoteId = jid }
                                            card.isGenerating = true
                                            card.summary = "正在生成会议记录（应用在后台时可能暂停刷新，回到前台会自动继续）。"
                                        } else {
                                            card.summary = "⚠️ 会议记录生成失败: \(error.localizedDescription)"
                                            card.isGenerating = false
                                        }
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
            
            // ✅ 兜底：如果后端返回“已完成但无有效内容”，也要把前端收敛为完成态占位卡片，避免一直 loading。
            let status = (item.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let looksCompleted = (
                status == "completed" || status == "complete" || status == "done" || status == "success" || status == "finished"
            )
            let hasAnyContent = (!newTitle.isEmpty) || (!newSummary.isEmpty) || hasDetails
            if !hasAnyContent && !looksCompleted {
                // 仍在处理中：保持生成中
                return
            }
            let summaryForUI: String = {
                if !newSummary.isEmpty { return newSummary }
                if hasDetails { return "会议记录已生成（暂无摘要）。" }
                return "会议记录已生成，但未识别到有效内容。"
            }()
            guard t.msgIndex < appState.chatMessages.count else { return }
            guard var meetings = appState.chatMessages[t.msgIndex].meetings, t.meetingIndex < meetings.count else { return }
            
            if !newTitle.isEmpty { meetings[t.meetingIndex].title = newTitle }
            meetings[t.meetingIndex].summary = summaryForUI
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
                    LiveRecordingManager.shared.startRecording(publishTranscriptionToUI: false, uploadToChat: true, updateMeetingList: false)
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
                    LiveRecordingManager.shared.startRecording(publishTranscriptionToUI: false, uploadToChat: true, updateMeetingList: false)
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
