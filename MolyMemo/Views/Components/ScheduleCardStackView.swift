import SwiftUI
import Combine

extension NSNotification.Name {
    static let dismissScheduleMenu = NSNotification.Name("DismissScheduleMenu")
}

struct ScheduleCardStackView: View {
    @Binding var events: [ScheduleEvent]
    /// 横向翻页时，用于通知外层 ScrollView 临时禁用上下滚动，避免手势冲突
    @Binding var isParentScrollDisabled: Bool
    
    var onDeleteRequest: ((ScheduleEvent) -> Void)? = nil
    /// 单击卡片或点击编辑按钮打开详情
    var onOpenDetail: ((ScheduleEvent) -> Void)? = nil
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var showMenu: Bool = false
    @State private var lastMenuOpenedAt: CFTimeInterval = 0
    @State private var isPressingCurrentCard: Bool = false
    
    // Constants
    private let cardHeight: CGFloat = 300
    private let cardWidth: CGFloat = 300
    private let pageSwipeThreshold: CGFloat = 50
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 卡片堆叠区域
            ZStack {
                if events.isEmpty {
                    Text("无日程")
                        .foregroundColor(.gray)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color.white)
                        .cornerRadius(12)
                } else {
                    ForEach(0..<events.count, id: \.self) { index in
                        let relativeIndex = getRelativeIndex(index)
                        
                        if relativeIndex < 4 || relativeIndex == events.count - 1 {
                            cardView(for: index, relativeIndex: relativeIndex)
                        }
                    }
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .frame(height: cardHeight + 20)
            // 横滑翻页：用 DragGesture(minimumDistance: 20) 让竖滑先给 ScrollView
            // 关键：必须用 simultaneousGesture，不能用 gesture，否则会阻塞子视图的 onLongPressGesture（体感像“要等很久”）
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // 只处理横向意图
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
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) else { return }
                        guard !events.isEmpty else { return }
                        
