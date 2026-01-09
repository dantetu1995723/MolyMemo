import SwiftUI
import SwiftData
import AVFoundation
import UIKit

// 录音文件项（可包含会议纪要）
struct RecordingItem: Identifiable {
    var id: UUID
    var remoteId: String?  // 远程服务器ID
    var audioURL: URL?  // 本地音频文件URL（可选）
    var createdAt: Date
    var duration: TimeInterval
    var meetingSummary: String?  // 会议纪要内容
    var title: String  // 会议标题
    var transcriptions: [MeetingTranscription]?  // 转写记录
    var isFromRemote: Bool = false  // 是否来自远程服务器
    var status: String?  // 状态：processing, completed, failed
    
    var isProcessing: Bool {
        status == "processing" || status == "generating"
    }
    
    // 本地录音初始化
    init(id: UUID = UUID(), audioURL: URL, createdAt: Date = Date(), duration: TimeInterval, meetingSummary: String? = nil, title: String = "") {
        self.id = id
        self.audioURL = audioURL
        self.createdAt = createdAt
        self.duration = duration
        self.meetingSummary = meetingSummary
        self.title = title
        self.isFromRemote = false
    }
    
    // 远程数据初始化
    init(remoteItem: MeetingMinutesService.MeetingMinutesItem) {
        self.id = UUID()
        self.remoteId = remoteItem.id
        self.isFromRemote = true
        self.status = remoteItem.status
        
        // 解析日期：列表要显示“时分秒/分钟”，优先用 updated_at/created_at（通常带时间），不要用 meeting_date(yyyy-MM-dd) 导致 00:00
        func parseBackendTimestamp(_ raw: String) -> Date? {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let d = iso2.date(from: s) { return d }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            if let d = df.date(from: s) { return d }
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            if let d = df.date(from: s) { return d }
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = df.date(from: s) { return d }
            return nil
        }

        if let updatedAt = remoteItem.updatedAt, let d = parseBackendTimestamp(updatedAt) {
            self.createdAt = d
        } else if let createdAt = remoteItem.createdAt, let d = parseBackendTimestamp(createdAt) {
            self.createdAt = d
        } else if let dateString = remoteItem.meetingDate ?? remoteItem.date {
            // 最后才用 meeting_date/date（可能只有 yyyy-MM-dd）
            if let d = parseBackendTimestamp(dateString) {
                self.createdAt = d
            } else {
                let df = DateFormatter()
                df.locale = Locale(identifier: "zh_CN")
                df.dateFormat = "yyyy-MM-dd"
                self.createdAt = df.date(from: dateString) ?? Date()
            }
        } else {
            self.createdAt = Date()
        }

        // 🔍 调试：打印列表 JSON 里的时间字段
        
        self.duration = remoteItem.audioDuration ?? 0
        self.meetingSummary = remoteItem.summary ?? remoteItem.meetingSummary
        self.title = remoteItem.title ?? "会议录音"
        
        // 设置音频路径
        if let audioPath = remoteItem.audioPath, !audioPath.isEmpty {
            self.audioURL = URL(fileURLWithPath: audioPath)
        } else if let audioUrl = remoteItem.audioUrl, !audioUrl.isEmpty, let u = URL(string: audioUrl) {
            self.audioURL = u
        }
        
        // 转换转写记录
        if let details = remoteItem.meetingDetails, !details.isEmpty {
            self.transcriptions = details.compactMap { d in
                guard let text = d.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let speaker = (d.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? d.speakerName!
                    : ("说话人" + (d.speakerId ?? ""))
                let time = {
                    let total = Int((d.startTime ?? 0).rounded(.down))
                    let h = total / 3600
                    let m = (total % 3600) / 60
                    let s = total % 60
                    return String(format: "%02d:%02d:%02d", h, m, s)
                }()
                return MeetingTranscription(speaker: speaker, time: time, content: text, startTime: d.startTime, endTime: d.endTime)
            }
        } else {
            self.transcriptions = remoteItem.transcriptions?.compactMap { item in
                guard let content = item.content, !content.isEmpty else { return nil }
                return MeetingTranscription(
                    speaker: item.speaker ?? "说话人",
                    time: item.time ?? "00:00:00",
                    content: content,
                    startTime: RecordingItem.parseHMSSeconds(item.time ?? "")
                )
            }
        }
    }

    private static func parseHMSSeconds(_ raw: String) -> TimeInterval? {
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
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: createdAt)
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }
    
