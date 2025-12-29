import SwiftUI

/// 首页顶部"今日日程通知栏"（折叠/展开）
/// - 折叠：展示一条（优先显示"当前时间之后最近的一条"，否则显示当天第一条）
/// - 展开：展示当日全部日程列表 + "以上为今日日程 / 全部已读" + 收起按钮
struct TodayScheduleNotificationBar: View {
    let events: [ScheduleEvent]
    let isLoading: Bool
    let errorText: String?
    
    @Binding var isExpanded: Bool
    
    var onTapMarkAllRead: (() -> Void)? = nil
    var onTapRow: ((ScheduleEvent) -> Void)? = nil
    
    // 主题色（与 ChatView 统一）
    private let primaryGray = Color(hex: "333333")
    private let secondaryGray = Color(hex: "666666")
    
    /// 所有日程（排序后）
    private var allEvents: [ScheduleEvent] {
        expandedEvents()
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
        // 加载中或无数据但正在请求时，也显示叠层效果
        if isLoading && events.isEmpty {
            return 1 // 一层背景叠层，加上主卡片共两层
        }
        let n = allEvents.count
        if n <= 1 { return 0 }
        return min(1, n - 1) // 最多一层背景叠层
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 日程行列表
            VStack(spacing: 10) { // 各个卡片之间的间距
                if isExpanded {
                    // 展开：显示所有日程，每个日程都是独立白卡
                    ForEach(Array(allEvents.enumerated()), id: \.element.id) { idx, e in
                        rowView(event: e, showsReadPill: true)
                            .background(cardBackground) // 每个项目独立白底
                            .contentShape(Rectangle())
                            .onTapGesture { onTapRow?(e) }
                    }
                } else {
                    // 折叠：只显示一条
                    if let e = collapsedEvent {
                        rowView(event: e, showsReadPill: false)
                            .background(cardBackground)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isExpanded = true
                            }
                    }
                }
            }
            
            // 展开时的底部区域（footer + 收起按钮）
            if isExpanded {
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
        if isLoading && events.isEmpty {
            return [ScheduleEvent(title: "正在从后端同步今日日程…", description: "", startTime: Date(), endTime: Date())]
        }
        if let errorText, !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, events.isEmpty {
            return [ScheduleEvent(title: "今日日程获取失败，请稍后重试", description: "", startTime: Date(), endTime: Date())]
        }
        if events.isEmpty {
            // 无日程占位：保持和“有日程”同样的一行样式
            return [ScheduleEvent(title: "今日暂无日程，安排一下更高效", description: "", startTime: Date(), endTime: Date())]
        }
        return events.sorted { $0.startTime < $1.startTime }
    }
    
    private func rowView(event: ScheduleEvent, showsReadPill: Bool) -> some View {
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
            
            if showsReadPill {
                readPill
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48) // 固定行高，确保展开和折叠状态一致
    }
    
    private var readPill: some View {
        Text("已读")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(secondaryGray)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: "F2F3F5")) // 浅灰色按钮背景
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private var footerView: some View {
        HStack(spacing: 16) {
            Text("以上为今日日程")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "999999"))
            
            Button(action: {
                HapticFeedback.light()
                onTapMarkAllRead?()
            }) {
                Text("全部已读")
                    .font(.system(size: 14))
                    .foregroundColor(primaryGray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var collapseButton: some View {
        Button(action: {
            HapticFeedback.light()
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
        if isLoading, events.isEmpty { return "正在同步今日日程…" }
        if let errorText, !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, events.isEmpty {
            return "今日日程获取失败"
        }
        return t.isEmpty ? "今日暂无日程" : t
    }
    
    // MARK: - Formatting
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}


