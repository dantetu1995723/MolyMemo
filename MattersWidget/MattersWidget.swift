import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// MARK: - 歌词式滚动视图
struct ScrollingLyricsView: View {
    let text: String
    let useAdaptiveSize: Bool
    
    init(text: String, useAdaptiveSize: Bool = false) {
        self.text = text
        self.useAdaptiveSize = useAdaptiveSize
    }
    
    // 将文字分段显示（每10个字一段，或按标点分割）
    private var displayLines: [String] {
        if text.isEmpty {
            return []
        }
        
        // 简单处理：每隔一定长度或遇到标点就换行
        let separators = "。！？.!?"
        var lines: [String] = []
        var currentLine = ""
        var charCount = 0
        
        for char in text {
            currentLine.append(char)
            charCount += 1
            
            // 遇到句号或超过15个字就分行
            if separators.contains(char) || charCount >= 15 {
                lines.append(currentLine.trimmingCharacters(in: .whitespacesAndNewlines))
                currentLine = ""
                charCount = 0
            }
        }
        
        // 添加剩余文字
        if !currentLine.isEmpty {
            lines.append(currentLine.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // 只显示最后2行
        return Array(lines.suffix(2))
    }
    
    var body: some View {
        if useAdaptiveSize {
            GeometryReader { geometry in
                let width = geometry.size.width
                let primarySize = min(width * 0.042, 15)
                let secondarySize = min(width * 0.036, 13)
                let spacing = min(width * 0.011, 4)
                
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(
                                size: index == displayLines.count - 1 ? primarySize : secondarySize,
                                weight: index == displayLines.count - 1 ? .semibold : .regular,
                                design: .rounded
                            ))
                            .foregroundColor(index == displayLines.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(index == displayLines.count - 1 ? 1.0 : 0.6)
                            .id("\(index)-\(line)")
                    }
                }
                .animation(.easeOut(duration: 0.3), value: displayLines.count)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.system(
                        size: index == displayLines.count - 1 ? 15 : 13,
                        weight: index == displayLines.count - 1 ? .semibold : .regular,
                        design: .rounded
                    ))
                    .foregroundColor(index == displayLines.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(index == displayLines.count - 1 ? 1.0 : 0.6)
                    .id("\(index)-\(line)")
            }
        }
        .animation(.easeOut(duration: 0.3), value: displayLines.count)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget Provider
struct MeetingRecordingProvider: TimelineProvider {
    func placeholder(in context: Context) -> MeetingRecordingEntry {
        MeetingRecordingEntry(date: Date())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (MeetingRecordingEntry) -> Void) {
        let entry = MeetingRecordingEntry(date: Date())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<MeetingRecordingEntry>) -> Void) {
        let entry = MeetingRecordingEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// Widget Entry
struct MeetingRecordingEntry: TimelineEntry {
    let date: Date
}

// Widget 视图
struct MeetingRecordingWidgetView: View {
    var entry: MeetingRecordingEntry
    
    var body: some View {
        Button(intent: StartMeetingRecordingIntent()) {
            ZStack {
                // 渐变背景
                LinearGradient(
                    colors: [
                        Color(red: 0.65, green: 0.85, blue: 0.15),
                        Color(red: 0.58, green: 0.78, blue: 0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(spacing: 8) {
                    // 麦克风图标
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                    
                    // 标题
                    Text("会议录音")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // 提示
                    Text("轻触开始")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding()
            }
        }
        .buttonStyle(.plain)
    }
}

// Widget 配置
struct MeetingRecordingWidget: Widget {
    let kind: String = "MeetingRecordingWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeetingRecordingProvider()) { entry in
            MeetingRecordingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("会议录音")
        .description("快速启动会议录音")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Live Activity 视图

struct MeetingRecordingLiveActivityView: View {
    let context: ActivityViewContext<MeetingRecordingAttributes>
    
    // 主App的霓虹色调
    private let neonColor = Color(red: 0.85, green: 1.0, blue: 0.25)
    private let gradientGreen1 = Color(red: 0.65, green: 0.85, blue: 0.15)
    private let gradientGreen2 = Color(red: 0.58, green: 0.78, blue: 0.1)
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧：录音图标和时长
            HStack(spacing: 8) {
                // 动画录音图标
                if context.state.isRecording {
                    if context.state.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(red: 0.9, green: 0.85, blue: 0.2))
                            .shadow(color: Color(red: 0.9, green: 0.85, blue: 0.2).opacity(0.6), radius: 8)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(neonColor)
                            .shadow(color: neonColor.opacity(0.6), radius: 8)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(gradientGreen1)
                        .shadow(color: gradientGreen1.opacity(0.5), radius: 8)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(context.state.duration))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    
                    Text(context.state.isRecording ? (context.state.isPaused ? "已暂停" : "录音中...") : "已完成")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// 锁屏和灵动岛视图
struct MeetingRecordingLiveActivity: Widget {
    // 主App的霓虹色调
    private let neonColor = Color(red: 0.85, green: 1.0, blue: 0.25)
    private let gradientGreen1 = Color(red: 0.65, green: 0.85, blue: 0.15)
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetingRecordingAttributes.self) { context in
            // 锁屏视图
            Link(destination: URL(string: "matters://meeting-recording")!) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if context.state.isRecording {
                            Image(systemName: "waveform")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(neonColor)
                                .shadow(color: neonColor.opacity(0.6), radius: 8)
                                .symbolEffect(.variableColor.iterative, isActive: true)
                        }
                        
                        Text(context.state.isRecording ? "录音中" : "录音完成")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        
                        Spacer()
                        
                        Text(formatDuration(context.state.duration))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    
                    // 转写文字 - 歌词式滚动
                    if !context.state.transcribedText.isEmpty {
                        ScrollingLyricsView(text: context.state.transcribedText, useAdaptiveSize: true)
                            .frame(height: 45)
                    }
                }
                .padding(16)
            }
            .activityBackgroundTint(Color(.systemBackground))
            
        } dynamicIsland: { context in
            // 灵动岛
            DynamicIsland {
                // 展开视图 - 添加点击跳转
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if context.state.isRecording {
                            if context.state.isPaused {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(red: 0.9, green: 0.85, blue: 0.2))
                                    .shadow(color: Color(red: 0.9, green: 0.85, blue: 0.2).opacity(0.5), radius: 6)
                            } else {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(neonColor)
                                    .shadow(color: neonColor.opacity(0.6), radius: 8)
                                    .symbolEffect(.variableColor.iterative, isActive: true)
                            }
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(gradientGreen1)
                                .shadow(color: gradientGreen1.opacity(0.5), radius: 6)
                        }
                        
                        Text(context.state.isRecording ? (context.state.isPaused ? "已暂停" : "录音中") : "完成")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .padding(.leading, 8)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatDuration(context.state.duration))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.trailing, 8)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        // 转写文字 - 歌词式滚动显示
                        if !context.state.transcribedText.isEmpty {
                            ScrollingLyricsView(text: context.state.transcribedText)
                                .frame(height: 40)
                                .padding(.horizontal, 4)
                        } else {
                            Text("等待说话...")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(height: 40)
                        }
                        
                        // 控制按钮
                        if context.state.isRecording {
                            HStack(spacing: 12) {
                                // 暂停/继续按钮
                                if context.state.isPaused {
                                    // 继续按钮
                                    Button(intent: ResumeMeetingRecordingIntent()) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text("继续")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        }
                                        .foregroundColor(Color.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [neonColor, Color(red: 0.75, green: 0.95, blue: 0.2)],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .shadow(color: neonColor.opacity(0.5), radius: 8)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    // 暂停按钮
                                    Button(intent: PauseMeetingRecordingIntent()) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "pause.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text("暂停")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        }
                                        .foregroundColor(Color.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(Color(red: 0.9, green: 0.85, blue: 0.2))
                                                .shadow(color: Color(red: 0.9, green: 0.85, blue: 0.2).opacity(0.5), radius: 8)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // 停止按钮
                                Button(intent: StopMeetingRecordingIntent()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "stop.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("停止")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                            .overlay(
                                                Capsule()
                                                    .stroke(gradientGreen1, lineWidth: 1.5)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                // 紧凑视图左侧 - 录音状态图标
                    if context.state.isRecording {
                        if context.state.isPaused {
                            Image(systemName: "pause.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(red: 0.9, green: 0.85, blue: 0.2))
                            .shadow(color: Color(red: 0.9, green: 0.85, blue: 0.2).opacity(0.5), radius: 4)
                        } else {
                            Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                                .foregroundColor(neonColor)
                            .shadow(color: neonColor.opacity(0.6), radius: 6)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                            .foregroundColor(gradientGreen1)
                }
            } compactTrailing: {
                // 紧凑视图右侧 - 时长
                Text(formatDuration(context.state.duration))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            } minimal: {
                // 最小视图 - 只显示核心图标
                ZStack {
                    if context.state.isRecording {
                        if context.state.isPaused {
                            // 暂停状态
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.9, green: 0.85, blue: 0.2))
                        } else {
                            // 录音中 - 波形 + 脉冲效果
                            ZStack {
                                // 脉冲光晕
                                Circle()
                                    .fill(neonColor.opacity(0.3))
                                    .frame(width: 18, height: 18)
                                    .scaleEffect(1.0)
                                    .symbolEffect(.pulse)
                                
                                // 主图标
                            Image(systemName: "waveform")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(neonColor)
                                    .symbolEffect(.variableColor.iterative)
                            }
                        }
                    } else {
                        // 完成状态
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(gradientGreen1)
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
