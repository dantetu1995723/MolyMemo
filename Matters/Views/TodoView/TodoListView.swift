import SwiftUI
import SwiftData

// 待办事项列表主界面
struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoItem.startTime) private var allTodos: [TodoItem]
    
    @State private var showAddSheet = false
    @State private var selectedTodo: TodoItem?
    @State private var showContent = false
    @State private var showHeader = false
    @State private var showAddButton = false
    @State private var selectedTab: TodoTab = .pending
    
    enum TodoTab {
        case pending
        case completed
    }
    
    // 过滤待办
    private var pendingTodos: [TodoItem] {
        allTodos.filter { !$0.isCompleted }
    }
    
    private var completedTodos: [TodoItem] {
        allTodos.filter { $0.isCompleted }
    }
    
    // 当前显示的待办列表
    private var currentTodos: [TodoItem] {
        selectedTab == .pending ? pendingTodos : completedTodos
    }
    
    var body: some View {
        ZStack {
            // 白色背景
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部标题栏
                if showHeader {
                    TodoHeader(dismiss: dismiss)
                }
                
                // Tab切换器
                if showHeader {
                    TodoTabSelector(
                        selectedTab: $selectedTab,
                        pendingCount: pendingTodos.count,
                        completedCount: completedTodos.count
                    )
                }
                
                // 内容区域
                TodoListContent(
                    showContent: showContent,
                    currentTodos: currentTodos,
                    selectedTab: selectedTab,
                    selectedTodo: $selectedTodo,
                    showAddSheet: $showAddSheet
                )
            }
            
            // 底部浮动添加按钮
            if showAddButton {
                VStack {
                    Spacer()
                    AddTodoButton(showAddSheet: $showAddSheet)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            TodoEditView()
        }
        .sheet(item: $selectedTodo) { todo in
            TodoEditView(todo: todo)
        }
        .navigationBarHidden(true)
        .onAppear {
            // 创建示例待办（仅在第一次打开时）
            createSampleTodoIfNeeded()
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                showHeader = true
            }
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.2)) {
                showContent = true
            }
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.4)) {
                showAddButton = true
            }
        }
    }
    
    // 创建示例待办
    private func createSampleTodoIfNeeded() {
        // 如果已经有待办了，就不创建示例
        guard allTodos.isEmpty else { return }
        
        // 创建一个示例待办
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
}

// MARK: - 子视图组件

// 顶部标题栏
struct TodoHeader: View {
    let dismiss: DismissAction
    
    var body: some View {
        HStack(spacing: 16) {
            // 返回按钮
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                    )
            }
            .buttonStyle(ScaleButtonStyle())
            
            // 标题
            Text("待办事项")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Color.white)
                .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                .shadow(color: Color.black, radius: 0, x: 1, y: 1)
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// Tab切换器
struct TodoTabSelector: View {
    @Binding var selectedTab: TodoListView.TodoTab
    let pendingCount: Int
    let completedCount: Int
    
    var body: some View {
        HStack(spacing: 0) {
            TodoTabButton(
                title: "待办",
                count: pendingCount,
                isSelected: selectedTab == .pending,
                action: {
                    HapticFeedback.light()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        selectedTab = .pending
                    }
                }
            )
            
            TodoTabButton(
                title: "已完成",
                count: completedCount,
                isSelected: selectedTab == .completed,
                action: {
                    HapticFeedback.light()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        selectedTab = .completed
                    }
                }
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

// Tab按钮
struct TodoTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // 标题和数量横向排列
                HStack(spacing: 8) {
                    // 标题
                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: -1, y: -1)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: 1, y: -1)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: -1, y: 1)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: 1, y: 1)
                        .opacity(isSelected ? 1.0 : 0.7)
                    
                    // 数量
                    Text("\(count)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: -1, y: -1)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: 1, y: -1)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: -1, y: 1)
                        .shadow(color: Color.black.opacity(isSelected ? 1.0 : 0.6), radius: 0, x: 1, y: 1)
                        .opacity(isSelected ? 1.0 : 0.7)
                }
                .frame(maxWidth: .infinity)
                
                // 底部指示器
                Rectangle()
                    .fill(isSelected ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.clear)
                    .frame(height: 3)
                    .cornerRadius(1.5)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 列表内容
