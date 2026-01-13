import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 首页顶部"今日日程通知栏"（折叠/展开）
/// - 折叠：展示一条（优先显示"当前时间之后最近的一条"，否则显示当天第一条）
/// - 展开：展示当日全部日程列表 + "以上为今日日程" + 收起按钮
struct TodayScheduleNotificationBar: View {
    let events: [ScheduleEvent]
    let isLoading: Bool
    let errorText: String?
    
    @Binding var isExpanded: Bool
    
    var onTapRow: ((ScheduleEvent) -> Void)? = nil

    // 通知权限状态（用于提示用户开启）
    @State private var notificationAuthStatus: UNAuthorizationStatus? = nil
    
    // 主题色（与 ChatView 统一）
    private let primaryGray = Color(hex: "333333")
    
    /// 所有日程（排序后）
    private var allEvents: [ScheduleEvent] {
        expandedEvents()
    }

    private var hasError: Bool {
        guard let errorText else { return false }
        return !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 当天无日程时不显示通知栏（加载中不做前端占位）
    private var shouldShowBar: Bool {
        return !events.isEmpty || hasError
    }
    
    /// 折叠时显示的那一条日程
    private var collapsedEvent: ScheduleEvent? {
        let all = allEvents
        if all.isEmpty { return nil }
        if all.count == 1 { return all.first }
        let now = Date()
        if let next = all.first(where: { $0.startTime >= now }) { return next }
        return all.first
    }

    /// 折叠态的"叠页"层数（最多两层，即主卡片+一层背景）
    private var stackCount: Int {
        let n = allEvents.count
        if n <= 1 { return 0 }
        return min(1, n - 1) // 最多一层背景叠层
    }
    
    /// 展开态：日程列表的最大高度（避免把 footer / 收起按钮顶出屏幕）
    /// 视觉上大约显示 3 条，超过则内部滚动
    private let expandedListMaxHeight: CGFloat = 48 * 3 + 10 * 2
    
    /// 展开态列表实际高度：少量日程不强行撑开，超过上限则固定高度并滚动
    private var expandedListHeight: CGFloat {
        let rows = CGFloat(allEvents.count)
        guard rows > 0 else { return 0 }
        let content = rows * 48 + max(0, rows - 1) * 10 + 2 // +2: 给阴影/像素对齐留一点余量
        return min(expandedListMaxHeight, content)
    }
    
    var body: some View {
        Group {
            if shouldShowBar {
                VStack(spacing: 0) {
                    // 日程行列表
                    if isExpanded {
                        // 展开：列表区域可滚动（隐藏侧边滚动条）
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 10) { // 各个卡片之间的间距
                                ForEach(Array(allEvents.enumerated()), id: \.element.id) { _, e in
                                    rowView(event: e)
                                        .background(cardBackground) // 每个项目独立白底
                                        .contentShape(Rectangle())
                                        .onTapGesture { onTapRow?(e) }
                                }
                            }
                            .padding(.vertical, 1) // 让顶部/底部阴影不被裁剪得太狠
                        }
                        .frame(height: expandedListHeight, alignment: .top)
                    } else {
                        // 折叠：只显示一条
                        VStack(spacing: 10) {
                            if let e = collapsedEvent {
                                rowView(event: e)
                                    .background(cardBackground)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticFeedback.heavy()
                                        isExpanded = true
                                    }
                            }
                        }
                    }
                    
                    // 展开时的底部区域（footer + 收起按钮）
                    if isExpanded {
                        if shouldShowNotificationPermissionHint {
                            notificationPermissionHint
                                .padding(.top, 10)
                        }
                        footerView
                            .frame(maxWidth: .infinity) // 居中
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        collapseButton
                            .padding(.bottom, 8)
                    }
                }
                // 移除了整体的 .background(cardBackground)
                // 折叠态：叠页背景
                .background(
                    ZStack(alignment: .top) {
                        if !isExpanded && stackCount >= 2 {
                            collapsedBackCard(level: 2)
                        }
                        if !isExpanded && stackCount >= 1 {
                            collapsedBackCard(level: 1)
                        }
                    }
                )
                // 为底部的叠页预留空间
                .padding(.bottom, !isExpanded && stackCount > 0 ? CGFloat(stackCount * 8) : 0)
                .animation(.easeOut(duration: 0.2), value: isExpanded)
            } else {
                EmptyView()
            }
        }
        .task {
            await refreshNotificationAuthStatus()
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                Task { await refreshNotificationAuthStatus() }
            }
        }
    }

    private func collapsedBackCard(level: Int) -> some View {
        // level: 1（靠近顶层） / 2（最底层）
        let y: CGFloat = (level == 1) ? 8 : 16 // 增大偏移，露出更多
        let scale: CGFloat = (level == 1) ? 0.97 : 0.94
        let alpha: CGFloat = (level == 1) ? 0.92 : 0.84
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(alpha))
            .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
            .offset(y: y)
            .scaleEffect(scale)
            .allowsHitTesting(false)
    }

    private func expandedEvents() -> [ScheduleEvent] {
        if hasError, events.isEmpty {
            return [ScheduleEvent(title: "今日日程获取失败，请稍后重试", description: "", startTime: Date(), endTime: Date())]
        }
        if events.isEmpty {
            return []
        }
        return events.sorted { $0.startTime < $1.startTime }
    }
    
    private func rowView(event: ScheduleEvent) -> some View {
        HStack(spacing: 8) { // 减小间距，更紧凑
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "999999"))
            
            Text(formatTime(event.startTime))
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "BBBBBB"))
            
            Text(titleText(for: event))
                .font(.system(size: 15))
                .foregroundColor(primaryGray)
                .lineLimit(1)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 48) // 固定行高，确保展开和折叠状态一致
    }
    
    private var footerView: some View {
        Text("以上为今日日程")
            .font(.system(size: 14))
            .foregroundColor(Color(hex: "999999"))
    }

    private var shouldShowNotificationPermissionHint: Bool {
        // 只有“确实存在提醒”的情况下才提示，避免打扰
        let hasReminder = events.contains { ev in
            let raw = (ev.reminderTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !raw.isEmpty
        }
        guard hasReminder else { return false }
        guard let s = notificationAuthStatus else { return false }
        return !(s == .authorized || s == .provisional || s == .ephemeral)
    }

    private var notificationPermissionHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "999999"))

            Text("系统通知未开启，日程提醒不会弹出")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "666666"))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                Task { await handleEnableNotificationsTap() }
            } label: {
                Text(enableButtonTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "333333"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
        .padding(.horizontal, 1)
    }

    private var enableButtonTitle: String {
        switch notificationAuthStatus {
        case .denied:
            return "去设置"
        case .notDetermined:
            return "开启"
        default:
            return "开启"
        }
    }
    
    private var collapseButton: some View {
        Button(action: {
            HapticFeedback.heavy()
            isExpanded = false
        }) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "999999"))
                .frame(width: 48, height: 26)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    private func titleText(for event: ScheduleEvent) -> String {
        let t = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasError, events.isEmpty {
            return "今日日程获取失败"
        }
        return t
    }
    
    // MARK: - Formatting
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Notification permission
    private func refreshNotificationAuthStatus() async {
        let status = await CalendarManager.shared.notificationAuthorizationStatus()
        await MainActor.run {
            notificationAuthStatus = status
        }
    }

    @MainActor
    private func handleEnableNotificationsTap() async {
        let status = await CalendarManager.shared.notificationAuthorizationStatus()
        notificationAuthStatus = status

        switch status {
        case .notDetermined:
            _ = await CalendarManager.shared.requestNotificationPermission()
            await refreshNotificationAuthStatus()
        case .denied:
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            #endif
        default:
            // 其它状态：不处理
            break
        }
    }
}