    // 是否已转换为会议纪要（检查是否包含结构化标记）
    var hasTranscription: Bool {
        guard let summary = meetingSummary, !summary.isEmpty else {
            return false
        }
        // 判断是否是AI生成的会议纪要（检查是否包含 • 无序列表标记）
        // 实时录音的原始语音识别文本不会有这个标记
        return summary.contains("•")
    }
    
    // 是否可以播放（有本地音频文件）
    var canPlay: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// 会议纪要录音视图 - 重新设计
struct MeetingRecordView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]
    
    // 外部绑定的添加弹窗状态（由底部tab栏控制）
    @Binding var showAddSheet: Bool
    
    // 使用 LiveRecordingManager 统一管理录音
    @StateObject private var recordingManager = LiveRecordingManager.shared
    
    // 录音文件列表
    @State private var recordingItems: [RecordingItem] = []
    
    // 加载状态
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText: String = ""

    // 删除提示
    @State private var showDeleteAlert: Bool = false
    @State private var deleteAlertMessage: String = ""
    
    // UI动画状态
    @State private var showContent = false
    @State private var showHeader = false
    
    // 会议详情 Sheet
    @State private var showingDetailSheet = false
    @State private var selectedMeetingCard: MeetingCard?
    
    init(showAddSheet: Binding<Bool> = .constant(false)) {
        self._showAddSheet = showAddSheet
    }
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)

    /// 空状态视图（放在同一作用域内，避免 Xcode 索引偶发“找不到符号”假报错）
    private struct EmptyMeetingView: View {
        var body: some View {
            VStack(spacing: 18) {
                Image(systemName: "mic.circle")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(Color.black.opacity(0.15))

                Text("暂无会议录音")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.55))

                Text("点击右上角 + 开始新录音")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.35))
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 渐变背景
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    // 主内容区域
                    if showContent {
                        List {
                            // 1. 录制中卡片 (如果有正在进行的录音)
                            if recordingManager.isRecording {
                                MeetingRecordingCardView()
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }

                            // 2. 会议列表
                            if isLoading && recordingItems.isEmpty {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("正在加载会议纪要...")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.5))
                                }
                                .padding(.top, 80)
                                .frame(maxWidth: .infinity)
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            // 错误状态
                            else if let error = loadError {
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 48, weight: .light))
                                        .foregroundColor(Color.orange.opacity(0.6))
                                    Text(error)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.5))
                                    Button("重试") {
                                        loadRecordingsFromMeetings()
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.blue)
                                }
                                .padding(.top, 60)
                                .frame(maxWidth: .infinity)
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            // 空状态 (且没有在录音)
                            else if recordingItems.isEmpty && !recordingManager.isRecording {
                                EmptyMeetingView()
                                    .padding(.top, 60)
                                    .frame(maxWidth: .infinity)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(recordingItems) { item in
                                    MeetingCardItemView(
                                        item: item,
                                        onTap: {
                                            // 转换为 MeetingCard 并显示详情页
                                            let remoteURLString: String? = {
                                                guard let u = item.audioURL, !u.isFileURL else { return nil }
                                                return u.absoluteString
                                            }()
                                            let localPath: String? = {
                                                guard let u = item.audioURL, u.isFileURL else { return nil }
                                                return u.path
                                            }()
                                            let card = MeetingCard(
                                                id: item.id,
                                                remoteId: item.remoteId,
                                                title: item.title,
                                                date: item.createdAt,
                                                summary: "",
                                                duration: item.duration,
                                                audioPath: localPath,
                                                audioRemoteURL: remoteURLString,
                                                transcriptions: nil,
                                                isGenerating: item.isProcessing
                                            )
                                            selectedMeetingCard = card
                                            showingDetailSheet = true
                                        }
                                    )
                                    // ✅ 左滑删除（替代长按菜单）
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteRecording(item)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                                .labelStyle(.iconOnly)
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }

                            // 预留底部空间，避免被底部栏遮挡
                            Color.clear
                                .frame(height: 120)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        // 关键：List 自身内缩，swipeActions 按钮也会随之内缩，从而与卡片右边对齐
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .refreshable {
                            // 下拉刷新
                            await loadRecordingsFromServer()
                        }
                    }
                }
            }
        }
        .alert("删除失败", isPresented: $showDeleteAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deleteAlertMessage)
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(
                title: "会议纪要",
                themeColor: themeColor,
                onBack: { dismiss() },
                customTrailing: AnyView(
                    Button(action: {
                        HapticFeedback.light()
                        if !recordingManager.isRecording {
                            // 会议记录页内发起：不要往聊天室插入“正在生成”卡片
                            recordingManager.startRecording(suppressChatCardOnUpload: true)
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                )
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingDetailSheet) {
            if selectedMeetingCard != nil {
                MeetingDetailSheet(meeting: Binding(
                    get: {
                        // 这里不做 demo/空对象兜底：避免出现“空白会议详情”
                        selectedMeetingCard!
                    },
                    set: { selectedMeetingCard = $0 }
                ))
            }
        }
        .onAppear {
            // 立即显示内容，不要延迟
            showHeader = true
            showContent = true
            
            // 设置 ModelContext 提供器
            recordingManager.modelContextProvider = { [modelContext] in
                return modelContext
            }
            
            // 先加载已有的录音（轻量操作）
            loadRecordingsFromMeetings()
            
            // 延迟恢复孤立录音（避免和App终止时的保存操作冲突）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    await RecordingRecoveryManager.recoverOrphanedRecordings(modelContext: modelContext)
                    // 恢复后再次加载
                    loadRecordingsFromMeetings()
                }
            }
            
            // 如果LiveRecordingManager正在录音，确保状态同步
            if recordingManager.isRecording {
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopRecordingFromUI"))) { _ in
            recordingManager.stopRecording(modelContext: modelContext)
            // 录音停止后延迟刷新列表
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                loadRecordingsFromMeetings()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopRecordingFromWidget"))) { _ in
            // 从灵动岛停止录音后，延迟刷新列表
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                loadRecordingsFromMeetings()
            }
        }
        .onChange(of: recordingManager.isRecording) { oldValue, newValue in
            // 监听录音状态变化，录音停止时刷新列表
            if oldValue && !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loadRecordingsFromMeetings()
                }
            }
        }
        .onChange(of: showAddSheet) { _, newValue in
            // 新流程：不再在会议纪要页通过“加号/新增”触发录音
            if newValue {
                showAddSheet = false
            }
        }
        // ✅ 详情页删除：列表立刻移除（避免返回后还看到旧条目）
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MeetingListDidDelete"))) { notification in
            guard let userInfo = notification.userInfo else { return }
            let remoteId = (userInfo["remoteId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let audioPath = (userInfo["audioPath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteId.isEmpty || !audioPath.isEmpty else { return }
            
            if let idx = recordingItems.firstIndex(where: { item in
                let rid = (item.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lp = (item.audioURL?.isFileURL == true) ? (item.audioURL?.path ?? "") : ""
                return (!remoteId.isEmpty && rid == remoteId) || (!audioPath.isEmpty && lp == audioPath)
            }) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    recordingItems.remove(at: idx)
                }
            }
        }
        // ✅ 会议页录音：一旦进入“上传/生成”流程，立刻在列表插入等高的加载小卡片
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("RecordingNeedsUpload"))
                .receive(on: RunLoop.main)
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            let suppressChatCard = userInfo["suppressChatCard"] as? Bool ?? false
            guard suppressChatCard else { return }

            let title = userInfo["title"] as? String ?? "会议录音"
            let date = userInfo["date"] as? Date ?? Date()
            let duration = userInfo["duration"] as? TimeInterval ?? 0
            let audioPath = (userInfo["audioPath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !audioPath.isEmpty else { return }

            // 去重：同一个 audioPath 的占位卡只插一次
            if recordingItems.contains(where: { ($0.audioURL?.isFileURL == true) && ($0.audioURL?.path == audioPath) && ($0.status == "generating" || $0.status == "processing") }) {
                return
            }

            var placeholder = RecordingItem(
                id: UUID(),
                audioURL: URL(fileURLWithPath: audioPath),
                createdAt: date,
                duration: duration,
                meetingSummary: nil,
                title: "正在生成会议纪要…"
            )
            placeholder.status = "generating"
            placeholder.isFromRemote = false

            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                recordingItems.insert(placeholder, at: 0)
            }
        }
        // ✅ 后端创建 job 后，尽早拿到 remoteId，后续详情/轮询才可用
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("MeetingListJobCreated"))
                .receive(on: RunLoop.main)
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            let audioPath = (userInfo["audioPath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteId = (userInfo["remoteId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !audioPath.isEmpty, !remoteId.isEmpty else { return }

            if let idx = recordingItems.firstIndex(where: { ($0.audioURL?.isFileURL == true) && ($0.audioURL?.path == audioPath) }) {
                recordingItems[idx].remoteId = remoteId
                recordingItems[idx].status = "processing"
            }
        }
        // ✅ 生成完成：把占位卡立即更新成正常条目（无需等刷新）
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("MeetingListDidComplete"))
                .receive(on: RunLoop.main)
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            let audioPath = (userInfo["audioPath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !audioPath.isEmpty else { return }

            let remoteId = (userInfo["remoteId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (userInfo["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = userInfo["date"] as? Date
            let duration = userInfo["duration"] as? TimeInterval
            let summary = userInfo["summary"] as? String

            if let idx = recordingItems.firstIndex(where: { ($0.audioURL?.isFileURL == true) && ($0.audioURL?.path == audioPath) }) {
                if let rid = remoteId, !rid.isEmpty { recordingItems[idx].remoteId = rid }
                if let t = title, !t.isEmpty { recordingItems[idx].title = t }
                if let d = date { recordingItems[idx].createdAt = d }
                if let du = duration { recordingItems[idx].duration = du }
                if let s = summary, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recordingItems[idx].meetingSummary = s
                }
                recordingItems[idx].status = "completed"
            } else {
                // 兜底：如果占位卡不存在，也插入一个完成态条目
                var item = RecordingItem(
                    id: UUID(),
                    audioURL: URL(fileURLWithPath: audioPath),
                    createdAt: date ?? Date(),
                    duration: duration ?? 0,
                    meetingSummary: summary,
                    title: title ?? "会议录音"
                )
                item.remoteId = remoteId
                item.status = "completed"
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    recordingItems.insert(item, at: 0)
                }
            }
        }
        // ✅ 详情页一旦把标题/摘要拉到，就同步回列表（用户返回列表立刻看到更新）
        .onChange(of: selectedMeetingCard) { _, newValue in
            guard let card = newValue else { return }
            let rid = (card.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lp = (card.audioPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty || !lp.isEmpty else { return }

            guard let idx = recordingItems.firstIndex(where: { item in
                let sameRid = (!rid.isEmpty) && (item.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines) == rid)
                let sameLocalPath = (!lp.isEmpty) && (item.audioURL?.isFileURL == true) && (item.audioURL?.path == lp)
                return sameRid || sameLocalPath
            }) else { return }

            let newTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newTitle.isEmpty { recordingItems[idx].title = newTitle }
            recordingItems[idx].createdAt = card.date
            if let d = card.duration { recordingItems[idx].duration = d }
            let s = card.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { recordingItems[idx].meetingSummary = s }
            if !rid.isEmpty { recordingItems[idx].remoteId = rid }
            recordingItems[idx].status = card.isGenerating ? "processing" : "completed"
        }
    }
    
    // MARK: - 录音控制方法
    
    private func loadRecordingsFromMeetings() {
        // 使用异步任务从后端加载
        Task {
            await loadRecordingsFromServer()
        }
    }
    
    /// 从服务器加载会议纪要列表
    @MainActor
    private func loadRecordingsFromServer() async {
        
        isLoading = true
        loadError = nil
        
        do {
            let remoteItems = try await MeetingMinutesService.getMeetingMinutesList(
                search: searchText.isEmpty ? nil : searchText
            )
            
            // 转换为 RecordingItem
            let remoteRecordingItems: [RecordingItem] = remoteItems.map { RecordingItem(remoteItem: $0) }

            // 合并：保留本地“生成中/处理中”占位卡，避免被服务端列表覆盖导致“回显消失”
            let placeholders = recordingItems.filter { !$0.isFromRemote && ($0.status == "generating" || $0.status == "processing") }
            let keepPlaceholders = placeholders.filter { p in
                if let rid = p.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
                    return !remoteRecordingItems.contains(where: { ($0.remoteId ?? "") == rid })
                }
                return true
            }

            var merged = remoteRecordingItems + keepPlaceholders
            // 去重（按 remoteId）
            var seen = Set<String>()
            merged = merged.filter { item in
                let rid = (item.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rid.isEmpty else { return true }
                if seen.contains(rid) { return false }
                seen.insert(rid)
                return true
            }
            merged.sort { $0.createdAt > $1.createdAt }

            recordingItems = merged
            
            isLoading = false
            
        } catch {
            
            isLoading = false
            loadError = "加载失败: \(error.localizedDescription)"
        }
    }
    
    private func deleteRecording(_ item: RecordingItem) {
        HapticFeedback.medium()

        guard let index = recordingItems.firstIndex(where: { $0.id == item.id }) else { return }

        // 先做 UI 乐观更新：立即从列表移除
        _ = withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            recordingItems.remove(at: index)
        }

        Task {
            do {
                // 远程会议纪要：调用后端删除
                if let remoteId = item.remoteId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !remoteId.isEmpty {
                    try await MeetingMinutesService.deleteMeetingMinutes(id: remoteId)
                }

                // 本地音频文件：仅在 fileURL 时才删除
                if let audioURL = item.audioURL, audioURL.isFileURL {
                    try? FileManager.default.removeItem(at: audioURL)
                }

                #if DEBUG
                #endif
            } catch {
                // 失败回滚：把条目插回去，并弹窗提示
                await MainActor.run {
                    let insertIndex = min(index, recordingItems.count)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        recordingItems.insert(item, at: insertIndex)
                    }
                    deleteAlertMessage = error.localizedDescription
                    showDeleteAlert = true
                }
            }
        }
    }
    
}

