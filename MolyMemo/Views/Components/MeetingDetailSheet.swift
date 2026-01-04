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
    
    var body: some View {
        let canPlay = playback.canPlay(meeting: meeting)
        let isCurrent = playback.isCurrent(meeting: meeting)
        let isPlaying = isCurrent && playback.isPlaying
        let isDownloading = isCurrent && playback.isDownloading

        // 🔍 调试：播放器时长 vs 后端时长
        let backendDuration = meeting.duration ?? 0
        let playerDuration = playback.duration
        let duration = max(playerDuration > 0 ? playerDuration : backendDuration, 0.0001)
        #if DEBUG
        let _ = {
            print("🔍 [MeetingDetailSheet] duration 选择: player=\(playerDuration) backend=\(backendDuration) used=\(duration)")
            return true
        }()
        #endif
        let progressValue = isScrubbing ? scrubValue : min(max(playback.currentTime / duration, 0), 1)
        let currentTimeLabel = formatHMS(isScrubbing ? scrubValue * duration : playback.currentTime)
        let remainingTimeLabel = "-\(formatHMS(max(duration - (isScrubbing ? scrubValue * duration : playback.currentTime), 0)))"

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
                                // 更多操作
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color(hex: "333333"))
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                        }
                        .padding(.trailing, 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 15)
                }
                .background(Color(hex: "F7F8FA"))
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 30) {
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
                        
                        if isLoading {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(Color(hex: "007AFF"))
                                Text("正在更新会议详情...")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(hex: "999999"))
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
                        
                        // 4. 对话列表
                        VStack(alignment: .leading, spacing: 28) {
                            if let transcriptions = meeting.transcriptions {
                                ForEach(transcriptions) { transcript in
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
                                            .foregroundColor(Color(hex: "999999"))
                                            .lineSpacing(7)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 160) // 给悬浮播放器留足空间
                    }
                    .padding(.top, 10)
                }
            }
            
            // 5. 悬浮播放控制模块
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
                print("🌐 [MeetingDetailSheet] GET 会议详情: id=\(remoteId) attempt=\(attempt)/\(maxAttempts)")
                let item = try await MeetingMinutesService.getMeetingMinutesDetail(id: remoteId)
                let status = (item.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                print("🔍 [MeetingDetailSheet] 当前 status=\(status.isEmpty ? "nil" : status) audioDuration=\(String(describing: item.audioDuration))")
            
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
                    return MeetingTranscription(speaker: speaker, time: time, content: text)
                }
            } else if let ts = item.transcriptions, !ts.isEmpty {
                meeting.transcriptions = ts.compactMap { t in
                    guard let content = t.content, !content.isEmpty else { return nil }
                    return MeetingTranscription(
                        speaker: t.speaker ?? "说话人",
                        time: t.time ?? "00:00:00",
                        content: content
                    )
                }
            }
            
            // 更新时长和路径（只使用 audio_duration）
            print("🔍 [MeetingDetailSheet] 收到时长: audioDuration=\(String(describing: item.audioDuration)) (raw duration=\(String(describing: item.duration)))")
            if let duration = item.audioDuration {
                print("🔍 [MeetingDetailSheet] 更新 meeting.duration = \(duration)")
                meeting.duration = duration
            } else {
                print("⚠️ [MeetingDetailSheet] audioDuration 为 nil，不更新时长")
            }
            // 音频：audio_url 作为远程原始文件链接；audio_path 可能是服务端路径，不保证本地可用
            if let audioUrl = item.audioUrl, !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meeting.audioRemoteURL = audioUrl
            }
            
            print("✅ [MeetingDetailSheet] 会议详情已更新")
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
                    print("✅ [MeetingDetailSheet] 轮询结束：hasTitle=\(hasTitle) hasSummary=\(hasSummary) status=\(status.isEmpty ? "nil" : status)")
                    meeting.isGenerating = false
                    break
                }

                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delayNs)
                } else {
                    print("⚠️ [MeetingDetailSheet] 轮询达到上限，最后 status=\(status.isEmpty ? "nil" : status) audioDuration=\(String(describing: item.audioDuration))")
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
                print("❌ [MeetingDetailSheet] 获取详情失败 attempt=\(attempt): \(error)")
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
}
