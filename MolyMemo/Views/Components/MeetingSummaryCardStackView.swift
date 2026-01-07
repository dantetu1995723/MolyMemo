import SwiftUI

struct MeetingSummaryCardStackView: View {
    @Binding var meetings: [MeetingCard]
    @Binding var isParentScrollDisabled: Bool
    
    var onDeleteRequest: ((MeetingCard) -> Void)? = nil
    var onOpenDetail: ((MeetingCard) -> Void)? = nil
    
    @StateObject private var playback = RecordingPlaybackController.shared
    
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 220

    // 与发票卡片一致：不做左右滑动/堆叠翻页，仅做“单张/垂直列表”
    @State private var menuMeetingId: UUID? = nil
    @State private var lastMenuOpenedAt: CFTimeInterval = 0
    @State private var pressingMeetingId: UUID? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if meetings.isEmpty {
                Text("无会议纪要")
                    .foregroundColor(.gray)
                    .frame(width: cardWidth, height: cardHeight)
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                VStack(spacing: 12) {
                    ForEach(meetings) { meeting in
                        let scale: CGFloat = (menuMeetingId == meeting.id
                                              ? 1.03
                                              : (pressingMeetingId == meeting.id ? 0.985 : 1.0))
                        MeetingSummaryCardView(meeting: meeting, playback: playback)
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(scale)
                            .shadow(color: Color.black.opacity(menuMeetingId == meeting.id ? 0.12 : 0.06),
                                    radius: menuMeetingId == meeting.id ? 14 : 10,
                                    x: 0,
                                    y: menuMeetingId == meeting.id ? 8 : 4)
                            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: pressingMeetingId)
                            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: menuMeetingId)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if menuMeetingId == meeting.id {
                                    withAnimation { menuMeetingId = nil }
                                    return
                                }
                                guard CACurrentMediaTime() - lastMenuOpenedAt > 0.18 else { return }
                                onOpenDetail?(meeting)
                            }
                            .onLongPressGesture(
                                minimumDuration: 0.12,
                                maximumDistance: 20,
                                perform: {
                                    guard !meeting.isObsolete else { return } // 🚫 废弃卡片不触发菜单
                                    guard menuMeetingId == nil else { return }
                                    lastMenuOpenedAt = CACurrentMediaTime()
                                    HapticFeedback.selection()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        menuMeetingId = meeting.id
                                    }
                                },
                                onPressingChanged: { pressing in
                                    guard !meeting.isObsolete else { return }
                                    if menuMeetingId != nil { return }
                                    pressingMeetingId = pressing ? meeting.id : nil
                                }
                            )
                            .overlay(alignment: .topLeading) {
                                if menuMeetingId == meeting.id {
                                    CardCapsuleMenuView(
                                        onEdit: {
                                            withAnimation { menuMeetingId = nil }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                onOpenDetail?(meeting)
                                            }
                                        },
                                        onDelete: {
                                            withAnimation { menuMeetingId = nil }
                                            if let onDeleteRequest {
                                                onDeleteRequest(meeting)
                                            } else if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
                                                _ = withAnimation { meetings.remove(at: idx) }
                                            }
                                        },
                                        onDismiss: {
                                            withAnimation { menuMeetingId = nil }
                                        }
                                    )
                                    // 让胶囊跟随卡片缩放后的左边缘（默认缩放 anchor 是中心，leading 会向左/右移动半个增量）
                                    .offset(x: -(cardWidth * (scale - 1) / 2), y: -60)
                                    .transition(.opacity)
                                    .zIndex(1000)
                                }
                            }
                    }
                }
                // 与发票卡片一致：顶部仅留 10pt 给阴影/菜单，ChatView 里有 -10，会抵消并贴近上方文字
                .padding(.top, 10)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissScheduleMenu)) { _ in
            if menuMeetingId != nil {
                withAnimation { menuMeetingId = nil }
            }
            pressingMeetingId = nil
        }
    }
}

struct MeetingSummaryCardView: View {
    let meeting: MeetingCard
    @ObservedObject var playback: RecordingPlaybackController
    
    var body: some View {
        let canPlay = playback.canPlay(meeting: meeting)
        let isCurrent = playback.isCurrent(meeting: meeting)
        let isPlaying = isCurrent && playback.isPlaying

        VStack(alignment: .leading, spacing: 0) {
            if meeting.isGenerating {
                // 生成中：保持卡片规格不变，卡片内部使用“空白 + loading”占位（不展示半成品标题/日期/播放按钮）
                MeetingCardFullLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 标题和播放按钮
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meeting.title)
                            .font(.custom("SourceHanSerifSC-Bold", size: 19))
                            .foregroundColor(meeting.isObsolete ? Color(hex: "999999") : Color(hex: "333333"))
                            .strikethrough(meeting.isObsolete, color: Color(hex: "999999"))
                            .lineLimit(1)
                        
                        Text(meeting.formattedDate)
                            .font(.system(size: 14))
                            .foregroundColor(meeting.isObsolete ? Color(hex: "AAAAAA") : Color(hex: "999999"))
                            .strikethrough(meeting.isObsolete, color: Color(hex: "AAAAAA"))
                    }
                    
                    Spacer()
                    
                    // 播放按钮 (蓝色背景，白色播放图标)
                    Button(action: {
                        guard !meeting.isObsolete else { return }
                        HapticFeedback.light()
                        guard canPlay else { return }
                        playback.togglePlay(meeting: meeting)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "007AFF")) // 标准 iOS 蓝色
                                .frame(width: 38, height: 38)
                                .opacity(meeting.isObsolete ? 0.2 : (canPlay ? 1.0 : 0.35))

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .offset(x: isPlaying ? 0 : 1) // 视觉居中偏移
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(meeting.isObsolete)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                // 分隔线
                Rectangle()
                    .fill(Color(hex: "F2F2F2"))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                
                // 总结内容
                Text(meeting.summary)
                    .font(.system(size: 15))
                    .foregroundColor(meeting.isObsolete ? Color(hex: "BBBBBB") : Color(hex: "333333").opacity(0.8))
                    .strikethrough(meeting.isObsolete, color: Color(hex: "BBBBBB"))
                    .lineSpacing(5)
                    .lineLimit(4)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer(minLength: 0)
        }
        .background(meeting.isObsolete ? Color(hex: "F9F9F9") : Color.white)
        .cornerRadius(12)
        .opacity(meeting.isObsolete ? 0.8 : 1.0)
    }
}

/// 生成中：全卡片占位（保持卡片规格不变，只在内部显示 loading）
private struct MeetingCardFullLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            
            ProgressView()
                .scaleEffect(1.1)
                .tint(Color(hex: "007AFF"))
            
            LoadingDotsText(base: "正在生成会议纪要")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "666666"))
            
            VStack(spacing: 12) {
                SkeletonLine(widthFactor: 0.78)
                SkeletonLine(widthFactor: 0.62)
                SkeletonLine(widthFactor: 0.70)
            }
            .padding(.horizontal, 48)
            .padding(.top, 6)
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityLabel("正在生成会议纪要")
    }
}

private struct SkeletonLine: View {
    let widthFactor: CGFloat
    @State private var isOn: Bool = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.06))
                .frame(width: max(0, geo.size.width * widthFactor), height: 12)
                .opacity(isOn ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isOn)
                .onAppear { isOn = true }
        }
        .frame(height: 12)
    }
}

private struct LoadingDotsText: View {
    let base: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 4
            Text(base + String(repeating: "·", count: tick))
        }
    }
}

