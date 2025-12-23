import SwiftUI

struct MeetingDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var meeting: MeetingCard

    @StateObject private var playback = RecordingPlaybackController.shared
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0
    
    var body: some View {
        let canPlay = playback.canPlay(meeting: meeting)
        let isCurrent = playback.isCurrent(meeting: meeting)
        let isPlaying = isCurrent && playback.isPlaying
        let duration = max(playback.duration, 0.0001)
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
                            Text(meeting.title)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(Color(hex: "333333"))
                            
                            Text(meeting.formattedDate)
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "999999"))
                        }
                        .padding(.horizontal, 24)
                        
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
                                
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                    .offset(x: isPlaying ? 0 : 3)
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

    private func formatHMS(_ time: TimeInterval) -> String {
        let total = Int(time.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
