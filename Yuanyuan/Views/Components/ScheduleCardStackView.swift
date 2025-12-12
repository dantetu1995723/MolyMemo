import SwiftUI

struct ScheduleCardStackView: View {
    @Binding var events: [ScheduleEvent]
    /// 横向翻页时，用于通知外层 ScrollView 临时禁用上下滚动，避免手势冲突
    @Binding var isParentScrollDisabled: Bool
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    
    // Constants
    private let cardHeight: CGFloat = 300 // Reduced height from 420 to 300 based on screenshot
    private let cardWidth: CGFloat = 300 // Adjust based on screen width if needed
    private let pageSwipeDistanceThreshold: CGFloat = 70
    private let pageSwipeVelocityThreshold: CGFloat = 800
    
    var body: some View {
        VStack(spacing: 8) {
            // Card Stack
            ZStack {
                if events.isEmpty {
                    Text("无日程")
                        .foregroundColor(.gray)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color.white)
                        .cornerRadius(24)
                } else {
                    ForEach(0..<events.count, id: \.self) { index in
                        // Calculate relative index for cyclic view
                        let relativeIndex = getRelativeIndex(index)
                        
                        // Only show relevant cards for performance
                        // Show current, next few, and the one that might be swiping out/in
                        if relativeIndex < 4 || relativeIndex == events.count - 1 {
                            ScheduleCardView(event: $events[index])
                                .frame(width: cardWidth, height: cardHeight)
                                .scaleEffect(getScale(relativeIndex))
                                .rotationEffect(.degrees(getRotation(relativeIndex)))
                                .offset(x: getOffsetX(relativeIndex), y: 0) // Only horizontal offset for stack look
                                .zIndex(getZIndex(relativeIndex))
                                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                                // 只在「横向意图」时才会开始识别，从根上避免竖滑被卡片 DragGesture 抢走
                                .overlay(
                                    index == currentIndex
                                    ? HorizontalPanGestureInstaller(
                                        directionRatio: 1.15,
                                        onChanged: { dx in
                                            isParentScrollDisabled = true
                                            dragOffset = CGSize(width: dx, height: 0)
                                        },
                                        onEnded: { dx, vx in
                                            defer {
                                                isParentScrollDisabled = false
                                                withAnimation(.spring()) {
                                                    dragOffset = .zero
                                                }
                                            }
                                            guard !events.isEmpty else { return }
                                            withAnimation(.spring()) {
                                                // 翻页方向与底部圆点方向保持一致：向右 = 下一个点；向左 = 上一个点
                                                // 更省力：距离阈值降低，同时支持“短距离快速甩动”
                                                if dx > pageSwipeDistanceThreshold || vx > pageSwipeVelocityThreshold {
                                                    currentIndex = (currentIndex + 1) % events.count
                                                } else if dx < -pageSwipeDistanceThreshold || vx < -pageSwipeVelocityThreshold {
                                                    currentIndex = (currentIndex - 1 + events.count) % events.count
                                                }
                                            }
                                        }
                                    )
                                    : nil
                                )
                                .allowsHitTesting(index == currentIndex)
                        }
                    }
                }
            }
            .frame(height: cardHeight + 20) // Give some space for rotation/offset
            .padding(.horizontal)
            
            // Pagination Dots
            if events.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<events.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getRelativeIndex(_ index: Int) -> Int {
        return (index - currentIndex + events.count) % events.count
    }
    
    private func getScale(_ relativeIndex: Int) -> CGFloat {
        if relativeIndex == 0 {
            return 1.0
        } else {
            // Cards behind get smaller
            return 1.0 - (CGFloat(relativeIndex) * 0.05)
        }
    }
    
    private func getRotation(_ relativeIndex: Int) -> Double {
        if relativeIndex == 0 {
            // Rotate with drag
            return Double(dragOffset.width / 20)
        } else {
            // Static rotation for stack effect
            return Double(relativeIndex) * 2
        }
    }
    
    private func getOffsetX(_ relativeIndex: Int) -> CGFloat {
        if relativeIndex == 0 {
            return dragOffset.width
        } else {
            // Stack offset to the right
            return CGFloat(relativeIndex) * 10
        }
    }
    
    private func getZIndex(_ relativeIndex: Int) -> Double {
        if relativeIndex == 0 {
            return 100
        } else {
            return Double(events.count - relativeIndex)
        }
    }
}

struct ScheduleCardView: View {
    @Binding var event: ScheduleEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: 圆点一行，日期单独一行，整体左对齐
            VStack(alignment: .leading, spacing: 6) {
                // 第一行：左上圆点
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 12, height: 12)
                
                // 第二行：日期一行（年月 + 星期）
                HStack(spacing: 16) {
                    Text(event.monthYear)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    Text(event.weekDay)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 5)
            
            // Big Date Number & Reminder Hint
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(event.day)
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.black)
                
                Text("日程将在开始前半小时提醒")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 10)
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .overlay(
                    // Circle on the divider line
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        .background(Circle().fill(Color.white))
                        .frame(width: 8, height: 8)
                        .offset(x: 0) // Center it or align right? Screenshot shows it aligned right usually or specifically placed.
                        // Existing code had it aligned right. Let's keep it simple or align right.
                        , alignment: .trailing
                )
                .padding(.bottom, 15)
            
            // Time & Content
            HStack(alignment: .top, spacing: 15) {
                // Time
                VStack(alignment: .leading, spacing: 4) {
                    Text(timeString(event.startTime))
                        .font(.system(size: 16, weight: .medium))
                    Text("~")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.gray)
                    Text(timeString(event.endTime)) // Show end time? Screenshot implies range
                        .font(.system(size: 12, weight: .light)) // Maybe smaller end time
                        .foregroundColor(.gray)
                }
                .frame(width: 50, alignment: .leading)
                
                // Title & Description
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    
                    Text(event.description)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
