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
                            .fill(context.state.isCompleted ? Color.green : Color.black)
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: context.state.isCompleted ? "checkmark" : (context.state.isRecording ? "mic.fill" : "pause.fill"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isCompleted ? "录音已保存" : (context.state.isRecording ? "正在录音" : "录音已暂停"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                        
                        if context.state.isCompleted {
                            Text("已生成会议卡片")
                                .font(.system(size: 12))
                                .foregroundColor(.black.opacity(0.6))
                        } else {
                            Text(context.state.isPaused ? "已暂停" : "点击进入详情")
                                .font(.system(size: 12))
                                .foregroundColor(.black.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    if context.state.isCompleted {
                        Text(formatDuration(context.state.duration))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .monospacedDigit()
                    } else {
                        Text(context.state.isPaused ? "已暂停" : "录音中")
                            .font(.system(size: 14, weight: .bold))
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
                        // 左：品牌 Logo
                        if context.state.isCompleted {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 52, height: 52)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.green)
                            }
                        } else {
                            // 🏠 与停止按钮同尺寸、白底圆形，左右对称
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 52, height: 52)
                                Image("molymemo")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    // 让 logo 在白底里的占比更大
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.black)
                                    .opacity(context.state.isPaused ? 0.55 : 1.0)
                            }
                        }
                        
                        Spacer()
                        
                        // 中：音浪动画 (替代文字)
                        if context.state.isCompleted {
                            VStack(spacing: 2) {
                                Text("录音已保存")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                Text("已同步至聊天室")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else if context.state.isRecording && !context.state.isPaused {
                            // 🎙️ 录音中：自绘音浪动画（不依赖 SF Symbols）
                            AnimatedWaveformBars(
                                // 展开态：更长一些（更多柱子、更宽）
                                barCount: 13,
                                barWidth: 3,
                                minHeight: 7,
                                maxHeight: 36,
                                spacing: 3,
                                color: .white,
                                isActive: true,
                                speed: 2.8,
                                phase: context.state.wavePhase
                            )
                        } else {
                            // 暂停：保留静态音浪，避免“文字”和“音浪”来回切换造成割裂
                            AnimatedWaveformBars(
                                barCount: 13,
                                barWidth: 3,
                                minHeight: 7,
                                maxHeight: 36,
                                spacing: 3,
                                color: .white.opacity(0.55),
                                isActive: false,
                                speed: 2.8,
                                phase: context.state.wavePhase
                            )
                        }
                        
                        Spacer()
                        
                        // 右：操作或时长
                        if context.state.isCompleted {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("总时长")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                Text(formatDuration(context.state.duration))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .monospacedDigit()
                            }
                        } else if context.state.isRecording {
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
                            Text("暂停")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            } compactLeading: {
                // 紧凑模式左侧：白底圆 + moly（与右侧停止键风格一致）
                if context.state.isCompleted {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                        Image("molymemo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(.black)
                            .opacity(context.state.isPaused ? 0.55 : 1.0)
                    }
                }
            } compactTrailing: {
                if context.state.isCompleted {
                    Text("完成")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                } else if context.state.isRecording && !context.state.isPaused {
                    // 🎙️ 录音中：紧凑态用“小音浪动画”（自绘）
                    AnimatedWaveformBars(
                        barCount: 5,
                        barWidth: 2,
                        minHeight: 6,
                        maxHeight: 14,
                        spacing: 2,
                        color: .white,
                        isActive: true,
                        speed: 3.2,
                        phase: context.state.wavePhase
                    )
                } else {
                    AnimatedWaveformBars(
                        barCount: 5,
                        barWidth: 2,
                        minHeight: 6,
                        maxHeight: 14,
                        spacing: 2,
                        color: .white.opacity(0.55),
                        isActive: false,
                        speed: 3.2,
                        phase: context.state.wavePhase
                    )
                }
            } minimal: {
                // 最小化模式：也要白底圆
                if context.state.isCompleted {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                        Image("molymemo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundStyle(.black)
                            .opacity(context.state.isPaused ? 0.55 : 1.0)
                    }
                }
            }
        }
    }

    // MARK: - 自绘音浪（Timeline 驱动）
    private struct AnimatedWaveformBars: View {
        let barCount: Int
        let barWidth: CGFloat
        let minHeight: CGFloat
        let maxHeight: CGFloat
        let spacing: CGFloat
        let color: Color
        let isActive: Bool
        let speed: Double
        let phase: Int

        var body: some View {
            bars(at: isActive ? Double(phase) / 1.0 : 0)
            // 让紧凑态布局更稳定，避免随着高度变化导致 baseline 抖动
            .frame(height: maxHeight, alignment: .center)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: phase)
            .accessibilityLabel(isActive ? "录音中" : "已暂停")
        }

        @ViewBuilder
        private func bars(at t: Double) -> some View {
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = barHeight(t: t, index: i)
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: h)
                }
            }
        }

        private func barHeight(t: Double, index: Int) -> CGFloat {
            guard isActive else {
                // 静态态：保持有节奏但不动的高度分布
                let preset: [CGFloat] = [0.35, 0.60, 0.85, 0.55, 0.40, 0.70, 0.50, 0.80, 0.45]
                let f = preset[index % preset.count]
                return minHeight + (maxHeight - minHeight) * f
            }

            // 动态态：多频叠加 + 轻微“呼吸”振幅，让柱子更灵动（仍保持确定性，避免抖动/闪烁）
            let p = (t * speed) + Double(index) * 0.58
            let a = sin(p)
            let b = sin(p * 0.57 + 1.9)
            let c = sin(p * 1.13 + Double(index) * 0.9)
            let raw = (a * 0.52 + b * 0.28 + c * 0.20) // [-1, 1]
            let normalized = (raw + 1) / 2             // [0, 1]

            // “呼吸”振幅：整体强弱随相位缓慢变化，更像真实音浪
            let breathe = 0.85 + 0.15 * sin((t * 0.35) + Double(index) * 0.22) // [0.7~1.0] 左右
            let shaped = pow(normalized, 0.75)                                  // 强化峰值，让跳动更明显

            // 下限抬高，避免柱子“消失”导致视觉闪烁
            let f = 0.22 + 0.78 * (shaped * breathe)
            return minHeight + (maxHeight - minHeight) * CGFloat(f)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

// MARK: - 截图发送灵动岛视图
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
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupId),
              let path = relativePath else { return nil }
        let url = base.appendingPathComponent(path)
        return UIImage(contentsOfFile: url.path)
    }
}