// MARK: - 子组件

/// 录制中卡片组件
struct MeetingRecordingCardView: View {
    @ObservedObject var recordingManager = LiveRecordingManager.shared
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("录音纪要 | 录制中...")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black.opacity(0.8))
                    
                    Text(formatDuration(recordingManager.recordingDuration))
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.4))
                        .monospacedDigit()
                }
                Spacer()
            }
            
            // 波纹展示区
            SimpleWaveformView(audioPower: 0.5)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            
            // 停止按钮 - 更加集成
            Button(action: {
                HapticFeedback.medium()
                NotificationCenter.default.post(name: NSNotification.Name("StopRecordingFromUI"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

/// 简易波纹视图
struct SimpleWaveformView: View {
    let audioPower: CGFloat
    private let barCount = 50
    
    var body: some View {
        GeometryReader { geo in
            let count = max(barCount, 1)
            let spacing: CGFloat = 1.5
            let totalSpacing = spacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(count), 1)

            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    WaveBar(index: i, audioPower: audioPower, barWidth: barWidth)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

struct WaveBar: View {
    let index: Int
    let audioPower: CGFloat
    let barWidth: CGFloat
    @State private var height: CGFloat = 3
    
    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.black.opacity(0.08))
            .frame(width: barWidth, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.015)) {
                    height = CGFloat.random(in: 3...20)
                }
            }
    }
}

/// 普通会议卡片组件
struct MeetingCardItemView: View {
    let item: RecordingItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.title.isEmpty ? "会议录音" : item.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(2)
                    
                    if item.isProcessing {
                        Spacer()
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("处理中")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                        Text(item.formattedDate)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(item.formattedDuration)
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.4))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 子组件

// MARK: - 辅助方法
