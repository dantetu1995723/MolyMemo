import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

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
                // 改为与聊天室一致的深色卡片风格
                Color(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x22 / 255.0)
                
                VStack(spacing: 8) {
                    // 麦克风图标 - 使用更干净的亮绿色
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(Color(red: 0.8, green: 1.0, blue: 0.1))
                    
                    // 标题
                    Text("Moly录音")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // 提示
                    Text("轻触开始")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
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
        .configurationDisplayName("Moly录音")
        .description("快速启动 Moly录音")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 锁屏和灵动岛视图
struct MeetingRecordingLiveActivity: Widget {
    // 严格对齐聊天室的调色板 - 极简白/灰/黑风格
    private let chatBackground = Color(red: 0xF7 / 255.0, green: 0xF8 / 255.0, blue: 0xFA / 255.0)
    private let bubbleWhite = Color.white // Agent 气泡风格
    private let bubbleDark = Color(red: 34 / 255.0, green: 34 / 255.0, blue: 34 / 255.0) // 用户气泡风格
    private let primaryText = Color(red: 51 / 255.0, green: 51 / 255.0, blue: 51 / 255.0) // #333333
    private let secondaryText = Color(red: 102 / 255.0, green: 102 / 255.0, blue: 102 / 255.0) // #666666
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetingRecordingAttributes.self) { context in
            // 锁屏视图 - 极简风格，只显示状态和时长
            Link(destination: URL(string: "yuanyuan://meeting-recording")!) {
                HStack {
                    // 状态图标
                    ZStack {
                        Circle()
                            .fill(bubbleDark)
                            .frame(width: 26, height: 26)
                        
                        Image(systemName: context.state.isRecording ? "waveform" : "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text(context.state.isRecording ? "正在录音" : "录音已保存")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(primaryText)
                    
                    Spacer()
                    
                    Text(formatDuration(context.state.duration))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(primaryText)
                }
                .padding(16)
            }
            .activityBackgroundTint(chatBackground)
            
        } dynamicIsland: { context in
            // 灵动岛 - 彻底放弃黄绿逻辑
            DynamicIsland {
                // 展开视图
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isRecording ? "mic.fill" : "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(context.state.isRecording ? .white : Color(red: 0.8, green: 1.0, blue: 0.1))
                        Text(context.state.isRecording ? "Moly 录音" : "录音已完成")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.leading, 8)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isRecording {
                        Text(formatDuration(context.state.duration))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.trailing, 8)
                    } else {
                        // 完成时显示一个简单的状态
                        Text("已保存")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.8, green: 1.0, blue: 0.1))
                            .padding(.trailing, 8)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isRecording {
                        // 只保留停止按钮
                        Button(intent: StopMeetingRecordingIntent()) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 12))
                                Text("停止并生成卡片")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(bubbleWhite)
                            .foregroundColor(bubbleDark)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    } else {
                        // 完成后的状态反馈
                        Text("正在后台为您生成会议卡片...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 12)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isRecording ? "mic.fill" : "checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(context.state.isRecording ? .white : Color(red: 0.8, green: 1.0, blue: 0.1))
            } compactTrailing: {
                if context.state.isRecording {
                    Text(formatDuration(context.state.duration))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.8, green: 1.0, blue: 0.1))
                }
            } minimal: {
                Image(systemName: context.state.isRecording ? "mic.fill" : "checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(context.state.isRecording ? .white : Color(red: 0.8, green: 1.0, blue: 0.1))
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
