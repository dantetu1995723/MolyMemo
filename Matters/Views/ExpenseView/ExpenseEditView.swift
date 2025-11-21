import SwiftUI
import SwiftData
import PhotosUI

// 报销编辑/创建界面
struct ExpenseEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var amount: String
    @State private var category: String
    @State private var event: String
    @State private var occurredAt: Date
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showContent = false
    @State private var showMoreOptions = false
    @State private var createTodoReminder = false
    @State private var todoStartTime: Date = {
        let calendar = Calendar.current
        var date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }()
    @State private var todoEndTime: Date = {
        let calendar = Calendar.current
        var date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
    }()
    @State private var todoReminderTime: Date = {
        let calendar = Calendar.current
        var date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 8, minute: 45, second: 0, of: date) ?? date
    }()
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case title
        case amount
        case category
        case event
    }
    
    private let expense: Expense?
    private let isEditing: Bool
    
    // 预定义类别
    private let categories = ["餐饮", "交通", "住宿", "办公", "娱乐", "其他"]
    
    init(expense: Expense? = nil) {
        self.expense = expense
        self.isEditing = expense != nil
        
        // 初始化状态
        _title = State(initialValue: expense?.title ?? "")
        _amount = State(initialValue: expense != nil ? String(format: "%.2f", expense!.amount) : "")
        _category = State(initialValue: expense?.category ?? "")
        _event = State(initialValue: expense?.event ?? "")
        _occurredAt = State(initialValue: expense?.occurredAt ?? Date())
        
        // 加载图片
        if let imageDataArray = expense?.imageData {
            let images = imageDataArray.compactMap { UIImage(data: $0) }
            _selectedImages = State(initialValue: images)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                
                ScrollView {
                    if showContent {
                        VStack(spacing: 16) {
                            // 核心信息卡片
                            AmountAndTitleCard(
                                amount: $amount,
                                title: $title,
                                focusedField: $focusedField
                            )
                            
                            // 类别和时间卡片
                            CategoryAndTimeCard(
                                categories: categories,
                                selectedCategory: $category,
                                occurredAt: $occurredAt
                            )
                            
                            // 事件输入卡片
                            EventInputCard(event: $event, focusedField: $focusedField)
                            
                            // 待办提醒开关
                            TodoReminderToggle(createTodoReminder: $createTodoReminder)
                            
                            // 待办时间设置（展开式）
                            if createTodoReminder {
                                TodoTimeSettings(
                                    startTime: $todoStartTime,
                                    endTime: $todoEndTime,
                                    reminderTime: $todoReminderTime
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            // 更多选项切换
                            MoreOptionsButton(
                                showMoreOptions: $showMoreOptions,
                                hasAttachments: !selectedImages.isEmpty
                            )
                            
                            // 展开的附件选项
                            if showMoreOptions {
                                AttachmentsSection(
                                    selectedImages: $selectedImages,
                                    showImagePicker: $showImagePicker
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            // 底部占位
                            Color.clear.frame(height: 100)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑报销" : "新建报销")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveExpense) {
                        Text("保存")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white)
                            .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                            .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                            .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                            .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
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
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black, lineWidth: 2)
                                    )
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(!isValid)
                    .opacity(isValid ? 1.0 : 0.5)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView { images in
                    selectedImages.append(contentsOf: images)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.1)) {
                    showContent = true
                }
            }
        }
    }
    
    // 验证输入
    private var isValid: Bool {
        !title.isEmpty && !amount.isEmpty && Double(amount) != nil && Double(amount)! > 0
    }
    
    // 保存报销
    private func saveExpense() {
        guard isValid else { return }
        guard let amountValue = Double(amount) else { return }
        
        HapticFeedback.medium()
        
        // 准备图片数据
        let imageDataArray = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        
        var targetExpense: Expense?
        
        if let expense = expense {
            // 更新现有报销
            expense.title = title
            expense.amount = amountValue
            expense.category = category.isEmpty ? nil : category
            expense.event = event.isEmpty ? nil : event
            expense.occurredAt = occurredAt
            expense.imageData = imageDataArray.isEmpty ? nil : imageDataArray
            expense.textAttachments = nil
            expense.lastModified = Date()
            targetExpense = expense
        } else {
            // 创建新报销
            let newExpense = Expense(
                amount: amountValue,
                title: title,
                category: category.isEmpty ? nil : category,
                event: event.isEmpty ? nil : event,
                occurredAt: occurredAt,
                notes: nil,
                imageData: imageDataArray.isEmpty ? nil : imageDataArray,
                textAttachments: nil
            )
            modelContext.insert(newExpense)
            targetExpense = newExpense
        }
        
        // 创建待办提醒
        if createTodoReminder, let targetExpense = targetExpense {
            let todoTitle = "报销提醒：\(title)"
            let todoDescription = "金额：¥\(String(format: "%.2f", amountValue))\n类别：\(category.isEmpty ? "未分类" : category)"
            
            let todoItem = TodoItem(
                title: todoTitle,
                taskDescription: todoDescription,
                startTime: todoStartTime,
                endTime: todoEndTime,
                reminderTime: todoReminderTime,
                syncToCalendar: true
            )
            
            // 建立双向关联
            todoItem.linkedExpenseId = targetExpense.id
            targetExpense.linkedTodoId = todoItem.id
            
            modelContext.insert(todoItem)
        }
        
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 子视图组件

// 金额和标题卡片
struct AmountAndTitleCard: View {
    @Binding var amount: String
    @Binding var title: String
    var focusedField: FocusState<ExpenseEditView.Field?>.Binding
    
    var body: some View {
        VStack(spacing: 0) {
            // 金额输入
            VStack(spacing: 6) {
                Text("报销金额")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 8) {
                    Text("¥")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.85))
                    
                    TextField("0.00", text: $amount)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused(focusedField, equals: .amount)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            
            Divider()
                .padding(.horizontal, 18)
            
            // 标题
            TextField("报销项目名称", text: $title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .focused(focusedField, equals: .title)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// 类别和时间卡片
struct CategoryAndTimeCard: View {
    let categories: [String]
    @Binding var selectedCategory: String
    @Binding var occurredAt: Date
    
    var body: some View {
        VStack(spacing: 0) {
            // 类别选择
            VStack(alignment: .leading, spacing: 12) {
                Text("类别")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories, id: \.self) { cat in
                            CategoryButton(
                                category: cat,
                                isSelected: selectedCategory == cat,
                                action: {
                                    HapticFeedback.light()
                                    selectedCategory = cat
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            
            Divider()
                .padding(.horizontal, 18)
            
            // 发生时间
            HStack(spacing: 8) {
                Text("发生时间")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.75))
                
                Spacer()
                
                DatePicker("", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(Color(red: 0.85, green: 1.0, blue: 0.25))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

// 类别按钮
struct CategoryButton: View {
    let category: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(category)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? Color.white : Color.black.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            isSelected ?
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25),
                                    Color(red: 0.78, green: 0.98, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.black.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 待办时间设置
struct TodoTimeSettings: View {
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var reminderTime: Date
    
    var body: some View {
        VStack(spacing: 12) {
            // 开始时间
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                    .frame(width: 24)
                
                Text("开始")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.75))
                
                Spacer()
                
                DatePicker("", selection: $startTime)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color(red: 0.85, green: 1.0, blue: 0.25))
                    .onChange(of: startTime) { _, newValue in
                        if endTime <= newValue {
                            endTime = newValue.addingTimeInterval(3600)
                        }
                        reminderTime = newValue.addingTimeInterval(-15 * 60)
                        HapticFeedback.light()
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            
            Divider()
                .padding(.horizontal, 18)
            
            // 结束时间
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                    .frame(width: 24)
                
                Text("结束")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.75))
                
                Spacer()
                
                DatePicker("", selection: $endTime, in: startTime...)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color(red: 0.85, green: 1.0, blue: 0.25))
                    .onChange(of: endTime) { _, _ in
                        HapticFeedback.light()
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            
            Divider()
                .padding(.horizontal, 18)
            
            // 提醒时间
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                    .frame(width: 24)
                
                Text("提醒")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.75))
                
                Spacer()
                
                DatePicker("", selection: $reminderTime)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color(red: 0.85, green: 1.0, blue: 0.25))
                    .onChange(of: reminderTime) { _, _ in
                        HapticFeedback.light()
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.05),
                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

// 待办提醒开关
struct TodoReminderToggle: View {
    @Binding var createTodoReminder: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            // 左侧图标背景
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.2),
                                Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("添加到待办提醒")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                
                Text(createTodoReminder ? "点击下方设置时间" : "创建关联的待办事项")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.45))
            }
            
            Spacer()
            
            Toggle("", isOn: $createTodoReminder)
                .labelsHidden()
                .tint(Color(red: 0.85, green: 1.0, blue: 0.25))
                .onChange(of: createTodoReminder) { _, _ in
                    HapticFeedback.light()
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.98, green: 0.98, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    createTodoReminder ? 
                    Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3) : 
                    Color.black.opacity(0.06),
                    lineWidth: 1.5
                )
        )
        .padding(.horizontal, 20)
    }
}

// 更多选项按钮
struct MoreOptionsButton: View {
    @Binding var showMoreOptions: Bool
    let hasAttachments: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showMoreOptions.toggle()
            }
            HapticFeedback.light()
        }) {
            HStack(spacing: 8) {
                Image(systemName: showMoreOptions ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                
                Text(showMoreOptions ? "收起附件" : "添加附件")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                
                Spacer()
                
                if hasAttachments {
                    Circle()
                        .fill(Color(red: 0.85, green: 1.0, blue: 0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

// 附件区域
struct AttachmentsSection: View {
    @Binding var selectedImages: [UIImage]
    @Binding var showImagePicker: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            if !selectedImages.isEmpty {
                AttachmentsList(selectedImages: $selectedImages)
            }
            
            // 添加图片按钮
            Button(action: {
                HapticFeedback.light()
                showImagePicker = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("添加图片")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color.white)
                .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
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
                )
                .padding(.horizontal, 18)
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

// 附件列表
struct AttachmentsList: View {
    @Binding var selectedImages: [UIImage]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                
                Text("附件 (\(selectedImages.count))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.7))
            }
            .padding(.horizontal, 18)
            
            VStack(spacing: 6) {
                // 图片附件
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ExpenseImageAttachmentRow(
                        image: image,
                        index: index,
                        onDelete: {
                            HapticFeedback.light()
                            selectedImages.remove(at: index)
                        }
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// 图片附件行
struct ExpenseImageAttachmentRow: View {
    let image: UIImage
    let index: Int
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text("图片 \(index + 1)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.6))
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.black.opacity(0.2))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

// 事件输入卡片
struct EventInputCard: View {
    @Binding var event: String
    var focusedField: FocusState<ExpenseEditView.Field?>.Binding
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("事件")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                TextField("报销项目发生情形（如：项目会议、客户拜访等）", text: $event)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .focused(focusedField, equals: .event)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
}