struct TodoListContent: View {
    let showContent: Bool
    let currentTodos: [TodoItem]
    let selectedTab: TodoListView.TodoTab
    @Binding var selectedTodo: TodoItem?
    @Binding var showAddSheet: Bool
    
    var body: some View {
        ScrollView {
            if showContent {
                if !currentTodos.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(Array(currentTodos.enumerated()), id: \.element.id) { index, todo in
                            TodoCardView(todo: todo)
                                .opacity(selectedTab == .completed ? 0.75 : 1.0)
                                .onTapGesture {
                                    HapticFeedback.light()
                                    selectedTodo = todo
                                }
                                .transition(.scale.combined(with: .opacity))
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.75)
                                    .delay(Double(index) * 0.05),
                                    value: showContent
                                )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 180)
                } else {
                    EmptyTodoListView(
                        isCompleted: selectedTab == .completed,
                        onAddTodo: { showAddSheet = true }
                    )
                    .padding(.top, 60)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

// 添加按钮
struct AddTodoButton: View {
    @Binding var showAddSheet: Bool
    
    var body: some View {
        Button(action: {
            HapticFeedback.medium()
            showAddSheet = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                
                Text("添加待办")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color.white)
            .shadow(color: Color.black, radius: 0, x: -1, y: -1)
            .shadow(color: Color.black, radius: 0, x: 1, y: -1)
            .shadow(color: Color.black, radius: 0, x: -1, y: 1)
            .shadow(color: Color.black, radius: 0, x: 1, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 1.0, blue: 0.25),
                                Color(red: 0.78, green: 0.98, blue: 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.4), radius: 20, x: 0, y: 8)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// 空状态视图
struct EmptyTodoListView: View {
    let isCompleted: Bool
    let onAddTodo: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isCompleted ? "checkmark.circle" : "list.bullet.clipboard")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color.black.opacity(0.2))
            
            Text(isCompleted ? "暂无已完成待办" : "暂无待办事项")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color.white)
                .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                .shadow(color: Color.black, radius: 0, x: 1, y: 1)
            
            if !isCompleted {
                Text("点击下方按钮添加新的待办")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
            }
        }
    }
}


