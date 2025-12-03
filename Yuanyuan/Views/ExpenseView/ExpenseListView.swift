import SwiftUI
import SwiftData
import MessageUI
import UIKit

// 报销列表视图
struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Query(sort: \Expense.occurredAt, order: .reverse) private var expenses: [Expense]
    @Query private var companies: [CompanyInfo]
    
    // 外部绑定的添加弹窗状态（由底部tab栏控制）
    @Binding var showAddSheet: Bool
    @State private var selectedExpense: Expense?
    @State private var showContent = false
    @State private var showHeader = false
    @State private var selectedTab: ExpenseTab = .unreimbursed
    @State private var filterMode: FilterMode = .event
    @State private var showCompanySettings = false
    @State private var mailData: MailData?
    @State private var showMailAlert = false
    @State private var mailAlertMessage = ""
    
    init(showAddSheet: Binding<Bool> = .constant(false)) {
        self._showAddSheet = showAddSheet
    }
    
    // 主题色 - 跟随主页颜色
    private var themeColor: Color {
        YuanyuanTheme.color(at: appState.colorIndex)
    }
    
    // 邮件数据结构
    struct MailData: Identifiable {
        let id = UUID()
        let pdfData: Data
        let eventName: String
    }
    
    enum ExpenseTab {
        case unreimbursed
        case reimbursed
    }
    
    enum FilterMode {
        case event  // 按事件备注
        case category(String)  // 按具体类别
    }
    
    // 所有可用的类别
    private let allCategories = ["交通", "餐饮", "住宿", "办公", "娱乐", "其他"]
    
    // 过滤报销
    private var unreimbursedExpenses: [Expense] {
        expenses.filter { !$0.isReimbursed }
    }
    
    private var reimbursedExpenses: [Expense] {
        expenses.filter { $0.isReimbursed }
    }
    
    // 当前显示的报销列表
    private var currentExpenses: [Expense] {
        selectedTab == .unreimbursed ? unreimbursedExpenses : reimbursedExpenses
    }
    
    // 分组后的报销列表（按事件备注分组）
    private var groupedByEvent: [(String, [Expense])] {
        let grouped = Dictionary(grouping: currentExpenses) { expense in
            if let event = expense.event, !event.isEmpty {
                return event
            }
            return "无事件"
        }
        return grouped.sorted { $0.key < $1.key }
    }
    
    // 筛选后的报销列表（按类别筛选）
    private var filteredExpenses: [Expense] {
        switch filterMode {
        case .event:
            return []  // 事件模式不使用这个
        case .category(let category):
            return currentExpenses.filter { $0.category == category }
        }
    }
    
    var totalUnreimbursed: Double {
        unreimbursedExpenses.reduce(0) { $0 + $1.amount }
    }
    
    var totalReimbursed: Double {
        reimbursedExpenses.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        ZStack {
            // 渐变背景
            ModuleBackgroundView(themeColor: themeColor)
            
            ModuleSheetContainer {
                VStack(spacing: 0) {
                    // 顶部操作栏
                    if showHeader {
                        HStack {
                            Spacer()
                            Button(action: {
                                HapticFeedback.light()
                                showCompanySettings = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("开票信息")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.black.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(LiquidGlassCapsuleBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    
                    // Tab切换器
                    if showHeader {
                        ExpenseTabSelector(
                            selectedTab: $selectedTab,
                            unreimbursedAmount: totalUnreimbursed,
                            reimbursedAmount: totalReimbursed,
                            themeColor: themeColor
                        )
                    }
                    
                    // 类别筛选器
                    if showHeader {
                        CategoryFilterSelector(
                            categories: allCategories,
                            filterMode: $filterMode,
                            currentExpenses: currentExpenses
                        )
                    }
                    
                    // 内容区域
                    if case .event = filterMode {
                        // 按事件分组显示
                        ExpenseGroupedListContent(
                            showContent: showContent,
                            groupedExpenses: groupedByEvent,
                            selectedTab: selectedTab,
                            selectedExpense: $selectedExpense,
                            onSendEmail: { eventName, expenseList in
                                sendEmailForEvent(eventName: eventName, expenses: expenseList)
                            },
                            onSendAllEmail: {
                                sendEmailForAllEvents(groupedExpenses: groupedByEvent)
                            }
                        )
                    } else {
                        // 按类别筛选显示
                        if case .category(let category) = filterMode {
                            ExpenseListContent(
                                showContent: showContent,
                                expenses: filteredExpenses,
                                selectedTab: selectedTab,
                                selectedExpense: $selectedExpense,
                                categoryName: category,
                                onSendEmail: { expenseList in
                                    sendEmailForEvent(eventName: category, expenses: expenseList)
                                }
                            )
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            ModuleNavigationBar(
                title: "报销管理",
                themeColor: themeColor,
                onBack: { dismiss() },
                trailingIcon: "plus",
                trailingAction: { showAddSheet = true }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            ExpenseEditView()
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedExpense) { expense in
            ExpenseEditView(expense: expense)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompanySettings) {
            CompanySettingsView()
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $mailData) { data in
            MailComposeView(
                pdfData: data.pdfData,
                eventName: data.eventName,
                recipientEmail: companies.first?.email ?? ""
            )
        }
        .alert("提示", isPresented: $showMailAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(mailAlertMessage)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showHeader = true
            }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.1)) {
                showContent = true
            }
        }
    }
    
    private func deleteExpense(_ expense: Expense) {
        withAnimation {
            modelContext.delete(expense)
        }
        HapticFeedback.medium()
    }
    
    // 发送邮件（单个事件）
    private func sendEmailForEvent(eventName: String, expenses: [Expense]) {
        HapticFeedback.medium()
        
        // 检查邮件服务是否可用
        guard MailComposeView.canSendMail else {
            mailAlertMessage = "无法发送邮件，请在系统设置中配置邮件账户"
            showMailAlert = true
            HapticFeedback.warning()
            return
        }
        
        // 检查是否有发票图片
        let hasImages = expenses.contains { expense in
            if let imageData = expense.imageData, !imageData.isEmpty {
                return true
            }
            return false
        }
        
        if !hasImages {
            mailAlertMessage = "该事件下的报销项目暂无发票图片，将生成汇总表"
        }
        
        // 生成PDF
        guard let pdfData = ExpensePDFGenerator.generatePDF(for: expenses, eventName: eventName) else {
            mailAlertMessage = "PDF生成失败，请稍后重试"
            showMailAlert = true
            HapticFeedback.error()
            return
        }
        
        print("✅ PDF生成成功，大小：\(pdfData.count) 字节")
        
        // 设置邮件数据并显示邮件界面
        mailData = MailData(pdfData: pdfData, eventName: eventName)
    }
    
    // 发送邮件（所有事件汇总）
    private func sendEmailForAllEvents(groupedExpenses: [(String, [Expense])]) {
        HapticFeedback.medium()
        
        // 检查邮件服务是否可用
        guard MailComposeView.canSendMail else {
            mailAlertMessage = "无法发送邮件，请在系统设置中配置邮件账户"
            showMailAlert = true
            HapticFeedback.warning()
            return
        }
        
        // 检查是否有报销项目
        if groupedExpenses.isEmpty {
            mailAlertMessage = "当前没有报销项目"
            showMailAlert = true
            HapticFeedback.warning()
            return
        }
        
        // 生成按事件分组的PDF
        guard let pdfData = ExpensePDFGenerator.generateGroupedPDF(groupedExpenses: groupedExpenses) else {
            mailAlertMessage = "PDF生成失败，请稍后重试"
            showMailAlert = true
            HapticFeedback.error()
            return
        }
        
        print("✅ 汇总PDF生成成功，大小：\(pdfData.count) 字节")
        
        // 设置邮件数据并显示邮件界面
        let eventNames = groupedExpenses.map { $0.0 }.prefix(3).joined(separator: "、")
        let summaryName = groupedExpenses.count > 3 ? "\(eventNames)等\(groupedExpenses.count)个事件" : eventNames
        mailData = MailData(pdfData: pdfData, eventName: "汇总-\(summaryName)")
    }
}

// MARK: - 子视图组件

// Tab切换器
struct ExpenseTabSelector: View {
    @Binding var selectedTab: ExpenseListView.ExpenseTab
    let unreimbursedAmount: Double
    let reimbursedAmount: Double
    var themeColor: Color = YuanyuanTheme.warmBackground
    
    var body: some View {
        HStack(spacing: 0) {
            ModuleTabButton(
                title: "未报销",
                value: String(format: "¥%.0f", unreimbursedAmount),
                isSelected: selectedTab == .unreimbursed,
                action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        selectedTab = .unreimbursed
                    }
                },
                themeColor: themeColor
            )
            
            ModuleTabButton(
                title: "已报销",
                value: String(format: "¥%.0f", reimbursedAmount),
                isSelected: selectedTab == .reimbursed,
                action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        selectedTab = .reimbursed
                    }
                },
                themeColor: themeColor
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

// 类别筛选器
struct CategoryFilterSelector: View {
    let categories: [String]
    @Binding var filterMode: ExpenseListView.FilterMode
    let currentExpenses: [Expense]
    
    // 检查事件备注模式是否有内容
    private var hasEventContent: Bool {
        let grouped = Dictionary(grouping: currentExpenses) { expense in
            if let event = expense.event, !event.isEmpty {
                return event
            }
            return "无事件"
        }
        return !grouped.isEmpty
    }
    
    // 检查某个类别是否有内容
    private func hasCategoryContent(_ category: String) -> Bool {
        return currentExpenses.contains { $0.category == category }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // "事件备注"按钮
                FilterCapsuleButton(
                    title: "事件备注",
                    isSelected: { if case .event = filterMode { return true }; return false }(),
                    action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            filterMode = .event
                        }
                    }
                )
                
                // 各个类别按钮
                ForEach(categories, id: \.self) { category in
                    FilterCapsuleButton(
                        title: category,
                        isSelected: { if case .category(let selected) = filterMode, selected == category { return true }; return false }(),
                        action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                filterMode = .category(category)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 16)
    }
}

// 按事件分组的列表内容
struct ExpenseGroupedListContent: View {
    let showContent: Bool
    let groupedExpenses: [(String, [Expense])]
    let selectedTab: ExpenseListView.ExpenseTab
    @Binding var selectedExpense: Expense?
    let onSendEmail: (String, [Expense]) -> Void
    let onSendAllEmail: () -> Void
    
    var body: some View {
        ScrollView {
            if showContent {
                if !groupedExpenses.isEmpty {
                    VStack(spacing: 20) {
                        // 总的发送邮箱按钮
                        Button(action: {
                            HapticFeedback.medium()
                            onSendAllEmail()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("发送全部发票")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                    Text("按事件分类汇总PDF")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .opacity(0.7)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundColor(Color.black.opacity(0.7))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                ZStack {
                                    // 主体液态玻璃
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: Color.white.opacity(0.95), location: 0.0),
                                                    .init(color: Color.white.opacity(0.82), location: 0.5),
                                                    .init(color: Color.white.opacity(0.88), location: 1.0)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    // 高光层
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: Color.white.opacity(0.7), location: 0.0),
                                                    .init(color: Color.white.opacity(0.3), location: 0.3),
                                                    .init(color: Color.clear, location: 0.6)
                                                ]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                    
                                    // 晶体边框
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: Color.white.opacity(1.0), location: 0.0),
                                                    .init(color: Color.white.opacity(0.5), location: 0.5),
                                                    .init(color: Color.white.opacity(0.8), location: 1.0)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2.0
                                        )
                                }
                            )
                            .shadow(color: Color.white.opacity(0.8), radius: 10, x: 0, y: -4)
                            .shadow(color: Color.white.opacity(0.4), radius: 5, x: -2, y: -2)
                            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        
                        ForEach(Array(groupedExpenses.enumerated()), id: \.element.0) { groupIndex, group in
                            VStack(alignment: .leading, spacing: 12) {
                                // 分组标题和操作按钮
                                HStack(spacing: 12) {
                                    // 标题
                                    HStack(spacing: 8) {
                                        Text(group.0)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.white)
                                            .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                            .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                            .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                            .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                                        
                                        Text("(\(group.1.count))")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color.white.opacity(0.7))
                                            .shadow(color: Color.black.opacity(0.6), radius: 0, x: -0.5, y: -0.5)
                                            .shadow(color: Color.black.opacity(0.6), radius: 0, x: 0.5, y: -0.5)
                                            .shadow(color: Color.black.opacity(0.6), radius: 0, x: -0.5, y: 0.5)
                                            .shadow(color: Color.black.opacity(0.6), radius: 0, x: 0.5, y: 0.5)
                                    }
                                    
                                    Spacer()
                                    
                                    // 发送邮箱按钮
                                    Button(action: {
                                        HapticFeedback.light()
                                        onSendEmail(group.0, group.1)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "envelope.fill")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("发送邮箱")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                        .foregroundColor(Color.black.opacity(0.65))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(LiquidGlassCapsuleBackground())
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                                .padding(.horizontal, 24)
                                
                                // 组内报销卡片
                                VStack(spacing: 16) {
                                    ForEach(Array(group.1.enumerated()), id: \.element.id) { index, expense in
                                        ExpenseCardView(expense: expense)
                                            .opacity(selectedTab == .reimbursed ? 0.85 : 1.0)
                                            .onTapGesture {
                                                HapticFeedback.light()
                                                selectedExpense = expense
                                            }
                                            .transition(.scale.combined(with: .opacity))
                                            .animation(
                                                .spring(response: 0.4, dampingFraction: 0.75)
                                                .delay(Double(groupIndex) * 0.03 + Double(index) * 0.01),
                                                value: showContent
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 180)
                } else {
                    EmptyExpenseView(
                        isReimbursed: selectedTab == .reimbursed
                    )
                    .padding(.top, 60)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

// 按类别筛选的列表内容
struct ExpenseListContent: View {
    let showContent: Bool
    let expenses: [Expense]
    let selectedTab: ExpenseListView.ExpenseTab
    @Binding var selectedExpense: Expense?
    let categoryName: String
    let onSendEmail: ([Expense]) -> Void
    
    var body: some View {
        ScrollView {
            if showContent {
                if !expenses.isEmpty {
                    VStack(spacing: 20) {
                        // 类别标题和操作按钮
                        VStack(alignment: .leading, spacing: 12) {
                            // 标题行
                            HStack(spacing: 12) {
                                // 标题
                                HStack(spacing: 8) {
                                    Text(categoryName)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                        .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                        .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                                    
                                    Text("(\(expenses.count))")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white.opacity(0.7))
                                        .shadow(color: Color.black.opacity(0.6), radius: 0, x: -0.5, y: -0.5)
                                        .shadow(color: Color.black.opacity(0.6), radius: 0, x: 0.5, y: -0.5)
                                        .shadow(color: Color.black.opacity(0.6), radius: 0, x: -0.5, y: 0.5)
                                        .shadow(color: Color.black.opacity(0.6), radius: 0, x: 0.5, y: 0.5)
                                }
                                
                                Spacer()
                                
                                // 发送邮箱按钮
                                Button(action: {
                                    HapticFeedback.light()
                                    onSendEmail(expenses)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "envelope.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("发送邮箱")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(Color.black.opacity(0.65))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(LiquidGlassCapsuleBackground())
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                            .padding(.horizontal, 24)
                            
                            // 报销卡片列表
                            VStack(spacing: 16) {
                                ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                                    ExpenseCardView(expense: expense)
                                        .opacity(selectedTab == .reimbursed ? 0.85 : 1.0)
                                        .onTapGesture {
                                            HapticFeedback.light()
                                            selectedExpense = expense
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                        .animation(
                                            .spring(response: 0.4, dampingFraction: 0.75)
                                            .delay(Double(index) * 0.01),
                                            value: showContent
                                        )
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 180)
                } else {
                    EmptyExpenseView(
                        isReimbursed: selectedTab == .reimbursed
                    )
                    .padding(.top, 60)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

// 报销卡片
struct ExpenseCardView: View {
    @Bindable var expense: Expense
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirm = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 主要内容区域
            VStack(alignment: .leading, spacing: 12) {
                // 第一行：金额和按钮水平对齐
                HStack(alignment: .center, spacing: 0) {
                    // 金额 - 大号突出
                    Text(expense.formattedAmount)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.9))
                    
                    Spacer()
                    
                    // 右侧：操作按钮组
                    HStack(spacing: 8) {
                        // 展开/收起按钮（如果有事件或附件）
                        if hasExpandableContent {
                            Button(action: {
                                HapticFeedback.light()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    isExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color.black.opacity(0.7))
                                    .frame(width: 32, height: 32)
                                    .background(GlassButtonBackground())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        
                        // 删除按钮
                        Button(action: {
                            HapticFeedback.light()
                            showDeleteConfirm = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.black.opacity(0.3))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // 第二行：抬头
                Text(expense.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // 第三行：类别和时间信息
                HStack(spacing: 8) {
                    // 类别标签 - 液态玻璃白色
                    if let category = expense.category {
                        Text(category)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.65))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: Color.white.opacity(0.92), location: 0.0),
                                                    .init(color: Color.white.opacity(0.78), location: 0.5),
                                                    .init(color: Color.white.opacity(0.85), location: 1.0)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: Color.white.opacity(0.6), location: 0.0),
                                                    .init(color: Color.white.opacity(0.2), location: 0.3),
                                                    .init(color: Color.clear, location: 0.6)
                                                ]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                    
                                    Capsule()
                                        .strokeBorder(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: Color.white.opacity(1.0), location: 0.0),
                                                    .init(color: Color.white.opacity(0.5), location: 0.5),
                                                    .init(color: Color.white.opacity(0.8), location: 1.0)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.2
                                        )
                                }
                                .shadow(color: Color.white.opacity(0.6), radius: 3, x: 0, y: -1)
                                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 2)
                            )
                    }
                    
                    // 时间
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10, weight: .medium))
                        Text(expense.occurredDateText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            
            // 可折叠内容区域
            if hasExpandableContent {
                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // 事件备注
                        if let event = expense.event, !event.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.black.opacity(0.5))
                                    .frame(width: 16)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("事件备注")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.4))
                                    
                                    Text(event)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.7))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // 图片附件
                        if let imageData = expense.imageData, !imageData.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "paperclip.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.black.opacity(0.5))
                                    .frame(width: 16)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("附件")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.4))
                                    
                                    HStack(spacing: 8) {
                                        ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in
                                            if let image = UIImage(data: data) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 60, height: 60)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                                                    )
                                                    .shadow(color: Color.white.opacity(0.4), radius: 2, x: 0, y: -1)
                                                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                                            }
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(
            ZStack {
                // 液态玻璃基础
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.88), location: 0.0),
                                .init(color: Color.white.opacity(0.68), location: 0.5),
                                .init(color: Color.white.opacity(0.78), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // 表面高光
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.45), location: 0.0),
                                .init(color: Color.white.opacity(0.15), location: 0.2),
                                .init(color: Color.clear, location: 0.5)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // 晶体边框
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.9), location: 0.0),
                                .init(color: Color.white.opacity(0.35), location: 0.5),
                                .init(color: Color.white.opacity(0.65), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.white.opacity(0.5), radius: 6, x: 0, y: -2)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 20)
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteExpense()
            }
        } message: {
            Text("确定要删除报销「\(expense.title)」吗？")
        }
    }
    
    // 是否有可展开内容
    private var hasExpandableContent: Bool {
        let hasEvent = expense.event != nil && !expense.event!.isEmpty
        let hasImages = expense.imageData != nil && !expense.imageData!.isEmpty
        return hasEvent || hasImages
    }
    
    private func deleteExpense() {
        HapticFeedback.medium()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            modelContext.delete(expense)
            try? modelContext.save()
        }
    }
}

// 空状态视图
struct EmptyExpenseView: View {
    let isReimbursed: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isReimbursed ? "checkmark.circle" : "doc.text")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color.black.opacity(0.15))
            
            Text(isReimbursed ? "暂无已报销项目" : "暂无未报销项目")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.5))
            
            if !isReimbursed {
                Text("点击下方按钮添加报销")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.35))
            }
        }
    }
}

// 添加按钮
struct AddExpenseButton: View {
    @Binding var showAddSheet: Bool
    
    var body: some View {
        Button(action: {
            HapticFeedback.medium()
            showAddSheet = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                
                Text("添加报销")
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

#Preview {
    ExpenseListView()
        .modelContainer(for: [Expense.self])
}
