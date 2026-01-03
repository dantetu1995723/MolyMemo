import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import UIKit

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
                    // 麦克风图标 - 使用纯白色
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                    
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
            // 锁屏视图 - 极简风格，黑白配色
            Link(destination: URL(string: "\(AppIdentifiers.urlScheme)://meeting-recording")!) {
                HStack(spacing: 12) {
                    // 状态图标
                    ZStack {
                        Circle()
                            .fill(.black)
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: context.state.isRecording ? "mic.fill" : "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isRecording ? "正在录音" : "录音已保存")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                        
                        if !context.state.isRecording {
                            Text("已生成会议卡片")
                                .font(.system(size: 12))
                                .foregroundColor(.black.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    if context.state.isRecording {
                        Text(formatDuration(context.state.duration))
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .activityBackgroundTint(.white)
            
        } dynamicIsland: { context in
            // 灵动岛 - 极简水平布局，所有元素在同一个 HStack 内对齐
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { EmptyView() }
                DynamicIslandExpandedRegion(.trailing) { EmptyView() }
                DynamicIslandExpandedRegion(.center) { EmptyView() }
                
                // 全部内容放在 bottom 区域，用 HStack 实现真正的水平对齐
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // 左：大话筒图标
                        Image(systemName: "mic.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // 中：计时器或完成文字
                        if context.state.isRecording {
                            Text(formatDuration(context.state.duration))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        } else {
                            Text("完成录音")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // 右：停止按钮或完成图标
                        if context.state.isRecording {
                            Button(intent: StopMeetingRecordingIntent()) {
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 52, height: 52)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.black)
                                        .frame(width: 18, height: 18)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            } compactLeading: {
                // 紧凑模式左侧：麦克风小图标
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } compactTrailing: {
                // 紧凑模式右侧：数字计时
                if context.state.isRecording {
                    Text(formatDuration(context.state.duration))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            } minimal: {
                // 最小化模式：仅图标
                Image(systemName: context.state.isRecording ? "mic.fill" : "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - 截图发送灵动岛提示
struct ScreenshotSendLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScreenshotSendAttributes.self) { context in
            // 锁屏：简洁提示
            Link(destination: URL(string: "\(AppIdentifiers.urlScheme)://chat")!) {
                HStack(spacing: 12) {
                    if let uiImage = loadThumbnail(from: context.state.thumbnailRelativePath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        ZStack {
                            Circle()
                                .fill(.black)
                                .frame(width: 32, height: 32)

                            Image(systemName: iconName(for: context.state.status))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: context.state.status))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)

                        Text(context.state.message)
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.6))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .activityBackgroundTint(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let uiImage = loadThumbnail(from: context.state.thumbnailRelativePath) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: iconName(for: context.state.status))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        VStack(spacing: 4) {
                            Text(title(for: context.state.status))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Text(context.state.message)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            } compactLeading: {
                if let uiImage = loadThumbnail(from: context.state.thumbnailRelativePath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: iconName(for: context.state.status))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            } compactTrailing: {
                Image(systemName: context.state.status == .failed ? "xmark" : "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(context.state.status == .sending ? 0 : 1)
            } minimal: {
                Image(systemName: iconName(for: context.state.status))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    private func title(for status: ScreenshotSendAttributes.ContentState.Status) -> String {
        switch status {
        case .sending: return "发送截图中"
        case .sent: return "截图已发送"
        case .failed: return "发送失败"
        }
    }

    private func iconName(for status: ScreenshotSendAttributes.ContentState.Status) -> String {
        switch status {
        case .sending: return "paperplane.fill"
        case .sent: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func loadThumbnail(from relativePath: String?) -> UIImage? {
        guard let url = ScreenshotSendAttributes.thumbnailURL(relativePath: relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