// 待办卡片
struct TodoCardView: View {
    @Bindable var todo: TodoItem
    @State private var showCheckmark = false
    @State private var showDeleteConfirm = false
    @State private var showExpenseSheet = false
    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]
    
    // 获取关联的报销
    private var linkedExpense: Expense? {
        guard let expenseId = todo.linkedExpenseId else { return nil }
        return allExpenses.first { $0.id == expenseId }
    }

    var body: some View {
        HStack(spacing: 16) {
            // 完成状态按钮
            Button(action: {
                HapticFeedback.medium()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    todo.isCompleted.toggle()
                    showCheckmark = todo.isCompleted
                }
            }) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            todo.isCompleted ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.black.opacity(0.2),
                            lineWidth: 2.5
                        )
                        .frame(width: 28, height: 28)

                    if todo.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                            .scaleEffect(showCheckmark ? 1.0 : 0.3)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showCheckmark)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // 事项内容
            VStack(alignment: .leading, spacing: 6) {
                // 标题和状态指示
                HStack(spacing: 6) {
                    // 即将到来的圆点指示
                    if !todo.isOverdue && todo.isUpcoming {
                        Circle()
                            .fill(Color(red: 0.85, green: 1.0, blue: 0.25))
                            .frame(width: 8, height: 8)
                    }

                    Text(todo.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.85))
                        .strikethrough(todo.isCompleted, color: Color.black.opacity(0.3))
                    
                    // 已逾期标注
                    if todo.isOverdue {
                        Text("已逾期")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color.red.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }

                HStack(spacing: 8) {
                    // 日期和星期
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.black.opacity(0.5))
                        Text(todo.dateText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.5))
                    }

                    // 时间
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.black.opacity(0.5))
                        Text(todo.timeRangeText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.5))
                    }
                }
                
                // 附件和日历同步指示
                HStack(spacing: 8) {
                    // 附件指示（统一显示所有附件类型）
                    let hasImages = todo.imageData?.isEmpty == false
                    let hasTexts = todo.textAttachments?.isEmpty == false
                    let hasAttachments = hasImages || hasTexts
                    
                    if hasAttachments {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 11, weight: .medium))
                            
                            let attachmentCount = (todo.imageData?.count ?? 0) + 
                                                 (todo.textAttachments?.count ?? 0)
                            
                            if attachmentCount > 1 {
                                Text("\(attachmentCount)")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                        }
                        .foregroundColor(Color.black.opacity(0.35))
                    }
                    
                    // 关联报销指示
                    if linkedExpense != nil {
                        Button(action: {
                            HapticFeedback.light()
                            showExpenseSheet = true
                        }) {
                            Text("跳转至报销")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 0, x: -0.5, y: -0.5)
                                .shadow(color: .black, radius: 0, x: 0.5, y: -0.5)
                                .shadow(color: .black, radius: 0, x: -0.5, y: 0.5)
                                .shadow(color: .black, radius: 0, x: 0.5, y: 0.5)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.8))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // 日历同步指示
                    if todo.syncToCalendar && todo.calendarEventId != nil {
                        Button(action: {
                            openCalendarApp(for: todo)
                        }) {
                            Text("跳转至日历")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 0, x: -0.5, y: -0.5)
                                .shadow(color: .black, radius: 0, x: 0.5, y: -0.5)
                                .shadow(color: .black, radius: 0, x: -0.5, y: 0.5)
                                .shadow(color: .black, radius: 0, x: 0.5, y: 0.5)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 0.85, green: 1.0, blue: 0.25))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            Spacer()

            // 右侧：删除按钮
            Button(action: {
                HapticFeedback.light()
                showDeleteConfirm = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.black.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.5))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .onAppear {
            showCheckmark = todo.isCompleted
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteTodo()
            }
        } message: {
            Text("确定要删除待办事项「\(todo.title)」吗？")
        }
        .sheet(isPresented: $showExpenseSheet) {
            if let expense = linkedExpense {
                ExpenseEditView(expense: expense)
            }
        }
    }

    // 删除待办事项
    private func deleteTodo() {
        HapticFeedback.medium()

        // 如果有日历事件，先删除日历事件
        if let eventId = todo.calendarEventId {
            Task {
                await CalendarManager.shared.deleteCalendarEvent(eventIdentifier: eventId)
            }
        }

        // 如果有通知，删除通知
        if let notificationId = todo.notificationId {
            Task {
                await CalendarManager.shared.cancelNotification(id: notificationId)
            }
        }

        // 从数据库删除
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            modelContext.delete(todo)
            try? modelContext.save()
        }

        print("✅ 已删除待办: \(todo.title)")
    }

    // 打开系统日历应用
    private func openCalendarApp(for todo: TodoItem) {
        HapticFeedback.light()

        // 使用 calshow: URL scheme 打开系统日历
        // iOS 日历使用的是从 2001-01-01 00:00:00 UTC 开始的秒数 (Apple's reference date)
        let timestamp = todo.startTime.timeIntervalSinceReferenceDate

        if let url = URL(string: "calshow:\(timestamp)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                print("✅ 打开系统日历: \(todo.title)")
                print("   开始时间: \(todo.startTime)")
                print("   时间戳: \(timestamp)")
            } else {
                print("⚠️ 无法打开系统日历")
            }
        }
    }
}
