import SwiftUI

struct MeetingDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var meeting: MeetingCard

    @StateObject private var playback = RecordingPlaybackController.shared
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var didFetchOnAppear: Bool = false
    @State private var pollingTask: Task<Void, Never>? = nil
    
    // “歌词滚动”跟随：当前高亮的转写条目
    @State private var activeTranscriptId: UUID? = nil
    // 用户手动滚动时，短暂抑制自动滚动（避免抢控制权）
    @State private var suppressAutoScrollUntil: Date = .distantPast
    
    // 右上角“更多”-> 删除胶囊（与人脉/日程详情一致）
    @State private var showDeleteMenu: Bool = false
    @State private var deleteMenuAnchorFrame: CGRect = .zero
    @State private var isDeleting: Bool = false
    @State private var deleteAlertMessage: String? = nil
    
    var body: some View {
        let canPlay = playback.canPlay(meeting: meeting)
        let isCurrent = playback.isCurrent(meeting: meeting)
        let isPlaying = isCurrent && playback.isPlaying
        let isDownloading = isCurrent && playback.isDownloading
        
        let trimmedSummary = meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnyTextContent = !trimmedSummary.isEmpty || (meeting.transcriptions?.isEmpty == false)
        let hasAnyAudioRef: Bool = {
            let lp = (meeting.audioPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ru = (meeting.audioRemoteURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !lp.isEmpty || !ru.isEmpty
        }()
        // “没录到音”的判定：既没有可用音频引用，也没有任何文本内容，且不在生成中
        let showNoValidContentTip = (!meeting.isGenerating) && (!hasAnyAudioRef) && (!hasAnyTextContent)

        // 🔍 调试：播放器时长 vs 后端时长
        let backendDuration = meeting.duration ?? 0
        let playerDuration = playback.duration
        let duration = max(playerDuration > 0 ? playerDuration : backendDuration, 0.0001)
        #if DEBUG
        let _ = {
            return true
        }()
        #endif
        let playheadTime = isScrubbing ? scrubValue * duration : playback.currentTime
        let progressValue = isScrubbing ? scrubValue : min(max(playback.currentTime / duration, 0), 1)
        let currentTimeLabel = formatHMS(playheadTime)
        let remainingTimeLabel = "-\(formatHMS(max(duration - playheadTime, 0)))"
        
        let transcriptionsSorted: [MeetingTranscription] = {
            guard let ts = meeting.transcriptions, !ts.isEmpty else { return [] }
            return ts.sorted(by: { transcriptionStartSeconds($0) < transcriptionStartSeconds($1) })
        }()
        
        // 悬浮播放器会遮挡底部：给 ScrollView 预留足够空间，让最后一条也能滚到顶部
        let floatingPlayerReservedHeight: CGFloat = 320

        ZStack(alignment: .top) {
            // 背景色
            Color(hex: "F7F8FA").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 顶部拖动手柄和页眉
                VStack(spacing: 0) {
                    // 拖动手柄
                    Capsule()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)
                    
                    // 页眉标题和按钮
                    ZStack {
                        Text("会议纪要")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(hex: "333333"))
                        
                        HStack {
                            Spacer()
                            Button(action: {
                                HapticFeedback.light()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    showDeleteMenu.toggle()
                                }
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color(hex: "333333"))
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                            .disabled(isDeleting)
                            .modifier(GlobalFrameReporter(frame: $deleteMenuAnchorFrame))
                            .opacity(showDeleteMenu ? 0 : 1)
                            .allowsHitTesting(!showDeleteMenu)
                        }
                        .padding(.trailing, 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 15)
                }
                .background(Color(hex: "F7F8FA"))
                
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 30) {
                            if showNoValidContentTip {
                                VStack(spacing: 12) {
                                    Image(systemName: "mic.slash")
                                        .font(.system(size: 40, weight: .light))
                                        .foregroundColor(Color.black.opacity(0.22))
                                        .padding(.top, 26)
                                    
                                    Text("未录到有效内容")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(Color(hex: "333333"))
                                    
                                    Text("请重新录音后再试")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "999999"))
                                        .padding(.bottom, 26)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                
                                Spacer(minLength: 240)
                            } else {
                            // 2. 标题和日期
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    if meeting.isGenerating {
                                        TimelineView(.periodic(from: .now, by: 0.5)) { context in
                                            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 4
                                            Text("正在生成标题" + String(repeating: "·", count: tick))
                                                .font(.system(size: 26, weight: .bold))
                                                .foregroundColor(Color(hex: "333333"))
                                        }
                                    } else {
                                        Text(meeting.title)
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundColor(Color(hex: "333333"))
                                    }

                                    if meeting.isGenerating {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .tint(Color(hex: "007AFF"))
                                    }
                                }
                                
                                Text(meeting.formattedDate)
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: "999999"))
                            }
                            .padding(.horizontal, 24)
                            
                            if isLoading && meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 20) {
                                    HStack(spacing: 12) {
                                        ProgressView()
                                            .tint(Color(hex: "007AFF"))
                                        Text("正在获取会议详情...")
                                            .font(.system(size: 15))
                                            .foregroundColor(Color(hex: "999999"))
                                    }
                                    
                                    // 简单的骨架屏效果
                                    VStack(alignment: .leading, spacing: 12) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.black.opacity(0.05))
                                            .frame(height: 16)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.black.opacity(0.05))
                                            .frame(height: 16)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.black.opacity(0.05))
                                            .frame(width: 200, height: 16)
                                    }
                                }
                                .padding(.horizontal, 24)
                            } else if let error = loadError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.system(size: 14))
                                        .foregroundColor(.red)
                                    Button("重试") {
                                        pollingTask?.cancel()
                                        pollingTask = Task { await fetchDetailsWithPolling() }
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(hex: "007AFF"))
                                }
                                .padding(.horizontal, 24)
                            }
                            
                            // 3. 智能总结区块
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: "007AFF"))
                                    Text("智能总结")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(Color(hex: "333333"))
                                }

                                Group {
                                    if meeting.isGenerating {
                                        VStack(alignment: .leading, spacing: 14) {
                                            HStack(spacing: 10) {
                                                ProgressView()
                                                    .scaleEffect(0.95)
                                                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                                                    let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 4
                                                    Text("正在生成会议纪要" + String(repeating: "·", count: tick))
                                                        .font(.system(size: 15, weight: .medium))
                                                        .foregroundColor(Color(hex: "777777"))
                                                }
                                            }

                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.black.opacity(0.06))
                                                .frame(height: 14)
                                                .opacity(0.7)
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.black.opacity(0.06))
                                                .frame(height: 14)
                                                .opacity(0.5)
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.black.opacity(0.06))
                                                .frame(width: 220, height: 14)
                                                .opacity(0.6)
                                        }
                                    } else {
                                        Text(meeting.summary)
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(hex: "555555"))
                                            .lineSpacing(7)
                                    }
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 4)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.black.opacity(0.03), lineWidth: 1)
                                )
                            }
                            .padding(.horizontal, 24)
                            
                            // 4. 对话列表（随播放“歌词滚动”）
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(transcriptionsSorted) { transcript in
                                    let isActive = (transcript.id == activeTranscriptId)
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 10) {
                                            Text(transcript.speaker)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(Color(hex: "999999"))
                                            Text(transcript.time)
                                                .font(.system(size: 14))
                                                .foregroundColor(Color(hex: "CCCCCC"))
                                        }
                                        
                                        Text(transcript.content)
                                            .font(.system(size: 16))
                                            // 命中播放时间节点：文字变黑；其余保持灰色（不使用背景高亮）
                                            .foregroundColor(isActive ? Color(hex: "333333") : Color(hex: "999999"))
                                            .lineSpacing(7)
                                    }
                                    .padding(.vertical, 6)
                                    .id(transcript.id)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, floatingPlayerReservedHeight) // 给悬浮播放器留足空间（加大滚动幅度）
                            }
                        }
                        .padding(.top, 10)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { _ in
                                suppressAutoScrollUntil = Date().addingTimeInterval(2.0)
                            }
                    )
                    .onChange(of: playheadTime) { _, newTime in
                        // 只在“当前会议播放中/拖动中”跟随，并且避免用户手动滚动时抢控制权
                        guard isCurrent else { return }
                        guard isPlaying || isScrubbing else { return }
                        guard !transcriptionsSorted.isEmpty else { return }

                        let newId = resolveActiveTranscriptId(at: newTime, in: transcriptionsSorted)
                        if newId != activeTranscriptId {
                            activeTranscriptId = newId
                            guard Date() >= suppressAutoScrollUntil else { return }
                            if let id = newId {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    // “歌词效果”：当前句保持在列表顶部（不会被底部播放器遮挡）
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            
            // 5. 悬浮播放控制模块
            if !showNoValidContentTip {
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        // 进度条
                        VStack(spacing: 10) {
                            Slider(
                                value: Binding(
                                    get: { progressValue },
                                    set: { newValue in
                                        isScrubbing = true
                                        scrubValue = min(max(newValue, 0), 1)
                                    }
                                ),
                                onEditingChanged: { editing in
                                    if !editing {
                                        isScrubbing = false
                                        playback.seek(to: scrubValue * duration)
                                    }
                                }
                            )
                                .tint(Color(hex: "007AFF"))
                                .disabled(!canPlay || !isCurrent)
                            
                            HStack {
                                Text(currentTimeLabel)
                                Spacer()
                                Text(remainingTimeLabel)
                            }
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "999999"))
                        }
                        .padding(.horizontal, 24)
                        
                        // 控制按钮
                        HStack(spacing: 45) {
                            Button(action: {
                                HapticFeedback.light()
                                guard canPlay, isCurrent else { return }
                                playback.skip(by: -15)
                            }) {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(hex: "333333"))
                            }
                            .disabled(!canPlay || !isCurrent)
                            
                            Button(action: {
                                HapticFeedback.medium()
                                guard canPlay else { return }
                                playback.togglePlay(meeting: meeting)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "007AFF"))
                                        .frame(width: 68, height: 68)
                                        .shadow(color: Color(hex: "007AFF").opacity(0.3), radius: 8, x: 0, y: 4)
                                    
                                    if isDownloading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.white)
                                            .offset(x: isPlaying ? 0 : 3)
                                    }
                                }
                            }
                            .disabled(!canPlay)
                            .opacity(canPlay ? 1.0 : 0.45)
                            
                            Button(action: {
                                HapticFeedback.light()
                                guard canPlay, isCurrent else { return }
                                playback.skip(by: 15)
                            }) {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(hex: "333333"))
                            }
                            .disabled(!canPlay || !isCurrent)
                        }
                        .padding(.bottom, 50) // 适配安全区高度
                    }
                    .padding(.top, 25)
                    .background(
                        RoundedRectangle(cornerRadius: 35)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: -5)
                    )
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        // 点击空白处关闭删除胶囊（与人脉/日程一致）
        .overlay {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if showDeleteMenu {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    showDeleteMenu = false
                                }
                            }
                    }
                    
                    if showDeleteMenu {
                        TopDeletePillButton(title: isDeleting ? "正在删除…" : "删除录音") {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showDeleteMenu = false
                            }
                            HapticFeedback.medium()
                            Task { await submitDelete() }
                        }
                        .frame(width: 200)
                        .offset(
                            PopupMenuPositioning.rightAlignedCenterOffset(
                                for: deleteMenuAnchorFrame,
                                in: geo.frame(in: .global),
                                width: 200,
                                height: 52
                            )
                        )
                        .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity), removal: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity)))
                        .zIndex(30)
                        .allowsHitTesting(!isDeleting)
                    }
                }
            }
        }
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { deleteAlertMessage != nil },
                set: { if !$0 { deleteAlertMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deleteAlertMessage ?? "")
        }
        .task {
            // 如果有远程ID，自动获取详情以更新内容（特别是转写记录）
            guard !didFetchOnAppear else { return }
            didFetchOnAppear = true
            if meeting.remoteId != nil {
                pollingTask?.cancel()
                pollingTask = Task { await fetchDetailsWithPolling() }
                await pollingTask?.value
            }
        }
        // 关键：生成中用户可能提前进入详情页，此时 remoteId 还是 nil。
        // 当 remoteId 后续被写入（例如后端创建任务/生成完成后回填），这里需要自动触发一次拉取/轮询，否则 UI 会一直停在“正在生成…”
        .onChange(of: meeting.remoteId) { _, newValue in
            let rid = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            guard meeting.isGenerating || (meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return }
            pollingTask?.cancel()
            pollingTask = Task { await fetchDetailsWithPolling() }
        }
        // 兜底：如果外部已经把 title/summary 回填进来了（例如 MolyMemoApp 直接更新了聊天卡片），
        // 但 isGenerating 没被正确置为 false，这里自动收敛状态，避免无限 loading。
        .onChange(of: meeting.summary) { _, newValue in
            let s = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty && meeting.isGenerating {
                meeting.isGenerating = false
            }
        }
        .onDisappear {
            pollingTask?.cancel()
            pollingTask = nil
            // 下滑关闭详情页时，停止播放（避免切换到其他会议详情仍在播放上一条）
            playback.stop()
        }
    }
    
    @MainActor
    private func submitDelete() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        
        do {
            // 1) 先停播放，避免删文件时播放器仍占用
            playback.stop()
            
            // 2) 删远端（有 remoteId 才删）
            let rid = (meeting.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rid.isEmpty {
                try await MeetingMinutesService.deleteMeetingMinutes(id: rid)
            }
            
            // 3) 删本地音频文件（仅当 file path 存在）
            let localPath = (meeting.audioPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !localPath.isEmpty {
                let url = URL(fileURLWithPath: localPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            // 4) 通知会议列表立即移除
            NotificationCenter.default.post(
                name: NSNotification.Name("MeetingListDidDelete"),
                object: nil,
                userInfo: [
                    "remoteId": rid,
                    "audioPath": (meeting.audioPath ?? "")
                ]
            )
            
            dismiss()
        } catch {
            deleteAlertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func fetchDetailsWithPolling() async {
        guard let remoteId = meeting.remoteId else { return }
        
        isLoading = true
        loadError = nil
        
        // 轮询策略：
        // - 详情页的目标是“尽快把 title/summary/transcriptions 刷新出来”，不应强依赖 audio_duration
        // - 给后端一定时间，但避免无限转圈：最多 ~2 分钟
        let maxAttempts = 80
        let delayNs: UInt64 = 1_500_000_000 // 1.5s

        for attempt in 1...maxAttempts {
            if Task.isCancelled { break }
            do {
                let item = try await MeetingMinutesService.getMeetingMinutesDetail(id: remoteId)
                let status = (item.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 更新标题（如果不为空）
            if let newTitle = item.title, !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meeting.title = newTitle
            }
            
            // 更新摘要
            if let newSummary = item.summary ?? item.meetingSummary {
                meeting.summary = newSummary
            }
            
            // 更新转写记录
            if let details = item.meetingDetails, !details.isEmpty {
                meeting.transcriptions = details.compactMap { d in
                    guard let text = d.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let speaker = (d.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? d.speakerName!
                        : ("说话人" + (d.speakerId ?? ""))
                    let time = formatHMS(d.startTime ?? 0)
                    return MeetingTranscription(speaker: speaker, time: time, content: text, startTime: d.startTime, endTime: d.endTime)
                }
            } else if let ts = item.transcriptions, !ts.isEmpty {
                meeting.transcriptions = ts.compactMap { t in
                    guard let content = t.content, !content.isEmpty else { return nil }
                    return MeetingTranscription(
                        speaker: t.speaker ?? "说话人",
                        time: t.time ?? "00:00:00",
                        content: content,
                        startTime: parseHMSSeconds(t.time ?? "")
                    )
                }
            }
            
            // 更新时长和路径（只使用 audio_duration）
            if let duration = item.audioDuration {
                meeting.duration = duration
            } else {
            }
            // 音频：audio_url 作为远程原始文件链接；audio_path 可能是服务端路径，不保证本地可用
            if let audioUrl = item.audioUrl, !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meeting.audioRemoteURL = audioUrl
            }
            
                // 轮询退出条件（更贴近用户感知）：
                // - 如果 title/summary 任一已经有内容，且后端状态看起来“已完成”，即可结束生成态
                // - 即使 status 字段不规范，只要 summary 有内容，也可以结束生成态（避免无限 loading）
                let lowered = status.lowercased()
                let isDone =
                    lowered.contains("completed")
                    || lowered.contains("done")
                    || lowered.contains("success")
                    || lowered.contains("complete")
                let hasTitle = !meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasSummary = !meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if (hasTitle || hasSummary) && (isDone || hasSummary) {
                    meeting.isGenerating = false
                    break
                }

                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delayNs)
                } else {
                    // 达到上限也不要无限显示生成中：如果已经拿到任意内容就收敛；否则给出可重试的错误提示
                    let hasAnyContent = !meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (meeting.transcriptions?.isEmpty == false)
                    if hasAnyContent {
                        meeting.isGenerating = false
                    } else {
                        loadError = "生成中，稍后再试（已等待约\(Int(Double(maxAttempts) * (Double(delayNs) / 1_000_000_000)))秒）"
                    }
                }
            } catch {
                if attempt >= maxAttempts {
                    loadError = "详情更新失败: \(error.localizedDescription)"
                } else {
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
        }

        isLoading = false
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
        if let v = Double(s) {
            return max(0, v)
        }
        return nil
    }
    
    private func transcriptionStartSeconds(_ t: MeetingTranscription) -> TimeInterval {
        if let v = t.startTime { return max(0, v) }
        return parseHMSSeconds(t.time) ?? 0
    }
    
    private func resolveActiveTranscriptId(at time: TimeInterval, in transcriptions: [MeetingTranscription]) -> UUID? {
        guard !transcriptions.isEmpty else { return nil }
        let t = max(0, time)
        // 取最后一个 startTime <= 当前时间 的条目
        if let idx = transcriptions.lastIndex(where: { transcriptionStartSeconds($0) <= t + 0.05 }) {
            return transcriptions[idx].id
        }
        // 当前时间在第一句之前：高亮第一句
        return transcriptions.first?.id
    }
}
