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
    
    // 拖拽临时状态
    @State private var dragStartProgress: CGFloat?
    @State private var didInitialize = false
    
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
                    todos: allTodos,
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
            // 整体手势监听（优先级提升，保证周视图可顺利展开）
            .highPriorityGesture(
                DragGesture()
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
            
            createSampleTodoIfNeeded()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                showContent = true
            }
        }
    }
    
    // MARK: - 拖拽手势处理
    private func handleDragChange(_ value: DragGesture.Value) {
        let verticalTranslation = value.translation.height
        
        // 列表不在顶部时，不允许继续收缩或展开
        if listScrollOffset < -5 && verticalTranslation < 0 {
            dragStartProgress = nil
            return
        }
        
        if verticalTranslation > 0 && listScrollOffset < -2 {
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
        } else if velocity > 150 && listScrollOffset >= 0 { // 快速下滑且列表在顶
            targetProgress = 0.0
        } else {
            // 就近停靠
            targetProgress = calendarProgress > 0.5 ? 1.0 : 0.0
        }
        
        // 如果列表不在顶部且是下滑操作，不要强制展开日历
        if listScrollOffset < -10 && targetProgress == 0.0 {
             return
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            calendarProgress = targetProgress
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
            
            // 空状态
            if currentDayTodos.isEmpty {
                EmptyScheduleView()
                    .padding(.top, 40)
            }
        }
        .padding(.horizontal, 16) // 统一水平内边距
        .padding(.bottom, 160)
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
    
    // 创建示例待办
    private func createSampleTodoIfNeeded() {
        guard allTodos.isEmpty else { return }
        
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let startTime = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let endTime = Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        
        let sampleTodo = TodoItem(
            title: "项目周会",
            taskDescription: "讨论本周工作进展和下周计划",
            startTime: startTime,
            endTime: endTime
        )
        
        modelContext.insert(sampleTodo)
        try? modelContext.save()
    }
    
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
    let todos: [TodoItem]
    let progress: CGFloat // 0=月视图, 1=周视图
    let height: CGFloat
    
    var body: some View {
        // 使用 TabView 支持左右滑动切换月份
        TabView(selection: $currentMonth) {
            ForEach(monthsRange(), id: \.self) { month in
                AdaptiveMonthGrid(
                    month: month,
                    selectedDate: $selectedDate,
                    todos: todos,
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
    let todos: [TodoItem]
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
                                hasTodos: hasTodos(on: date),
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
    
    private func hasTodos(on date: Date) -> Bool {
        let calendar = Calendar.current
        return todos.contains { calendar.isDate($0.startTime, inSameDayAs: date) }
    }
}

// MARK: - 日历日期单元格（新设计）
struct CalendarDayCellNew: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasTodos: Bool
    let isCurrentMonth: Bool
    
    private let selectionColor = Color(red: 0.95, green: 0.75, blue: 0.45)
    
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
        } else if hasTodos {
            return selectionColor.opacity(0.95)
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
                .strokeBorder(selectionColor, lineWidth: 2)
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

// MARK: - Swipe to Delete 容器
struct SwipeToDeleteCard<Content: View>: View {
    let onTap: () -> Void
    let onDelete: () -> Void
    private let content: () -> Content
    
    @State private var offsetX: CGFloat = 0
    @State private var isRevealed = false
    @State private var isSwiping = false
    
    private let maxRevealOffset: CGFloat = 110.0
    private let revealThreshold: CGFloat = 70.0
    
    init(
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onTap = onTap
        self.onDelete = onDelete
        self.content = content
    }
    
    private var revealProgress: CGFloat {
        min(1.0, max(0.0, -offsetX / maxRevealOffset))
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // 只有滑动时才显示删除背景
            if offsetX < 0 {
                deleteBackground
                    .opacity(Double(revealProgress))
            }
            
            content()
                .contentShape(Rectangle())
                .offset(x: offsetX)
                .gesture(dragGesture)
                .onTapGesture {
                    if isRevealed {
                        closeSwipe()
                    } else {
                        onTap()
                    }
                }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: offsetX)
    }
    
    private var deleteBackground: some View {
        HStack {
            Spacer()
            
            // 纯图标设计，不使用按钮样式，更符合"非按钮"的描述
            Image(systemName: "trash.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                .scaleEffect(0.8 + 0.2 * revealProgress)
                .padding(.trailing, 36)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.9))
        )
        // 匹配卡片的内边距视觉
        .padding(.vertical, 2) 
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isSwiping {
                    if abs(value.translation.width) > abs(value.translation.height) {
                        isSwiping = true
                    } else {
                        return
                    }
                }
                
                // 允许左滑，限制右滑
                let baseOffset = isRevealed ? -maxRevealOffset : 0
                var newOffset = baseOffset + value.translation.width
                
                if newOffset > 0 {
                    newOffset = newOffset / 4 // 强阻尼右滑
                }
                
                if newOffset < -maxRevealOffset {
                    let extra = newOffset + maxRevealOffset
                    newOffset = -maxRevealOffset + extra / 3 // 左侧阻尼
                }
                
                offsetX = newOffset
            }
            .onEnded { value in
                guard isSwiping else { return }
                defer { isSwiping = false }
                
                let baseOffset = isRevealed ? -maxRevealOffset : 0
                let finalOffset = baseOffset + value.translation.width
                let shouldReveal = -finalOffset > revealThreshold
                let shouldDelete = -finalOffset > maxRevealOffset * 1.5 // 深度滑动直接删除
                
                if shouldDelete {
                     // 触发删除并关闭
                    HapticFeedback.medium()
                    closeSwipe()
                    // 延迟一点执行删除以保证动画流畅
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDelete()
                    }
                } else if shouldReveal {
                    HapticFeedback.light()
                    revealSwipe()
                } else {
                    closeSwipe()
                }
            }
    }
    
    private func revealSwipe() {
        offsetX = -maxRevealOffset
        isRevealed = true
    }
    
    private func closeSwipe() {
        offsetX = 0
        isRevealed = false
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
