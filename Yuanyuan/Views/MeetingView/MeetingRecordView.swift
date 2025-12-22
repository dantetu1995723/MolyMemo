import SwiftUI
import SwiftData
import AVFoundation
import UIKit

// 录音文件项（可包含会议纪要）
struct RecordingItem: Identifiable {
    var id: UUID
    let audioURL: URL
    let createdAt: Date
    let duration: TimeInterval
    var meetingSummary: String?  // 会议纪要内容
    var title: String  // 会议标题
    
    init(id: UUID = UUID(), audioURL: URL, createdAt: Date = Date(), duration: TimeInterval, meetingSummary: String? = nil, title: String = "") {
        self.id = id
        self.audioURL = audioURL
        self.createdAt = createdAt
        self.duration = duration
        self.meetingSummary = meetingSummary
        self.title = title
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
    
    // 播放状态
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playingRecordingId: UUID?
    @State private var playbackTimer: Timer?
    @State private var playbackProgress: TimeInterval = 0
    
    // 转换状态
    @State private var transcribingRecordingId: UUID?
    @State private var transcriptionProgress: String = ""
    
    // UI动画状态
    @State private var showContent = false
    @State private var showHeader = false
    
    // 折叠状态（录音项的折叠）
    @State private var expandedRecordings: Set<UUID> = []
    
    // 重命名状态
    @State private var renamingRecordingId: UUID?
    @State private var newTitle: String = ""
    
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
                                // 空状态
                                if recordingItems.isEmpty {
                                    EmptyMeetingView()
                                        .padding(.top, 60)
                                } else {
                                    ForEach(recordingItems) { item in
                                        RecordingItemCard(
                                            item: item,
                                            isPlaying: playingRecordingId == item.id,
                                            playbackProgress: playingRecordingId == item.id ? playbackProgress : 0,
                                            duration: item.duration,
                                            isTranscribing: transcribingRecordingId == item.id,
                                            transcriptionProgress: transcriptionProgress,
                                            isExpanded: expandedRecordings.contains(item.id),
                                            onPlay: {
                                                playRecording(item)
                                            },
                                            onStop: {
                                                stopPlaying()
                                            },
                                            onTranscribe: {
                                                transcribeRecording(item)
                                            },
                                            onToggle: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    if expandedRecordings.contains(item.id) {
                                                        expandedRecordings.remove(item.id)
                                                    } else {
                                                        expandedRecordings.insert(item.id)
                                                    }
                                                }
                                            },
                                            onRename: {
                                                startRenaming(item)
                                            },
                                            onCopyAndShare: {
                                                copyAndShareRecording(item)
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
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(
                title: "会议纪要",
                themeColor: themeColor,
                onBack: { dismiss() },
                customTrailing: AnyView(
                    NavRecordingButton(
                        isRecording: recordingManager.isRecording,
                        isPaused: recordingManager.isPaused,
                        recordingDuration: recordingManager.recordingDuration,
                        onStartRecording: {
                            recordingManager.modelContextProvider = { [modelContext] in
                                return modelContext
                            }
                            recordingManager.startRecording()
                        },
                        onPauseRecording: {
                            recordingManager.pauseRecording()
                        },
                        onResumeRecording: {
                            recordingManager.resumeRecording()
                        },
                        onStopRecording: {
                            recordingManager.stopRecording(modelContext: modelContext)
                            loadRecordingsFromMeetings()
                        }
                    )
                )
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("重命名会议", isPresented: Binding(
            get: { renamingRecordingId != nil },
            set: { if !$0 { renamingRecordingId = nil } }
        )) {
            TextField("输入新标题", text: $newTitle)
                .onChange(of: newTitle) { oldValue, newValue in
                    // 限制最多50个字符
                    if newValue.count > 50 {
                        newTitle = String(newValue.prefix(50))
                    }
                }
            Button("取消", role: .cancel) {
                renamingRecordingId = nil
            }
            Button("确定") {
                if let id = renamingRecordingId,
                   let item = recordingItems.first(where: { $0.id == id }) {
                    saveRename(item)
                }
            }
        } message: {
            Text("为这个会议录音设置一个新标题（最多50字）")
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
            
            // 音频会话配置延迟到后台执行，避免阻塞UI
            DispatchQueue.global(qos: .userInitiated).async {
                setupAudio()
            }
            
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
            // 当从底部tab栏点击加号时，开始录音
            if newValue && !recordingManager.isRecording {
                recordingManager.modelContextProvider = { [modelContext] in
                    return modelContext
                }
                recordingManager.startRecording()
                showAddSheet = false
            }
        }
    }
    
    // MARK: - 录音控制方法
    
    private func setupAudio() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            print("✅ 音频会话配置成功")
        } catch {
            print("❌ 音频会话配置失败: \(error)")
        }
    }
    
    private func loadRecordingsFromMeetings() {
        let descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\Meeting.createdAt, order: .reverse)])
        do {
            let meetings = try modelContext.fetch(descriptor)
            
            // 根据「时间+时长」兜底去重，同一段录音只展示一次
            // 即使底层因为异常生成了两条记录，这里也只会看到一条
            var seenKeys = Set<String>()
            recordingItems = meetings.compactMap { (meeting: Meeting) -> RecordingItem? in
                guard let audioPath = meeting.audioFilePath,
                      FileManager.default.fileExists(atPath: audioPath) else {
                    return nil
                }
                
                // 以分钟级时间戳 + 四舍五入后的时长作为“同一段录音”的标识
                let minuteStamp = Int(meeting.createdAt.timeIntervalSince1970 / 60)
                let roundedDuration = Int(meeting.duration.rounded())
                let key = "\(minuteStamp)|\(roundedDuration)"
                
                guard !seenKeys.contains(key) else {
                    let fileName = URL(fileURLWithPath: audioPath).lastPathComponent
                    print("⚠️ 检测到重复会议记录（同时间同时长），已在列表中隐藏: \(fileName)")
                    return nil
                }
                
                seenKeys.insert(key)
                
                return RecordingItem(
                    id: meeting.id,
                    audioURL: URL(fileURLWithPath: audioPath),
                    createdAt: meeting.createdAt,
                    duration: meeting.duration,
                    meetingSummary: meeting.content,
                    title: meeting.title
                )
            }
        } catch {
            print("❌ 读取录音失败: \(error)")
        }
    }
    
    private func stopPlayingIfNeeded(for itemId: UUID) {
        if playingRecordingId == itemId {
            stopPlaying()
        }
    }
    
    // MARK: - 播放控制
    
    private func playRecording(_ item: RecordingItem) {
        // 如果正在播放其他录音，先停止
        if playingRecordingId != nil && playingRecordingId != item.id {
            stopPlaying()
        }
        
        // 如果正在播放当前录音，则停止
        if playingRecordingId == item.id {
            stopPlaying()
            return
        }
        
        HapticFeedback.light()
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: item.audioURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            playingRecordingId = item.id
            playbackProgress = 0
            
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard let player = self.audioPlayer else { return }
                self.playbackProgress = player.currentTime
                
                if !player.isPlaying {
                    self.stopPlaying()
                }
            }
            
            print("▶️ 开始播放录音: \(item.id)")
        } catch {
            print("❌ 播放失败: \(error)")
        }
    }
    
    private func stopPlaying() {
        HapticFeedback.light()
        
        audioPlayer?.stop()
        playbackTimer?.invalidate()
        playingRecordingId = nil
        playbackProgress = 0
        
        print("⏹️ 停止播放")
    }
    
    // MARK: - 语音转文字
    
    private func transcribeRecording(_ item: RecordingItem) {
        transcribingRecordingId = item.id
        transcriptionProgress = "正在转写音频..."
        
        Task {
            do {
                // 第一步：使用通义千问3 ASR转写音频（支持长音频、情感识别）
                await MainActor.run {
                    transcriptionProgress = "正在识别音频..."
                }
                
                print("🎤 [MeetingRecord] 开始转写录音: \(item.audioURL.lastPathComponent)")
                let transcription = try await QwenASRService.transcribeAudio(fileURL: item.audioURL)
                
                guard !transcription.isEmpty else {
                    print("❌ [MeetingRecord] 识别结果为空")
                    throw NSError(domain: "Transcription", code: -1, userInfo: [NSLocalizedDescriptionKey: "识别结果为空"])
                }
                
                print("✅ [MeetingRecord] 音频转写完成 - 长度: \(transcription.count) 字符")
                print("   预览: \(transcription.prefix(100))...")
                
                // 第二步：使用 qwen max 生成会议纪要
                await MainActor.run {
                    transcriptionProgress = "正在生成会议纪要..."
                }
                
                let meetingSummary = try await QwenMaxService.generateMeetingSummary(transcription: transcription)
                
                await MainActor.run {
                    // 更新录音项的会议纪要
                    if let index = recordingItems.firstIndex(where: { $0.id == item.id }) {
                        recordingItems[index].meetingSummary = meetingSummary
                        
                        // 保存到数据库
                        if let meeting = allMeetings.first(where: { $0.id == item.id }) {
                            meeting.content = meetingSummary
                            do {
                                try modelContext.save()
                                print("✅ 会议纪要已保存到数据库")
                            } catch {
                                print("❌ 保存会议纪要失败: \(error)")
                            }
                        }
                        
                        // 自动展开该项
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            expandedRecordings.insert(item.id)
                        }
                    }
                    
                    transcribingRecordingId = nil
                    transcriptionProgress = ""
                    
                    HapticFeedback.success()
                    print("✅ 会议纪要生成并保存完成")
                }
            } catch {
                await MainActor.run {
                    transcribingRecordingId = nil
                    transcriptionProgress = ""
                    
                    print("❌ 转换失败: \(error)")
                }
            }
        }
    }
    
    // 分享会议纪要（以文件形式）
    private func copyAndShareRecording(_ item: RecordingItem) {
        HapticFeedback.light()
        
        // 构建分享内容
        var shareText = ""
        
        // 添加标题
        shareText += "📝 会议纪要\n"
        shareText += "━━━━━━━━━━━━━━━━\n\n"
        
        // 添加录音信息
        shareText += "📅 时间：\(item.formattedDate)\n"
        shareText += "⏱️ 时长：\(item.formattedDuration)\n\n"
        
        // 添加会议纪要内容
        if let summary = item.meetingSummary, !summary.isEmpty {
            shareText += summary
        } else {
            shareText += "（未生成会议纪要）"
        }
        
        shareText += "\n\n━━━━━━━━━━━━━━━━\n"
        shareText += "来自 Yuanyuan 会议记录"
        
        // 同时复制到剪贴板（备用）
        UIPasteboard.general.string = shareText
        
        // 创建临时文本文件
        let fileName = "会议纪要_\(item.formattedDate).txt"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            // 写入文件
            try shareText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ 已创建临时文件: \(fileURL.path)")
            
            // 弹出分享面板（以文件形式分享）
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                print("❌ 无法获取window")
                return
            }
            
            // 找到最顶层的 view controller
            var topController = window.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }
            
            guard let presentingVC = topController else {
                print("❌ 无法获取presenting view controller")
                return
            }
            
            let activityVC = UIActivityViewController(
                activityItems: [fileURL],  // 分享文件 URL
                applicationActivities: nil
            )
            
            // 设置完成回调，清理临时文件
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: fileURL)
                print("🗑️ 已清理临时文件")
            }
            
            // iPad 需要设置 popover，iPhone 默认从底部弹出
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = presentingVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: presentingVC.view.bounds.midX,
                    y: presentingVC.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }
            
            presentingVC.present(activityVC, animated: true)
            HapticFeedback.success()
            print("✅ 打开分享面板（文件模式）")
            
        } catch {
            print("❌ 创建临时文件失败: \(error)")
            HapticFeedback.error()
        }
    }
    
    // 开始重命名
    private func startRenaming(_ item: RecordingItem) {
        HapticFeedback.light()
        newTitle = item.title
        renamingRecordingId = item.id
    }
    
    // 保存重命名
    private func saveRename(_ item: RecordingItem) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            renamingRecordingId = nil
            return
        }
        
        // 限制字数（最多50个字符）
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.count > 50 ? String(trimmedTitle.prefix(50)) : trimmedTitle
        
        // 更新数据库
        if let meeting = allMeetings.first(where: { $0.id == item.id }) {
            meeting.title = finalTitle
            do {
                try modelContext.save()
                print("✅ 标题已更新: \(newTitle)")
                
                // 更新本地列表
                if let index = recordingItems.firstIndex(where: { $0.id == item.id }) {
                    recordingItems[index].title = finalTitle
                }
                
                HapticFeedback.success()
            } catch {
                print("❌ 保存标题失败: \(error)")
            }
        }
        
        renamingRecordingId = nil
    }
    
    private func deleteRecording(_ item: RecordingItem) {
        HapticFeedback.medium()
        
        // 如果正在播放该录音，先停止
        stopPlayingIfNeeded(for: item.id)
        
        // 删除音频文件
        try? FileManager.default.removeItem(at: item.audioURL)
        
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
            
            Text("点击下方按钮开始录音")
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

// 录音文件卡片（可展开显示会议纪要）
struct RecordingItemCard: View {
    let item: RecordingItem
    let isPlaying: Bool
    let playbackProgress: TimeInterval
    let duration: TimeInterval
    let isTranscribing: Bool
    let transcriptionProgress: String
    let isExpanded: Bool
    let onPlay: () -> Void
    let onStop: () -> Void
    let onTranscribe: () -> Void
    let onToggle: () -> Void
    let onRename: () -> Void
    let onCopyAndShare: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isDeleteVisible = false
    @State private var isDragging = false
    
    private var isButtonDisabled: Bool {
        isDragging || abs(offset) > 5
    }
    
    // 根据标题长度计算字体大小（自适应）
    private func calculateTitleFontSize(_ title: String) -> CGFloat {
        let titleLength = title.isEmpty ? 4 : title.count
        // 根据长度动态调整：短标题18，长标题逐渐减小，最小14
        // 使用更平滑的递减曲线
        if titleLength <= 8 {
            return 18
        } else if titleLength <= 15 {
            return 17.5
        } else if titleLength <= 25 {
            return 16.5
        } else if titleLength <= 35 {
            return 15.5
        } else {
            return 14.5
        }
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
        VStack(spacing: 0) {
            // 主卡片内容
            VStack(spacing: 16) {
                // 标题和操作行
                HStack(alignment: .top, spacing: 12) {
                    // 播放按钮（放在标题前面）
                    Button(action: {
                        if isPlaying {
                            onStop()
                        } else {
                            onPlay()
                        }
                    }) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(GlassButtonBackground())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isButtonDisabled)
                    
                    // 标题区域 - 确保可以换行
                    Text(item.title.isEmpty ? "会议录音" : item.title)
                        .font(.system(size: calculateTitleFontSize(item.title), weight: .bold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    
                    // 操作按钮组
                    HStack(spacing: 10) {
                        // 编辑按钮
                        Button(action: onRename) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color.black.opacity(0.4))
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isButtonDisabled)
                        
                        // 分享按钮（仅在有会议纪要时显示）
                        if item.hasTranscription {
                            Button(action: onCopyAndShare) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color.black.opacity(0.7))
                                    .frame(width: 44, height: 44)
                                    .background(GlassButtonBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(isButtonDisabled)
                        }
                        
                        // 转换/折叠按钮
                        if isTranscribing {
                            ProgressView()
                                .tint(Color.black.opacity(0.6))
                                .frame(width: 44, height: 44)
                                .background(GlassButtonBackground())
                        } else if item.hasTranscription {
                            // 已转换，显示折叠按钮
                            Button(action: onToggle) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                                    .frame(width: 44, height: 44)
                                    .background(GlassButtonBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(isButtonDisabled)
                        } else {
                            // 未转换，显示转换图标按钮
                            Button(action: onTranscribe) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                                    .frame(width: 44, height: 44)
                                    .background(GlassButtonBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(isButtonDisabled)
                        }
                    }
                }
                
                // 下半部分：日期和时长（底部信息栏）
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
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.4))
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            
            // 转文字进度显示（转文字过程中显示）
            if isTranscribing {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 18)
                    
                    HStack(spacing: 12) {
                        // 进度指示器
                        ProgressView()
                            .tint(Color(red: 0.65, green: 0.85, blue: 0.15))
                            .scaleEffect(0.9)
                        
                        // 进度文本
                        Text(transcriptionProgress.isEmpty ? "正在处理..." : transcriptionProgress)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.6))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .background(
                    Color(red: 0.65, green: 0.85, blue: 0.15).opacity(0.05)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // 会议纪要/原始文本（展开时显示）
            if isExpanded, let summary = item.meetingSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .padding(.horizontal, 18)
                    
                    // 如果是AI生成的会议纪要，正常显示
                    // 如果是原始转写文本，显示提示
                    VStack(alignment: .leading, spacing: 12) {
                        if !item.hasTranscription {
                            // 原始转写文本提示
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.black.opacity(0.5))
                                Text("原始录音文字")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.black.opacity(0.5))
                            }
                            .padding(.horizontal, 18)
                        }
                    
                    Text(summary)
                            .font(.system(size: 15, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.7))
                            .lineSpacing(8)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
