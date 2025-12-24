import SwiftUI
import SwiftData
import AVFoundation
import UIKit

// 录音文件项（可包含会议纪要）
struct RecordingItem: Identifiable {
    var id: UUID
    var remoteId: String?  // 远程服务器ID
    var audioURL: URL?  // 本地音频文件URL（可选）
    let createdAt: Date
    let duration: TimeInterval
    var meetingSummary: String?  // 会议纪要内容
    var title: String  // 会议标题
    var transcriptions: [MeetingTranscription]?  // 转写记录
    var isFromRemote: Bool = false  // 是否来自远程服务器
    
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
        
        // 解析日期
        if let dateString = remoteItem.meetingDate ?? remoteItem.date {
            // 兼容 "yyyy-MM-dd" / ISO8601
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: dateString) {
                self.createdAt = d
            } else {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                self.createdAt = iso.date(from: dateString) ?? Date()
            }
        } else if let createdAt = remoteItem.createdAt {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.createdAt = iso.date(from: createdAt) ?? Date()
        } else {
            self.createdAt = Date()
        }
        
        print("🔍 [RecordingItem] 初始化时长: audioDuration=\(String(describing: remoteItem.audioDuration)) (raw duration=\(String(describing: remoteItem.duration)))")
        self.duration = remoteItem.audioDuration ?? 0
        print("🔍 [RecordingItem] 设置 self.duration = \(self.duration)")
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
                return MeetingTranscription(speaker: speaker, time: time, content: text)
            }
        } else {
            self.transcriptions = remoteItem.transcriptions?.compactMap { item in
                guard let content = item.content, !content.isEmpty else { return nil }
                return MeetingTranscription(
                    speaker: item.speaker ?? "说话人",
                    time: item.time ?? "00:00:00",
                    content: content
                )
            }
        }
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
    
    var body: some View {
        ZStack {
            // 渐变背景
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    // 主内容区域
                    if showContent {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                // 加载中状态
                                if isLoading && recordingItems.isEmpty {
                                    VStack(spacing: 16) {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                        Text("正在加载会议纪要...")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.black.opacity(0.5))
                                    }
                                    .padding(.top, 80)
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
                                }
                                // 空状态
                                else if recordingItems.isEmpty {
                                    EmptyMeetingView()
                                        .padding(.top, 60)
                                } else {
                                    ForEach(recordingItems) { item in
                                        RecordingItemCard(
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
                                                    // 不使用 list 接口的摘要/转写，强制以详情 GET 的返回为准
                                                    summary: "",
                                                    duration: item.duration,
                                                    audioPath: localPath,
                                                    audioRemoteURL: remoteURLString,
                                                    transcriptions: nil,
                                                    isGenerating: false
                                                )
                                                selectedMeetingCard = card
                                                showingDetailSheet = true
                                            },
                                            onDelete: {
                                                deleteRecording(item)
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 120)
                        }
                        .refreshable {
                            // 下拉刷新
                            await loadRecordingsFromServer()
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(
                title: "会议纪要",
                themeColor: themeColor,
                onBack: { dismiss() },
                // 新流程：会议纪要页不再提供“开始录音”入口（避免与快捷指令流程冲突）
                customTrailing: AnyView(EmptyView())
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingDetailSheet) {
            if selectedMeetingCard != nil {
                MeetingDetailSheet(meeting: Binding(
                    get: {
                        selectedMeetingCard
                            ?? MeetingCard(remoteId: nil, title: "", date: Date(), summary: "")
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
                print("✅ 检测到录音正在进行中，状态已同步")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopRecordingFromWidget"))) { _ in
            // 从灵动岛停止录音后，延迟刷新列表
            print("📱 会议纪要界面收到停止录音通知，准备刷新...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                print("🔄 刷新会议录音列表")
                loadRecordingsFromMeetings()
            }
        }
        .onChange(of: recordingManager.isRecording) { oldValue, newValue in
            // 监听录音状态变化，录音停止时刷新列表
            if oldValue && !newValue {
                print("🔄 检测到录音已停止，刷新列表")
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
        print("📡 ========== 开始加载会议纪要 ==========")
        print("📡 [MeetingRecordView] 搜索关键词: \(searchText.isEmpty ? "(空)" : searchText)")
        
        isLoading = true
        loadError = nil
        
        do {
            print("📡 [MeetingRecordView] 正在请求后端API...")
            let startTime = Date()
            
            let remoteItems = try await MeetingMinutesService.getMeetingMinutesList(
                search: searchText.isEmpty ? nil : searchText
            )
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("📡 [MeetingRecordView] 请求耗时: \(String(format: "%.2f", elapsed))秒")
            print("📡 [MeetingRecordView] 返回数据条数: \(remoteItems.count)")
            
            // 转换为 RecordingItem
            recordingItems = remoteItems.map { remoteItem in
                let recordingItem = RecordingItem(remoteItem: remoteItem)
                return recordingItem
            }
            
            print("✅ [MeetingRecordView] 成功加载 \(recordingItems.count) 条会议纪要")
            print("📡 ========== 加载完成 ==========\n")
            isLoading = false
            
        } catch {
            print("❌ ========== 加载失败 ==========")
            print("❌ [MeetingRecordView] 错误详情: \(error)")
            
            isLoading = false
            loadError = "加载失败: \(error.localizedDescription)"
        }
    }
    
    private func deleteRecording(_ item: RecordingItem) {
        HapticFeedback.medium()
        
        // 删除本地音频文件（如果存在）
        if let audioURL = item.audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        // 从列表中移除
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            recordingItems.removeAll { $0.id == item.id }
        }
        
        print("✅ 已删除录音文件")
    }
    
}

// MARK: - 子组件

// 空状态视图
struct EmptyMeetingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color.black.opacity(0.15))
            
            Text("暂无会议录音")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.5))
            
            Text("通过快捷指令开始录音")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color.black.opacity(0.35))
        }
    }
}

