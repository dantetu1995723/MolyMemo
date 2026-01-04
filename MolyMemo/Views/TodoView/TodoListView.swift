import SwiftUI
import SwiftData
import UIKit

// MARK: - 滚动偏移 PreferenceKey
private struct TodoListScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 后端日程行样式（轻量）
private struct RemoteScheduleRow: View {
    let event: ScheduleEvent
    var isDeleting: Bool = false
    var onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            timePill()
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.88))
                        .lineLimit(1)
                    
                    Spacer(minLength: 0)
                    
                    if !event.endTimeProvided {
                        Text("未设置结束")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black.opacity(0.45))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.04))
                            .clipShape(Capsule())
                    }
                }
                
                if !event.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(event.description)
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // 现代感删除按钮：直接内置
            deleteButton
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(cardBackground())
        .overlay(cardBorder())
    }

    @ViewBuilder
    private var deleteButton: some View {
        ZStack {
            if isDeleting {
                ProgressView()
                    .tint(.red)
                    .scaleEffect(0.8)
            } else {
                Button {
                    HapticFeedback.medium()
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 32)
        .padding(.leading, 4)
    }
    
    private func timePill() -> some View {
        VStack(spacing: 4) {
            Text(formatTime(event.startTime))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.88))
            
            if let end = displayEndTime() {
                Text(end)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.5))
            } else {
                Text("开始")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.45))
            }
        }
        .frame(width: 66)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.black.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 5)
    }
    
    private func cardBorder() -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.9), Color.black.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    private func displayEndTime() -> String? {
        guard event.endTimeProvided else { return nil }
        return formatTime(event.endTime)
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// 待办事项列表主界面 - 全新设计
struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Query(sort: \TodoItem.startTime) private var allTodos: [TodoItem]
    
    // 外部绑定的添加弹窗状态（由底部tab栏控制）
    @Binding var showAddSheet: Bool
    @State private var selectedTodo: TodoItem?
    @State private var editingTodo: TodoItem?
    @State private var pendingDeleteTodo: TodoItem?
    @State private var showDeleteConfirmation = false
    @State private var showContent = false
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    
    // 日历折叠进度：0 = 完全展开（月视图），1 = 完全折叠（周视图）
    @State private var calendarProgress: CGFloat = 0
    
    // 列表滚动位置
    @State private var listScrollOffset: CGFloat = 0
    @State private var isListAtBottom: Bool = false
    
    // 拖拽临时状态
    @State private var dragStartProgress: CGFloat?
    @State private var didInitialize = false
    
    // MARK: - 后端日程（/api/v1/schedules）
    @State private var remoteEvents: [ScheduleEvent] = []
    @State private var remoteIsLoading: Bool = false
    @State private var remoteErrorText: String? = nil
    @State private var remoteDetailSelection: ScheduleEvent? = nil
    
    // 追踪正在删除的日程 ID（用于显示行内 loading）
    @State private var deletingRemoteIds: Set<String> = []
    
    init(showAddSheet: Binding<Bool> = .constant(false)) {
        self._showAddSheet = showAddSheet
    }
    
    // 行程主题色 - 统一灰色调
    private let scheduleAccentColor = Color(white: 0.35)
    private let scheduleBackgroundColor = Color(white: 0.92)
    private let scheduleGlowColor = Color(white: 0.85)
    
    // 背景色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    // 当前选中日期的全部事项
    private var currentDayTodos: [TodoItem] {
        let calendar = Calendar.current
        return allTodos.filter { todo in
            calendar.isDate(todo.startTime, inSameDayAs: selectedDate)
        }.sorted { $0.startTime < $1.startTime }
    }
    
    // 全天事项
    private var allDayTodos: [TodoItem] {
        currentDayTodos.filter { $0.isAllDay }
    }
    
    // 有时间的事项
    private var timedTodos: [TodoItem] {
        currentDayTodos.filter { !$0.isAllDay }
    }
    
    // 动态计算日历高度
    private var currentCalendarHeight: CGFloat {
        let monthHeight = monthViewHeight
        let weekHeight: CGFloat = 52 // 周视图高度
        return monthHeight - (monthHeight - weekHeight) * calendarProgress
    }
    
    var body: some View {
        ZStack {
            // 渐变背景
            ModuleBackgroundView(themeColor: themeColor)
            
            VStack(spacing: 0) {
                // 顶部导航栏
                calendarNavigationBar()
                
                // 星期标题行（固定在顶部）
                weekdayHeader()
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.01))
                
                // 日历区域（高度动态变化）
                AdaptiveCalendarView(
                    currentMonth: $currentMonth,
                    selectedDate: $selectedDate,
                    progress: calendarProgress,
                    height: currentCalendarHeight
                )
                .frame(height: currentCalendarHeight)
                .padding(.horizontal, 16)
                .clipped()
                .zIndex(1)
                
                // 日程列表区域
                ScrollView {
                    VStack(spacing: 0) {
                        // 顶部探测器，用于检测滚动位置
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TodoListScrollOffsetKey.self,
                                value: proxy.frame(in: .named("listScroll")).minY
                            )
                        }
                        .frame(height: 0)
                        
                        // 今日行程标题
                        todayScheduleHeader()
                        
                        // 行程列表
                        scheduleListSectionContent()
                    }
                }
                .coordinateSpace(name: "listScroll")
                .onPreferenceChange(TodoListScrollOffsetKey.self) { offset in
                    listScrollOffset = offset
                }
                // 只有在日历折叠（周视图）时才允许列表滚动，
                // 或者列表已经滚下去了一点（offset < 0）时允许滚动回来
                // 这样在月视图下，手指滑动会优先触发日历折叠
                .scrollDisabled(calendarProgress < 1.0 && listScrollOffset >= 0)
            }
            // 整体手势监听：用于“上滑折叠月历/下拉展开月历”
            //
            // 之前这里使用 highPriorityGesture + including: .all，会把子视图（尤其是日历 TabView 的 page 横滑）
            // 的单指手势抢走，导致“翻月必须双指”。
            //
            // 改为 simultaneousGesture：不阻塞子视图手势，只在 handleDragChange/End 内部按需处理“纵向”拖拽即可。
            .simultaneousGesture(
                // 关键：这里一定要设置 minimumDistance。
                // 否则用户“点击列表项”时手指的轻微抖动也会被识别成拖拽，
                // 进而导致 SwipeToDeleteCard 的 onTap（打开详情）经常不触发，体感就是“点不进去详情”。
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        handleDragChange(value)
                    }
                    .onEnded { value in
                        handleDragEnd(value)
                    }
            )
            
            // 底部操作栏（选中事项时显示）
            if selectedTodo != nil {
                VStack {
                    Spacer()
                    actionBar()
                        .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedTodo != nil)
        .sheet(isPresented: $showAddSheet) {
            TodoEditView(defaultStartTime: selectedDate)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTodo, onDismiss: {
            selectedTodo = nil
        }) { todo in
            TodoEditView(todo: todo)
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "删除日程",
            isPresented: $showDeleteConfirmation,
            presenting: pendingDeleteTodo
        ) { todo in
            Button("删除", role: .destructive) {
                deleteTodo(todo)
            }
            Button("取消", role: .cancel) {
                pendingDeleteTodo = nil
            }
        } message: { _ in
            Text("删除后不可恢复")
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !didInitialize {
                didInitialize = true
                let today = Date()
                selectedDate = today
                let calendar = Calendar.current
                if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) {
                    currentMonth = monthStart
                } else {
                    currentMonth = today
                }
            }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                showContent = true
            }

            // 进入工具箱「日程」页即自动刷新（无需按钮）
            Task { await reloadRemoteSchedulesForSelectedDate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteScheduleDidChange).receive(on: RunLoop.main)) { _ in
            // 统一以“后端列表”为准：收到变更通知后直接强刷
            Task { await reloadRemoteSchedulesForSelectedDate(forceRefresh: true) }
        }
        .onChange(of: selectedDate) { _, _ in
            // 切换日期时自动刷新对应日程
            Task { await reloadRemoteSchedulesForSelectedDate() }
        }
        .sheet(item: $remoteDetailSelection) { _ in
            RemoteScheduleDetailLoaderSheet(
                event: $remoteDetailSelection,
                onCommittedSave: { updated in
                    applyRemoteEventUpdate(updated)
                },
                onCommittedDelete: { deleted in
                    applyRemoteEventDelete(deleted)
                }
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - 拖拽手势处理
    private func handleDragChange(_ value: DragGesture.Value) {
        let verticalTranslation = value.translation.height
        let horizontalTranslation = value.translation.width
        
        // 关键修复：
        // 这里需要“放行横滑”给 SwipeToDeleteCard（左滑删除），但如果判定过于敏感，
        // 用户在列表项上做“上下拖拽切换周/月”时会因为轻微横向抖动而被误判为横滑，导致折叠/展开失效。
        //
        // 因此仅在“横向明显占优 + 横向位移也足够大”时才放行。
        if dragStartProgress == nil {
            let horizontalDominant = abs(horizontalTranslation) > abs(verticalTranslation) + 18
            let horizontalIsMeaningful = abs(horizontalTranslation) > 24
            if horizontalDominant && horizontalIsMeaningful {
                return
            }
        }
        
        // ✅ 反向操作：周视图 + 列表到底部时，继续下拉（回弹）允许展开月历
        let canExpandFromBottomBounce = (calendarProgress >= 0.999 && isListAtBottom && verticalTranslation > 0)
        
        // 列表不在顶部时，不允许继续收缩或展开
        if !canExpandFromBottomBounce, listScrollOffset < -5 && verticalTranslation < 0 {
            dragStartProgress = nil
            return
        }
        
        if !canExpandFromBottomBounce, verticalTranslation > 0 && listScrollOffset < -2 {
            dragStartProgress = nil
            return
        }

        if dragStartProgress == nil {
            dragStartProgress = calendarProgress
        }
        
        // 向上滑 (translation < 0) -> progress 增加 (趋向1)
        // 向下滑 (translation > 0) -> progress 减小 (趋向0)
        let sensitivity: CGFloat = 260
        var newProgress = (dragStartProgress ?? calendarProgress) - verticalTranslation / sensitivity
        newProgress = max(0, min(1, newProgress))
        
        guard abs(newProgress - calendarProgress) > 0.001 else { return }
        
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.85)) {
            calendarProgress = newProgress
        }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        dragStartProgress = nil
        
        // 决定最终停靠点
        let velocity = value.predictedEndTranslation.height - value.translation.height
        let threshold: CGFloat = 0.3
        
        let targetProgress: CGFloat
        
        if velocity < -150 { // 快速上滑
            targetProgress = 1.0
        } else if velocity > 150 && (listScrollOffset >= 0 || (calendarProgress >= 0.999 && isListAtBottom)) { // 快速下滑：列表在顶 或 列表在底部回弹
            targetProgress = 0.0
        } else {
            // 就近停靠
            targetProgress = calendarProgress > 0.5 ? 1.0 : 0.0
        }
        
        // 如果列表不在顶部且是下滑操作，不要强制展开日历
        if listScrollOffset < -10 && targetProgress == 0.0 && !(calendarProgress >= 0.999 && isListAtBottom) {
             return
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            calendarProgress = targetProgress
        }
    }
    
    // MARK: - 远端日程（回写列表）
    
    private func isSameRemote(_ a: ScheduleEvent, _ b: ScheduleEvent) -> Bool {
        let ra = (a.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rb = (b.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ra.isEmpty, !rb.isEmpty { return ra == rb }
        return a.id == b.id
    }
    
    @MainActor
    private func applyRemoteEventUpdate(_ updated: ScheduleEvent) {
        if let idx = remoteEvents.firstIndex(where: { isSameRemote($0, updated) }) {
            remoteEvents[idx] = updated
        } else {
            remoteEvents.append(updated)
        }
        remoteEvents.sort(by: { $0.startTime < $1.startTime })
        remoteDetailSelection = updated
    }
    
    @MainActor
    private func applyRemoteEventDelete(_ deleted: ScheduleEvent) {
        remoteEvents.removeAll(where: { isSameRemote($0, deleted) })
        if let current = remoteDetailSelection, isSameRemote(current, deleted) {
            remoteDetailSelection = nil
        }
    }
    
    // MARK: - 顶部导航栏
    private func calendarNavigationBar() -> some View {
        ZStack {
            // 标题永远在容器几何中心（不受左侧按钮宽度影响）
            Text(monthTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
                // 预留两侧按钮区域，避免标题与返回按钮发生视觉重叠
                .padding(.horizontal, 60)
                .frame(maxWidth: .infinity, alignment: .center)
            
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(width: 44, height: 44, alignment: .center)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.01))
    }
    
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: currentMonth)
    }
    
    // 星期标题行
    private func weekdayHeader() -> some View {
        let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Text(weekdays[index])
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 52)
    }
    
    // MARK: - 今日行程标题
    private func todayScheduleHeader() -> some View {
        HStack {
            Text("今日行程")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - 行程列表内容
    private func scheduleListSectionContent() -> some View {
        LazyVStack(spacing: 12) {
            // 后端加载态/错误提示（无需按钮刷新）
            if remoteIsLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("正在从后端获取日程…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            
            if let remoteErrorText {
                Text(remoteErrorText)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            
            if remoteErrorText == nil {
                if !remoteEvents.isEmpty {
                    ForEach(remoteEvents) { e in
                        let rid = e.remoteId ?? ""
                        RemoteScheduleRow(
                            event: e,
                            isDeleting: deletingRemoteIds.contains(rid),
                            onDelete: {
                                requestDeleteRemoteEvent(e)
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticFeedback.light()
                            remoteDetailSelection = e
                        }
                    }
                } else if !remoteIsLoading {
                    Text("暂无后端日程")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                }
            } else {
                // 后端失败兜底：展示本地日程（避免空白）
                
                // 全天事项
                ForEach(allDayTodos) { todo in
                    SwipeToDeleteCard(
                        onTap: { presentEditor(for: todo) },
                        onDelete: { promptDelete(for: todo) }
                    ) {
                        UnifiedScheduleRow(
                            todo: todo,
                            isSelected: selectedTodo?.id == todo.id,
                            isAllDay: true,
                            accentColor: scheduleAccentColor,
                            backgroundColor: scheduleBackgroundColor,
                            glowColor: scheduleGlowColor
                        )
                    }
                }
                
                // 带时间的事项
                let items = timedTodos
                ForEach(Array(items.enumerated()), id: \.element.id) { index, todo in
                    // 检测重叠：如果上一项的结束时间晚于当前项的开始时间
                    let isOverlapping = index > 0 && items[index - 1].endTime > todo.startTime
                    
                    SwipeToDeleteCard(
                        onTap: { presentEditor(for: todo) },
                        onDelete: { promptDelete(for: todo) }
                    ) {
                        UnifiedScheduleRow(
                            todo: todo,
                            isSelected: selectedTodo?.id == todo.id,
                            accentColor: scheduleAccentColor,
                            backgroundColor: scheduleBackgroundColor,
                            glowColor: scheduleGlowColor,
                            isOverlapping: isOverlapping
                        )
                    }
                }
                
                // 空状态（仅兜底分支）
                if currentDayTodos.isEmpty {
                    EmptyScheduleView()
                        .padding(.top, 40)
                }
            }
            
            // 底部哨兵：用于识别“列表已到底部”，配合周视图的“下拉回弹”手势实现 周 -> 月
            Color.clear
                .frame(height: 1)
                .onAppear { isListAtBottom = true }
                .onDisappear { isListAtBottom = false }
        }
        .padding(.horizontal, 16) // 统一水平内边距
        .padding(.bottom, 160)
    }

    // MARK: - 后端拉取（按当前选中日期过滤）
    @MainActor
    private func reloadRemoteSchedulesForSelectedDate(forceRefresh: Bool = false) async {
        remoteErrorText = nil
        
        // 不设置日期范围，获取所有日程
        let base = ScheduleService.ListParams(
            page: nil,
            pageSize: nil,
            startDate: nil,
            endDate: nil,
            search: nil,
            category: nil,
            relatedMeetingId: nil
        )
        
        // 强制刷新：绕过缓存，直接从网络拉
        if forceRefresh {
            await reloadRemoteSchedulesForSelectedDateFromNetwork(base: base, showError: true, forceRefresh: true)
            return
        }
        
        // 1) 先用缓存秒开（避免切换日期/返回页面就必定 loading）
        // 注意：peekAllSchedules 的 maxPages 参数只用于缓存 key，实际获取时会循环直到没有更多数据
        if let cached = await ScheduleService.peekAllSchedules(maxPages: 10000, pageSize: 100, baseParams: base) {
            let cal = Calendar.current
            remoteEvents = cached.value
                .filter { cal.isDate($0.startTime, inSameDayAs: selectedDate) }
                .sorted(by: { $0.startTime < $1.startTime })
            
            // 即使缓存新鲜，也后台静默刷新，确保数据及时更新
            Task { @MainActor in
                await reloadRemoteSchedulesForSelectedDateFromNetwork(base: base, showError: false, forceRefresh: true)
            }
            return
        }
        
        // 2) 首次无缓存：显示 loading
        await reloadRemoteSchedulesForSelectedDateFromNetwork(base: base, showError: true, forceRefresh: false)
    }
    
    @MainActor
    private func reloadRemoteSchedulesForSelectedDateFromNetwork(base: ScheduleService.ListParams, showError: Bool, forceRefresh: Bool) async {
        remoteIsLoading = true
        defer { remoteIsLoading = false }
        
        do {
            // 不限制页数，循环获取直到没有更多数据
            let all = try await ScheduleService.fetchScheduleListAllPages(
                maxPages: Int.max,
                pageSize: 100,
                baseParams: base,
                forceRefresh: forceRefresh
            )
            let cal = Calendar.current
            remoteEvents = all
                .filter { cal.isDate($0.startTime, inSameDayAs: selectedDate) }
                .sorted(by: { $0.startTime < $1.startTime })
        } catch {
            remoteEvents = []
            if showError {
                remoteErrorText = "后端日程获取失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 左滑删除（后端日程）
    private func requestDeleteRemoteEvent(_ event: ScheduleEvent) {
        let rid = event.remoteId ?? ""
        guard !rid.isEmpty else { return }

        Task { @MainActor in
            deletingRemoteIds.insert(rid)
            defer { deletingRemoteIds.remove(rid) }
            
            do {
                try await DeleteActions.deleteRemoteSchedule(event)
                applyRemoteEventDelete(event)
            } catch {
                // 不做 UI 兜底提示，只打印，方便定位后端 404 的原因
                print("❌ [TodoListView:deleteRemoteEvent] title=\(event.title) remoteId=\(rid) error=\(error)")
            }
        }
    }

    private func formatYMD(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    
    // MARK: - 底部操作栏
    private func actionBar() -> some View {
        HStack(spacing: 0) {
            // 编辑按钮
            Button(action: {
                if let todo = selectedTodo {
                    HapticFeedback.selection()
                    editingTodo = todo
                }
            }) {
                Text("编辑")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.black.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            
            // 分隔线
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 1, height: 20)
            
            // 引用按钮
            Button(action: {
                if let todo = selectedTodo {
                    copyTodoInfo(todo)
                }
            }) {
                Text("引用")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.black.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 100)
    }
    
    // 复制待办信息
    private func copyTodoInfo(_ todo: TodoItem) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        var text = "📅 \(todo.title)\n"
        text += "⏰ \(formatter.string(from: todo.startTime))"
        formatter.dateFormat = "HH:mm"
        text += " - \(formatter.string(from: todo.endTime))"
        if !todo.taskDescription.isEmpty {
            text += "\n📝 \(todo.taskDescription)"
        }
        UIPasteboard.general.string = text
        HapticFeedback.success()
    }
    
    private func presentEditor(for todo: TodoItem) {
        HapticFeedback.light()
        selectedTodo = todo
        editingTodo = todo
    }
    
    private func promptDelete(for todo: TodoItem) {
        HapticFeedback.medium()
        pendingDeleteTodo = todo
        showDeleteConfirmation = true
    }
    
    private func deleteTodo(_ todo: TodoItem) {
        modelContext.delete(todo)
        do {
            try modelContext.save()
            HapticFeedback.success()
        } catch {
            HapticFeedback.error()
        }
        
        if selectedTodo?.id == todo.id {
            selectedTodo = nil
        }
        if editingTodo?.id == todo.id {
            editingTodo = nil
        }
        
        pendingDeleteTodo = nil
        showDeleteConfirmation = false
    }
    
    // 注意：不再创建任何“示例待办”，避免污染用户真实数据。
    
    // 计算月视图高度
    private var monthViewHeight: CGFloat {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return 280
        }
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let totalCells = range.count + firstWeekday - 1
        let rows = (totalCells + 6) / 7
        return CGFloat(rows) * 52 // 行高调整为52
    }
    
    // 生成月份范围（前后12个月）
    private func monthsRange() -> [Date] {
        let calendar = Calendar.current
        var months: [Date] = []
        for i in -12...12 {
            if let month = calendar.date(byAdding: .month, value: i, to: Date()) {
                let components = calendar.dateComponents([.year, .month], from: month)
                if let normalizedMonth = calendar.date(from: components) {
                    months.append(normalizedMonth)
                }
            }
        }
        return months
    }
}

// MARK: - 自适应日历视图（核心组件）
struct AdaptiveCalendarView: View {
    @Binding var currentMonth: Date
    @Binding var selectedDate: Date
    let progress: CGFloat // 0=月视图, 1=周视图
    let height: CGFloat
    
    var body: some View {
        // 使用 TabView 支持左右滑动切换月份
        TabView(selection: $currentMonth) {
            ForEach(monthsRange(), id: \.self) { month in
                AdaptiveMonthGrid(
                    month: month,
                    selectedDate: $selectedDate,
                    progress: progress
                )
                .tag(month)
                // 关键：在 TabView 中让内容顶部对齐，以配合高度变化
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
    
    private func monthsRange() -> [Date] {
        let calendar = Calendar.current
        var months: [Date] = []
        for i in -12...12 {
            if let month = calendar.date(byAdding: .month, value: i, to: Date()) {
                let components = calendar.dateComponents([.year, .month], from: month)
                if let normalizedMonth = calendar.date(from: components) {
                    months.append(normalizedMonth)
                }
            }
        }
        return months
    }
}

struct AdaptiveMonthGrid: View {
    let month: Date
    @Binding var selectedDate: Date
    let progress: CGFloat
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let rowHeight: CGFloat = 52
    
    var body: some View {
        GeometryReader { geometry in
            let days = daysInMonth
            let totalRows = (days.count + 6) / 7
            let selectedRowIndex = getSelectedRowIndex(days: days)
            
            ForEach(0..<totalRows, id: \.self) { rowIndex in
                // 计算每一行的位置
                // 1. 在月视图中的原始 Y 坐标
                let monthY = CGFloat(rowIndex) * rowHeight
                
                // 2. 在周视图中的目标 Y 坐标
                // 选中行移动到 0，其他行也移动到 0（并淡出）
                let weekY: CGFloat = 0
                
                // 3. 插值计算当前 Y 坐标
                // 注意：我们希望选中行始终保持在最上层，并且平滑移动到顶部
                // 实际上，所有行都应该向上移动 `selectedRowIndex * rowHeight * progress` 的距离
                // 这样选中行就正好到了顶部
                let offsetY = -CGFloat(selectedRowIndex) * rowHeight * progress
                
                let currentY = monthY + offsetY
                
                // 计算透明度
                // 选中行始终为 1
                // 其他行：1 -> 0
                let opacity = rowIndex == selectedRowIndex ? 1.0 : max(0, 1.0 - progress * 1.5)
                
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { colIndex in
                        let index = rowIndex * 7 + colIndex
                        if index < days.count, let date = days[index] {
                            CalendarDayCellNew(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                                isToday: Calendar.current.isDateInToday(date),
                                isCurrentMonth: Calendar.current.isDate(date, equalTo: month, toGranularity: .month)
                            )
                            .onTapGesture {
                                HapticFeedback.light()
                                selectedDate = date
                            }
                        } else {
                            Color.clear.frame(height: rowHeight)
                        }
                    }
                }
                .frame(height: rowHeight)
                .position(x: geometry.size.width / 2, y: currentY + rowHeight / 2)
                .opacity(opacity)
            }
        }
    }
    
    // 获取当月所有日期（包含填充）
    private var daysInMonth: [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
            let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }
        
        var dates: [Date?] = []
        var currentDate = monthFirstWeek.start
        
        // 填充直到下个月开始且填满整周
        while currentDate < monthInterval.end || dates.count % 7 != 0 {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dates
    }
    
    // 获取选中日期所在的行索引
    private func getSelectedRowIndex(days: [Date?]) -> Int {
        let calendar = Calendar.current
        for (index, maybeDate) in days.enumerated() {
            if let date = maybeDate, calendar.isDate(date, inSameDayAs: selectedDate) {
                return index / 7
            }
        }
        // 如果选中日期不在当前月份视图中（切换月份时），
        // 尝试找到今天所在的行，或者默认第一行
        for (index, maybeDate) in days.enumerated() {
            if let date = maybeDate, calendar.isDateInToday(date) {
                return index / 7
            }
        }
        return 0
    }
    
    // 注意：日历日期不再根据“是否有待办”做任何变色/标记。
}

// MARK: - 日历日期单元格（新设计）
struct CalendarDayCellNew: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    
    var body: some View {
        ZStack {
            selectionBackground
            
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                .foregroundColor(textColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
    }
    
    private var textColor: Color {
        if isSelected {
            return .black.opacity(0.85)
        } else if !isCurrentMonth {
            return .black.opacity(0.25)
        } else {
            return .black.opacity(0.8)
        }
    }
    
    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            LiquidGlassCircle()
                .frame(width: 44, height: 44)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else if isToday {
            Circle()
                .strokeBorder(Color.black.opacity(0.6), lineWidth: 2)
                .frame(width: 36, height: 36)
        } else {
            Circle()
                .fill(Color.clear)
                .frame(width: 36, height: 36)
        }
    }
}

// MARK: - Liquid Glass Selection
private struct LiquidGlassCircle: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .blur(radius: 6)
                    .offset(y: 5)
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .blendMode(.screen)
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 14, height: 10)
                    .blur(radius: 1.8)
                    .offset(x: 6, y: 6)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .blur(radius: 1.5)
                    .offset(x: -6, y: -6)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            .compositingGroup()
    }
}

// MARK: - 统一化行程行设计 (Unified Schedule Row)
struct UnifiedScheduleRow: View {
    let todo: TodoItem
    let isSelected: Bool
    var isAllDay: Bool = false
    let accentColor: Color
    let backgroundColor: Color
    let glowColor: Color
    var isOverlapping: Bool = false
    
    private let cornerRadius: CGFloat = 16
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    private var startTimeText: String {
        Self.timeFormatter.string(from: todo.startTime)
    }
    
    private var endTimeText: String {
        Self.timeFormatter.string(from: todo.endTime)
    }
    
    // 主题色背景
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        backgroundColor.opacity(isSelected ? 0.95 : 0.75),
                        backgroundColor.opacity(0.45)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: glowColor.opacity(isSelected ? 0.35 : 0.15), radius: isSelected ? 16 : 10, x: 0, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? accentColor : accentColor.opacity(0.3), lineWidth: isSelected ? 2 : 0.5)
            )
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：时间面板 (一体化设计，内嵌在卡片左侧)
            VStack(alignment: .center, spacing: 4) {
                if isAllDay {
                    Text("全天")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                } else {
                    Text(startTimeText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    // 视觉连接线
                    Capsule()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 2, height: 16)
                    
                    Text(endTimeText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.9))
                }
            }
            .frame(width: 66)
            .frame(maxHeight: .infinity) // 撑满高度
            .background(
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.95),
                        accentColor.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // 右侧：信息面板
            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(1)
                
                if !todo.taskDescription.isEmpty {
                    Text(todo.taskDescription)
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 80) // 保证最小高度
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // 如果重叠，稍微向内缩进并调整透明度，形成层叠感
        .padding(.top, isOverlapping ? -10 : 0) // 视觉重叠
        .scaleEffect(isOverlapping ? 0.98 : 1.0) // 稍微缩小
        .zIndex(isOverlapping ? 0 : 1) // 保证正确的层级覆盖（这里反向，新的在下？）通常List是顺序渲染
    }
}

// MARK: - 空状态视图
struct EmptyScheduleView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.black.opacity(0.15))
            
            Text("暂无日程安排")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black.opacity(0.4))
        }
    }
}