                        let velocity = value.predictedEndTranslation.width - dx
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if dx > pageSwipeThreshold || velocity > 200 {
                                currentIndex = (currentIndex - 1 + events.count) % events.count
                            } else if dx < -pageSwipeThreshold || velocity < -200 {
                                currentIndex = (currentIndex + 1) % events.count
                            }
                        }
                    }
            )
            
            // Pagination Dots
            if events.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<events.count, id: \.self) { index in
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
    
    // MARK: - 单张卡片视图（含手势）
    @ViewBuilder
    private func cardView(for index: Int, relativeIndex: Int) -> some View {
        ScheduleCardView(event: $events[index])
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(
                getScale(relativeIndex)
                * (index == currentIndex
                   ? (showMenu ? 1.05 : (isPressingCurrentCard ? 0.985 : 1.0))
                   : 1.0)
            )
            .rotationEffect(.degrees(getRotation(relativeIndex)))
            .offset(x: getOffsetX(relativeIndex), y: 0)
            .zIndex(getZIndex(relativeIndex))
            .shadow(color: Color.black.opacity(showMenu && index == currentIndex ? 0.12 : 0.08),
                    radius: showMenu && index == currentIndex ? 16 : 12,
                    x: 0,
                    y: showMenu && index == currentIndex ? 9 : 6)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPressingCurrentCard)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showMenu)
            .contentShape(Rectangle())
            // 短按：未选中时打开详情；选中（菜单打开）时再次短按取消选中
            .onTapGesture {
                guard index == currentIndex else { return }
                if showMenu {
                    withAnimation { showMenu = false }
                    return
                }
                // 菜单刚关闭时不触发详情，避免误触
                guard CACurrentMediaTime() - lastMenuOpenedAt > 0.18 else { return }
                onOpenDetail?(events[index])
            }
             // 长按：打开胶囊菜单（更快；适当放宽可移动距离，避免“手抖”导致长按反复失败体感变慢）
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
            // 胶囊菜单
            .overlay(alignment: .topLeading) {
                if showMenu && index == currentIndex {
                    CardCapsuleMenuView(
                        onEdit: {
                            let event = events[index]
                            withAnimation { showMenu = false }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onOpenDetail?(event)
                            }
                        },
                        onDelete: {
                            let event = events[index]
                            withAnimation { showMenu = false }
                            if let onDeleteRequest = onDeleteRequest {
                                onDeleteRequest(event)
                            } else {
                                events.removeAll { $0.id == event.id }
                                if events.isEmpty {
                                    currentIndex = 0
                                } else {
                                    currentIndex = currentIndex % events.count
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
    
    // MARK: - Helper Functions
    
    private func getRelativeIndex(_ index: Int) -> Int {
        (index - currentIndex + events.count) % events.count
    }
    
    private func getScale(_ relativeIndex: Int) -> CGFloat {
        relativeIndex == 0 ? 1.0 : 1.0 - CGFloat(relativeIndex) * 0.05
    }
    
    private func getRotation(_ relativeIndex: Int) -> Double {
        relativeIndex == 0 ? Double(dragOffset / 20) : Double(relativeIndex) * 2
    }
    
    private func getOffsetX(_ relativeIndex: Int) -> CGFloat {
        relativeIndex == 0 ? dragOffset : CGFloat(relativeIndex) * 10
    }
    
    private func getZIndex(_ relativeIndex: Int) -> Double {
        relativeIndex == 0 ? 100 : Double(events.count - relativeIndex)
    }
}

// MARK: - Loading (Skeleton) Card
/// 与正式日程卡片同规格的 loading 卡片，用于工具调用期间占位（避免展示 raw tool 文本）
struct ScheduleCardLoadingStackView: View {
    var title: String = "创建日程"
    var subtitle: String = "正在保存日程信息…"

    /// 横向翻页时，用于通知外层 ScrollView 临时禁用上下滚动，避免手势冲突（与正式卡片保持签名一致，方便替换）
    @Binding var isParentScrollDisabled: Bool

    // 与 ScheduleCardStackView 保持一致
    private let cardHeight: CGFloat = 300
    private let cardWidth: CGFloat = 300

    init(
        title: String = "创建日程",
        subtitle: String = "正在保存日程信息…",
        isParentScrollDisabled: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isParentScrollDisabled = isParentScrollDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ScheduleCardLoadingView(title: title, subtitle: subtitle)
                    .frame(width: cardWidth, height: cardHeight)
                    .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
            }
            .frame(height: cardHeight + 20)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) else { return }
                        isParentScrollDisabled = true
                    }
                    .onEnded { _ in
                        isParentScrollDisabled = false
                    }
            )
        }
    }
}

struct ScheduleCardLoadingView: View {
    let title: String
    let subtitle: String

    private let primaryText = Color(red: 0.2, green: 0.2, blue: 0.2)
    private let skeleton = Color.black.opacity(0.06)
    private let skeletonStrong = Color.black.opacity(0.10)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(title)
                    .font(.custom("SourceHanSerifSC-Bold", size: 24))
                    .foregroundColor(primaryText)

                Spacer()

                ProgressView()
                    .progressViewStyle(.circular)
            }
            .padding(.bottom, 8)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .padding(.bottom, 14)

            // Skeleton blocks：模拟标题/时间/地点/描述
            RoundedRectangle(cornerRadius: 6)
                .fill(skeletonStrong)
                .frame(width: 180, height: 16)
                .padding(.bottom, 10)

            RoundedRectangle(cornerRadius: 6)
                .fill(skeleton)
                .frame(width: 220, height: 14)
                .padding(.bottom, 10)

            RoundedRectangle(cornerRadius: 6)
                .fill(skeleton)
                .frame(width: 150, height: 14)
                .padding(.bottom, 18)

            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color(hex: "EEEEEE"))
                    .frame(height: 1)

                Circle()
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                    .background(Circle().fill(Color.white))
                    .frame(width: 7, height: 7)
            }
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 20)

                RoundedRectangle(cornerRadius: 6)
                    .fill(skeleton)
                    .frame(width: 170, height: 14)
            }
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 20)

                RoundedRectangle(cornerRadius: 6)
                    .fill(skeleton)
                    .frame(width: 120, height: 14)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - 简化的胶囊菜单
struct CardCapsuleMenuView: View {
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onDismiss: () -> Void
    
