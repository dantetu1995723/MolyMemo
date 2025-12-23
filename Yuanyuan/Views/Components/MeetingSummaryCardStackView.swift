import SwiftUI

struct MeetingSummaryCardStackView: View {
    @Binding var meetings: [MeetingCard]
    @Binding var isParentScrollDisabled: Bool
    
    var onDeleteRequest: ((MeetingCard) -> Void)? = nil
    var onOpenDetail: ((MeetingCard) -> Void)? = nil
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var showMenu: Bool = false
    @State private var lastMenuOpenedAt: CFTimeInterval = 0
    @State private var isPressingCurrentCard: Bool = false

    @StateObject private var playback = RecordingPlaybackController.shared
    
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 220
    private let pageSwipeThreshold: CGFloat = 50
    
    var body: some View {
        VStack(spacing: 0) {
            // 卡片堆叠区域
            ZStack {
                if meetings.isEmpty {
                    Text("无会议纪要")
                        .foregroundColor(.gray)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color.white)
                        .cornerRadius(24)
                } else {
                    ForEach(0..<meetings.count, id: \.self) { index in
                        let relativeIndex = (index - currentIndex + meetings.count) % meetings.count
                        
                        if relativeIndex < 3 {
                            MeetingSummaryCardView(meeting: meetings[index], playback: playback)
                                .frame(width: cardWidth, height: cardHeight)
                                .scaleEffect(
                                    (1.0 - CGFloat(relativeIndex) * 0.05)
                                    * (index == currentIndex
                                       ? (showMenu ? 1.05 : (isPressingCurrentCard ? 0.985 : 1.0))
                                       : 1.0)
                                )
                                .offset(x: relativeIndex == 0 ? dragOffset : CGFloat(relativeIndex) * 12, y: 0)
                                .zIndex(Double(meetings.count - relativeIndex))
                                .shadow(color: Color.black.opacity(showMenu && index == currentIndex ? 0.12 : 0.04),
                                        radius: showMenu && index == currentIndex ? 16 : 10,
                                        x: 0,
                                        y: showMenu && index == currentIndex ? 9 : 4)
                                .opacity(relativeIndex < 3 ? 1 : 0)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPressingCurrentCard)
                                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showMenu)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard index == currentIndex else { return }
                                    if showMenu {
                                        withAnimation { showMenu = false }
                                        return
                                    }
                                    guard CACurrentMediaTime() - lastMenuOpenedAt > 0.18 else { return }
                                    onOpenDetail?(meetings[index])
                                }
                                .onLongPressGesture(
                                    minimumDuration: 0.12,
                                    maximumDistance: 20,
                                    perform: {
                                        guard index == currentIndex else { return }
                                        guard !showMenu else { return }
                                        lastMenuOpenedAt = CACurrentMediaTime()
                                        HapticFeedback.selection()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            showMenu = true
                                        }
                                    },
                                    onPressingChanged: { pressing in
                                        guard index == currentIndex else { return }
                                        if showMenu { return }
                                        isPressingCurrentCard = pressing
                                    }
                                )
                                .overlay(alignment: .topLeading) {
                                    if showMenu && index == currentIndex {
                                        CardCapsuleMenuView(
                                            onEdit: {
                                                let meeting = meetings[index]
                                                withAnimation { showMenu = false }
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    onOpenDetail?(meeting)
                                                }
                                            },
                                            onDelete: {
                                                let meeting = meetings[index]
                                                withAnimation { showMenu = false }
                                                if let onDeleteRequest = onDeleteRequest {
                                                    onDeleteRequest(meeting)
                                                } else {
                                                    meetings.removeAll { $0.id == meeting.id }
                                                    if meetings.isEmpty {
                                                        currentIndex = 0
                                                    } else {
                                                        currentIndex = currentIndex % meetings.count
                                                    }
                                                }
                                            },
                                            onDismiss: {
                                                withAnimation { showMenu = false }
                                            }
                                        )
                                        .offset(y: -60)
                                        .transition(.opacity)
                                        .zIndex(1000)
                                    }
                                }
                                .allowsHitTesting(index == currentIndex)
                        }
                    }
                }
            }
            .frame(height: cardHeight + 10) // 紧贴底部，只预留顶部空间给缩放/阴影
            .padding(.top, 10)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) else { return }
                        
                        isParentScrollDisabled = true
                        dragOffset = dx
                        if showMenu { withAnimation { showMenu = false } }
                    }
                    .onEnded { value in
                        defer {
                            isParentScrollDisabled = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                        
                        let dx = value.translation.width
                        guard !meetings.isEmpty else { return }
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if dx > pageSwipeThreshold {
                                currentIndex = (currentIndex - 1 + meetings.count) % meetings.count
                            } else if dx < -pageSwipeThreshold {
                                currentIndex = (currentIndex + 1) % meetings.count
                            }
                        }
                    }
            )
            .padding(.horizontal)
            
            // Pagination Dots
            if meetings.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<meetings.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 4)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissScheduleMenu)) { _ in
            if showMenu {
                withAnimation { showMenu = false }
            }
            isPressingCurrentCard = false
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
                            .foregroundColor(Color(hex: "333333"))
                            .lineLimit(1)
                        
                        Text(meeting.formattedDate)
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "999999"))
                    }
                    
                    Spacer()
                    
                    // 播放按钮 (蓝色背景，白色播放图标)
                    Button(action: {
                        HapticFeedback.light()
                        guard canPlay else { return }
                        playback.togglePlay(meeting: meeting)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "007AFF")) // 标准 iOS 蓝色
                                .frame(width: 38, height: 38)
                                .opacity(canPlay ? 1.0 : 0.35)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .offset(x: isPlaying ? 0 : 1) // 视觉居中偏移
                        }
                    }
                    .buttonStyle(.plain)
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
                    .foregroundColor(Color(hex: "333333").opacity(0.8))
                    .lineSpacing(5)
                    .lineLimit(4)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer(minLength: 0)
        }
        .background(Color.white)
        .cornerRadius(24)
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