// 导航栏录音按钮 - 紧凑型
struct NavRecordingButton: View {
    let isRecording: Bool
    let isPaused: Bool
    let recordingDuration: TimeInterval
    let onStartRecording: () -> Void
    let onPauseRecording: () -> Void
    let onResumeRecording: () -> Void
    let onStopRecording: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 8) {
            // 时长显示 (仅在录音时)
            if isRecording {
                Text(formatDuration(recordingDuration))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isPaused ? .black.opacity(0.5) : .red)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                            )
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            
            // 主按钮
            Button(action: {
                if !isRecording {
                    onStartRecording()
                } else if isPaused {
                    onResumeRecording()
                } else {
                    onPauseRecording()
                }
            }) {
                ZStack {
                    if isRecording && !isPaused {
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .frame(width: 34, height: 34)
                            .scaleEffect(pulseScale)
                    }
                    
                    Image(systemName: isRecording ? (isPaused ? "play.fill" : "pause.fill") : "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isRecording && !isPaused ? .red : .black.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
                                )
                                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                        )
                }
            }
            .buttonStyle(.plain)
            
            // 停止按钮
            if isRecording {
                Button(action: onStopRecording) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
                                )
                                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        .onChange(of: isRecording, initial: true) { _, newValue in
            if newValue && !isPaused {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.2
                }
            } else {
                pulseScale = 1.0
            }
        }
        .onChange(of: isPaused) { _, newValue in
            if isRecording && !newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.2
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// 录音文件卡片（简化样式：仅标题、日期、时长）
struct RecordingItemCard: View {
    let item: RecordingItem
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isDeleteVisible = false
    @State private var isDragging = false
    
    private var isButtonDisabled: Bool {
        isDragging || abs(offset) > 5
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // 删除背景层
            if offset < 0 {
                ZStack(alignment: .trailing) {
                    Color.red
                    
                    Button(action: {
                        onDelete()
                        offset = 0
                        isDeleteVisible = false
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 90)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
            }
            
            // 前景卡片内容
            Button(action: {
                if !isDragging && abs(offset) < 5 {
                    onTap()
                }
            }) {
                VStack(spacing: 12) {
                    // 标题
                    Text(item.title.isEmpty ? "会议录音" : item.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 日期和时长
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text(item.formattedDate)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text(item.formattedDuration)
                        }
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.4))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    ZStack {
                        // 液态玻璃基础
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(0.88), location: 0.0),
                                        .init(color: Color.white.opacity(0.68), location: 0.5),
                                        .init(color: Color.white.opacity(0.78), location: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // 表面高光
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(0.45), location: 0.0),
                                        .init(color: Color.white.opacity(0.15), location: 0.2),
                                        .init(color: Color.clear, location: 0.5)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // 晶体边框
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(0.9), location: 0.0),
                                        .init(color: Color.white.opacity(0.35), location: 0.5),
                                        .init(color: Color.white.opacity(0.65), location: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: Color.white.opacity(0.5), radius: 6, x: 0, y: -2)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        isDragging = true
                        if value.translation.width < 0 {
                            offset = value.translation.width
                        } else if isDeleteVisible {
                            let newOffset = -90 + value.translation.width
                            offset = min(0, newOffset)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if value.translation.width < -60 {
                                offset = -90
                                isDeleteVisible = true
                            } else {
                                offset = 0
                                isDeleteVisible = false
                            }
                        }
                        // 延迟一点再恢复按钮，确保动画完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isDragging = false
                        }
                    }
            )
        }
    }
}