    @State private var showRescanMenu: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                // 编辑
                Text("编辑")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "333333"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit() }
                
                Divider().background(Color.black.opacity(0.1)).frame(height: 16)
                
                // 重新识别
                HStack(spacing: 2) {
                    Text("重新识别")
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: showRescanMenu ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(Color(hex: "333333"))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showRescanMenu.toggle()
                    }
                }
                
                Divider().background(Color.black.opacity(0.1)).frame(height: 16)
                
                // 删除
                Text("删除")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "FF3B30"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { onDelete() }
            }
            .modifier(ConditionalCapsuleBackground(showRescanMenu: showRescanMenu))
            
            // 重新识别下拉
            if showRescanMenu {
                VStack(spacing: 0) {
                    ForEach(["这是日程", "这是人脉", "这是发票"], id: \.self) { option in
                        Text(option)
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "333333"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation { showRescanMenu = false }
                                onDismiss()
                            }
                        if option != "这是发票" {
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
                .glassEffect(in: .rect(cornerRadius: 16))
                .frame(width: 200)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - 日程卡片视图
struct ScheduleCardView: View {
    @Binding var event: ScheduleEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 左上角装饰点
            HStack(alignment: .top) {
                Circle()
                    .fill(Color(hex: "EBEBEB"))
                    .frame(width: 18, height: 18)
                    .overlay(
                        GeometryReader { geo in
                            ZStack {
                                Rectangle()
                                    .fill(Color.black.opacity(0.25))
                                    .mask(
                                        ZStack {
                                            Rectangle().fill(Color.black)
                                            Circle().frame(width: geo.size.width, height: geo.size.height).blendMode(.destinationOut)
                                        }
                                        .compositingGroup()
                                    )
                                    .offset(y: 4)
                                    .blur(radius: 2.5)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(Circle())
                        }
                    )
                Spacer()
            }
            .padding(.bottom, 8)
            
            // 日期 & 冲突标签
            HStack(alignment: .center, spacing: 8) {
                Text(event.fullDateString)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "333333"))
                Spacer()
                if event.hasConflict {
                    Text("有日程冲突")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(hex: "F5A623"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "F5A623"), lineWidth: 1)
                        )
                }
            }
            .padding(.bottom, 14)
            
            // 分隔线
            HStack(spacing: 6) {
                Rectangle().fill(Color(hex: "EEEEEE")).frame(height: 1)
                Circle()
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                    .background(Circle().fill(Color.white))
                    .frame(width: 7, height: 7)
            }
            .padding(.bottom, 20)
            
            // 时间 & 内容
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    // ✅ end_time=null 时，不展示“结束时间=开始时间”的假象
                    Text(timeString(event.startTime, isEnd: false))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "333333"))

                    if event.endTimeProvided {
                        Text("~")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "999999"))
                            .padding(.leading, 2)
                        Text(timeString(event.endTime, isEnd: true))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "666666"))
                    }
                }
                .fixedSize()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "333333"))
                        .lineLimit(1)
                    Text(event.description)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "666666"))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            if let t = scheduleReminderDisplayText(event.reminderTime) {
                Text(t)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "999999"))
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.03), lineWidth: 1)
        )
    }
    
    private func timeString(_ date: Date, isEnd: Bool) -> String {
        if event.isFullDay {
            return isEnd ? "24:00" : "00:00"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func scheduleReminderDisplayText(_ value: String?) -> String? {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        switch v {
        case "-5m": return "日程将在开始前5分钟提醒"
        case "-10m": return "日程将在开始前10分钟提醒"
        case "-15m": return "日程将在开始前15分钟提醒"
        case "-30m": return "日程将在开始前30分钟提醒"
        case "-1h": return "日程将在开始前1小时提醒"
        case "-2h": return "日程将在开始前2小时提醒"
        case "-1d": return "日程将在开始前1天提醒"
        case "-2d": return "日程将在开始前2天提醒"
        case "-1w": return "日程将在开始前1周提醒"
        case "-2w": return "日程将在开始前2周提醒"
        default: return "日程提醒：\(v)"
        }
    }
}

// MARK: - 胶囊背景
struct ConditionalCapsuleBackground: ViewModifier {
    let showRescanMenu: Bool
    
    func body(content: Content) -> some View {
        Group {
            if showRescanMenu {
                content.background(Capsule().fill(Color(hex: "F5F5F5")))
            } else {
                content.glassEffect(in: .capsule)
            }
        }
    }
}
