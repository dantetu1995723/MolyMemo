import SwiftUI
import SwiftData
import Speech

// 环境值：隐藏输入栏
private struct HideInputBarKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var hideInputBar: Binding<Bool> {
        get { self[HideInputBarKey.self] }
        set { self[HideInputBarKey.self] = newValue }
    }
}

// 独立的聊天室页面 - 使用全局AppState保存对话历史
struct ChatRoomPage: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @State private var displayText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showHistory: Bool = false
    @State private var isLoadingHistory: Bool = true  // 是否正在加载历史记录
    @State private var shouldHideInputBar: Bool = false  // 是否隐藏底部输入栏
    @State private var showAutoInvoiceWebView: Bool = false  // 是否显示自动开票 WebView
    @State private var invoiceURL: String = ""  // 开票 URL
    @State private var companyInfoForInvoice: CompanyInfo? = nil  // 用于开票的公司信息

    let initialMode: AppMode
    
    
    // 从相册发送最近一张照片（用于截图分析shortcut）
    private func sendScreenshotFromClipboard() {
        print("\n========== 📸 开始处理相册最近照片 ==========")
        print("📍 sendScreenshotFromClipboard 被调用")
        print("   当前线程: \(Thread.isMainThread ? "主线程" : "后台线程")")
        print("   isAgentTyping: \(appState.isAgentTyping)")
        
        guard !appState.isAgentTyping else {
            print("⚠️ AI正在输入，无法发送截图")
            return
        }
        
        // 检查是否是有限访问权限
        if PhotoManager.shared.isLimitedAccess() {
            print("⚠️ 检测到相册有限访问权限，无法自动获取最新截图")
            Task { @MainActor in
                let alertMessage = ChatMessage(
                    role: .agent,
                    content: "您的相册设置为「有限访问」，我无法自动获取最新截图😔\n\n💡 有两种解决方案：\n\n方案1：手动选择照片\n• 点击下方 📎 按钮\n• 选择刚才的截图发送\n\n方案2：开启完全访问（推荐）\n• 打开「设置」App\n• 进入「隐私与安全性 > 照片」\n• 找到「Yuanyuan」\n• 选择「所有照片」\n• 然后重新截图即可自动识别"
                )
                appState.chatMessages.append(alertMessage)
                appState.saveMessageToStorage(alertMessage, modelContext: modelContext)
                HapticFeedback.warning()
            }
            return
        }
        
        // 异步从相册获取最近一张照片
        Task {
            print("🔍 从相册获取最近一张照片...")
            
            guard let latestImage = await PhotoManager.shared.fetchLatestPhoto() else {
                print("❌ 无法从相册获取照片")
                await MainActor.run {
                    // 提示用户需要授权相册权限
                    let alertMessage = ChatMessage(
                        role: .agent,
                        content: "无法获取照片，请在系统设置中允许访问相册权限"
                    )
                    appState.chatMessages.append(alertMessage)
                    appState.saveMessageToStorage(alertMessage, modelContext: modelContext)
                }
                return
            }
            
            print("✅ 成功从相册获取照片")
            print("   图片尺寸: \(latestImage.size.width) x \(latestImage.size.height)")
            
            await MainActor.run {
                HapticFeedback.success()
                
                print("📤 准备发送截图消息，开始智能识别...")
                
                // 添加用户消息（只包含图片，不含文字）
                let userMessage = ChatMessage(
                    role: .user,
                    images: [latestImage],
                    content: ""  // 空内容，只发送图片
                )
                appState.chatMessages.append(userMessage)
                appState.saveMessageToStorage(userMessage, modelContext: modelContext)
                print("✅ 用户截图消息已添加并保存（纯图片，无文字）")
                
                // 创建AI消息，显示处理状态
                let agentMessage = ChatMessage(role: .agent, content: "正在分析图片...")
                appState.chatMessages.append(agentMessage)
                let messageId = agentMessage.id
                print("✅ AI消息已添加")
                
                // 后台智能识别图片
                Task {
                    await processImagesIntelligently(images: [latestImage], userMessageId: userMessage.id, agentMessageId: messageId)
                }
            }
            
            print("==========================================\n")
        }
    }
    
    // 智能批量处理图片（新逻辑：聚合分析，多图合并）
    private func processImagesIntelligently(images: [UIImage], userMessageId: UUID, agentMessageId: UUID) async {
        print("🔍 开始智能分析\(images.count)张图片...")

        // 🆕 检查是否有预分类结果
        let preCategory = appState.screenshotCategory
        if let preCategory = preCategory {
            print("📊 使用预分类结果: \(preCategory.rawValue)")
        }

        // 🆕 优先检查是否有开票二维码
        print("🔍 步骤1: 检查是否包含开票二维码...")
        let qrCodes = await QRCodeScanner.detectQRCodes(in: images)

        print("📊 二维码识别结果: 共识别到 \(qrCodes.count) 个二维码")
        if qrCodes.isEmpty {
            print("⚠️ 未识别到任何二维码，可能原因：")
            print("   - 图片中没有二维码")
            print("   - 二维码模糊或被遮挡")
            print("   - 二维码太小或太大")
        } else {
            for (index, qrCode) in qrCodes.enumerated() {
                let preview = qrCode.count > 100 ? "\(qrCode.prefix(100))..." : qrCode
                print("   二维码 \(index + 1): \(preview)")
            }
        }

        print("🔍 步骤2: 判断二维码类型...")
        if let invoiceQRCode = qrCodes.first(where: { QRCodeScanner.isInvoiceQRCode($0) }) {
            print("✅ 检测到开票二维码，进入自动开票流程")
            await handleInvoiceQRCode(invoiceQRCode, agentMessageId: agentMessageId)
            // 清除预分类结果
            await MainActor.run {
                appState.screenshotCategory = nil
            }
            return
        }

        if !qrCodes.isEmpty {
            print("⚠️ 识别到二维码但不是开票链接，可能是：")
            print("   - 普通小票信息码")
            print("   - 商家二维码")
            print("   - 其他类型二维码")
        }

        print("ℹ️ 未检测到开票二维码，使用AI分析图片内容...")

        do {
            // 🆕 如果有预分类结果，使用针对性的解析
            let batchResult: BatchParseResult

            if let preCategory = preCategory, preCategory != .unknown {
                print("🎯 使用预分类结果进行针对性解析: \(preCategory.rawValue)")
                batchResult = try await parseImagesWithCategory(images: images, category: preCategory)
            } else {
                print("🔍 使用通用批量分析API")
                // 使用新的批量分析API
                batchResult = try await QwenOmniService.analyzeMultipleImages(images: images)
            }

            // 回到主线程更新UI
            await MainActor.run {
                // 清除预分类结果
                appState.screenshotCategory = nil

                // 检查是否有任何有效结果
                let hasAnyResult = !batchResult.todos.isEmpty || !batchResult.contacts.isEmpty || !batchResult.expenses.isEmpty

                if !hasAnyResult {
                    // 所有图片都无法识别，显示重新分类气泡
                    // 移除加载消息
                    if let index = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                        appState.chatMessages.remove(at: index)
                    }
                    
                    // 创建重新分类气泡消息
                    var reclassifyMessage = ChatMessage(
                        role: .agent,
                        content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
                    )
                    reclassifyMessage.showReclassifyBubble = true
                    reclassifyMessage.images = images  // 保存原始图片
                    appState.chatMessages.append(reclassifyMessage)
                    appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
                    return
                }
                
                // 检查是否识别出任何意图，如果都为空则显示重新分类气泡
                if batchResult.todos.isEmpty && batchResult.contacts.isEmpty && batchResult.expenses.isEmpty {
                    print("⚠️ AI未识别出任何意图，显示重新分类气泡让用户确认")
                    // 移除加载消息
                    if let index = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                        appState.chatMessages.remove(at: index)
                    }
                    
                    // 创建重新分类气泡消息
                    var reclassifyMessage = ChatMessage(
                        role: .agent,
                        content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
                    )
                    reclassifyMessage.showReclassifyBubble = true
                    reclassifyMessage.images = images  // 保存原始图片
                    appState.chatMessages.append(reclassifyMessage)
                    appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
                    return
                }

                // 移除加载消息
                if let idx = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                    appState.chatMessages.remove(at: idx)
                }

                // 生成待办预览消息
                for todoResult in batchResult.todos {
                    print("✅ 生成待办: \(todoResult.title)")
                    createTodoPreviewMessage(result: todoResult)
                }

                // 生成联系人预览消息
                for contactResult in batchResult.contacts {
                    print("✅ 生成联系人: \(contactResult.name)")
                    createContactPreviewMessage(result: contactResult)
                }

                // 生成报销预览消息
                for expenseResult in batchResult.expenses {
                    print("✅ 生成报销: \(expenseResult.title) - ¥\(expenseResult.amount)")
                    createExpensePreviewMessage(result: expenseResult)
                }

                HapticFeedback.success()
            }

        } catch {
            print("⚠️ 图片分析失败: \(error)")

            await MainActor.run {
                // 清除预分类结果
                appState.screenshotCategory = nil

                // 分析失败，显示重新分类气泡
                // 移除加载消息
                if let index = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                    appState.chatMessages.remove(at: index)
                }
                
                // 创建重新分类气泡消息
                var reclassifyMessage = ChatMessage(
                    role: .agent,
                    content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
                )
                reclassifyMessage.showReclassifyBubble = true
                reclassifyMessage.images = images  // 保存原始图片
                appState.chatMessages.append(reclassifyMessage)
                appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
            }
        }
    }

    // 🆕 根据预分类结果进行针对性解析
    private func parseImagesWithCategory(images: [UIImage], category: ScreenshotCategory) async throws -> BatchParseResult {
        print("🎯 针对性解析: \(category.rawValue)")

        // 根据分类调用对应的解析方法
        switch category {
        case .todo:
            // 只解析待办
            var todos: [TodoParseResult] = []
            for image in images {
                if let result = try? await QwenOmniService.parseImageForTodo(image: image) {
                    todos.append(result)
                }
            }
            return BatchParseResult(confidence: "high", todos: todos, contacts: [], expenses: [])

        case .contact:
            // 只解析人脉
            var contacts: [ContactParseResult] = []
            for image in images {
                if let result = try? await QwenOmniService.parseImageForContact(image: image) {
                    contacts.append(result)
                }
            }
            return BatchParseResult(confidence: "high", todos: [], contacts: contacts, expenses: [])

        case .expense:
            // 只解析报销
            var expenses: [ExpenseParseResult] = []
            for image in images {
                if let result = try? await QwenOmniService.parseImageForExpense(image: image) {
                    expenses.append(result)
                }
            }
            return BatchParseResult(confidence: "high", todos: [], contacts: [], expenses: expenses)

        case .unknown:
            // 未知类型，使用通用分析
            return try await QwenOmniService.analyzeMultipleImages(images: images)
        }
    }
    
    // 处理无法识别的图片 - 显示重新分类气泡
    private func handleUncertainImages(_ images: [UIImage], agentMessageId: UUID, userMessageId: UUID) {
        print("⚠️ 所有图片都无法识别，显示重新分类气泡")
        
        // 移除加载消息
        if let index = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
            appState.chatMessages.remove(at: index)
        }
        
        // 创建重新分类气泡消息
        var reclassifyMessage = ChatMessage(
            role: .agent,
            content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
        )
        reclassifyMessage.showReclassifyBubble = true
        reclassifyMessage.images = images  // 保存原始图片
        appState.chatMessages.append(reclassifyMessage)
        appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
        
        print("✅ 已显示重新分类气泡")
    }
    
    // 创建待办预览消息
    private func createTodoPreviewMessage(result: TodoParseResult) {
        let todoPreview = TodoPreviewData(
            title: result.title,
            description: result.description,
            startTime: result.startTime,
            endTime: result.endTime,
            reminderTime: result.startTime.addingTimeInterval(-15 * 60),
            imageData: result.imageData
        )
        
        // 从 imageData 重建 UIImage
        var originalImage: UIImage? = nil
        if let image = UIImage(data: result.imageData) {
            originalImage = image
        }
        
        var todoMessage = ChatMessage(role: .agent, content: "为你生成了待办事项，可以调整时间后点击完成~")
        todoMessage.todoPreview = todoPreview
        if let image = originalImage {
            todoMessage.images = [image]  // 保存原始图片供"识别错了"使用
        }
        appState.chatMessages.append(todoMessage)
        appState.saveMessageToStorage(todoMessage, modelContext: modelContext)
        print("✅ 待办预览消息已创建")
    }
    
    // 创建人脉预览消息
    private func createContactPreviewMessage(result: ContactParseResult) {
        // 检查是否存在同名联系人
        let nameToMatch = result.name
        let existingContact = try? modelContext.fetch(
            FetchDescriptor<Contact>(
                predicate: #Predicate { $0.name == nameToMatch }
            )
        ).first
        
        // 准备预览数据（无论是否重名都显示预览）
        let contactPreview = ContactPreviewData(
            name: result.name,
            phoneNumber: result.phoneNumber,
            company: result.company,
            identity: result.identity,
            hobbies: result.hobbies,
            relationship: result.relationship,
            avatarData: result.avatarData,
            imageData: result.imageData,
            isEditMode: existingContact != nil,  // 如果存在重名，设置为编辑模式
            existingContactId: existingContact?.id  // 如果存在重名，传入现有联系人ID
        )
        
        // 从 imageData 重建 UIImage
        var originalImage: UIImage? = nil
        if let image = UIImage(data: result.imageData) {
            originalImage = image
        }
        
        // 根据是否重名显示不同的提示文字
        let messageContent: String
        if existingContact != nil {
            messageContent = "检测到人脉库中已存在「\(result.name)」，可以调整后点击完成更新信息~"
            print("⚠️ 检测到重名联系人：\(result.name)，仍显示预览卡片供用户更新")
        } else {
            messageContent = "为你生成了人脉信息，可以调整后点击完成~"
        }
        
        var contactMessage = ChatMessage(
            role: .agent,
            content: messageContent
        )
        contactMessage.contactPreview = contactPreview
        if let image = originalImage {
            contactMessage.images = [image]  // 保存原始图片供"识别错了"使用
        }
        appState.chatMessages.append(contactMessage)
        appState.saveMessageToStorage(contactMessage, modelContext: modelContext)
        print("✅ 人脉预览消息已创建")
    }
    
    // 创建报销预览消息
    private func createExpensePreviewMessage(result: ExpenseParseResult) {
        let expensePreview = ExpensePreviewData(
            amount: result.amount,
            title: result.title,
            category: result.category,
            event: nil, // 事件字段为空，让用户在预览中填写
            occurredAt: result.occurredAt,
            notes: result.notes,
            imageData: result.imageData
        )
        
        // 从 imageData 数组重建 UIImage 数组
        var originalImages: [UIImage] = []
        for data in result.imageData {
            if let image = UIImage(data: data) {
                originalImages.append(image)
            }
        }

        var expenseMessage = ChatMessage(role: .agent, content: "为你生成了报销信息，可以调整后点击完成~")
        expenseMessage.expensePreview = expensePreview
        if !originalImages.isEmpty {
            expenseMessage.images = originalImages  // 保存原始图片供"识别错了"使用
        }
        appState.chatMessages.append(expenseMessage)
        appState.saveMessageToStorage(expenseMessage, modelContext: modelContext)
        print("✅ 报销预览消息已创建")
    }

    // 🆕 处理开票二维码
    private func handleInvoiceQRCode(_ qrCode: String, agentMessageId: UUID) async {
        print("🎫 开始处理开票二维码...")

        // 获取公司开票信息
        let companies = try? modelContext.fetch(FetchDescriptor<CompanyInfo>())
        guard let companyInfo = companies?.first, companyInfo.hasBasicInfo else {
            print("⚠️ 未设置公司开票信息")

            await MainActor.run {
                // 移除加载消息
                if let idx = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                    appState.chatMessages.remove(at: idx)
                }

                // 提示用户设置公司信息
                let tipMessage = ChatMessage(
                    role: .agent,
                    content: "检测到开票二维码！但你还没有设置公司开票信息哦~\n\n请先在设置中填写公司名称和税号，之后就可以自动开票啦！"
                )
                appState.chatMessages.append(tipMessage)
                appState.saveMessageToStorage(tipMessage, modelContext: modelContext)

                HapticFeedback.warning()
            }
            return
        }

        print("✅ 已获取公司信息: \(companyInfo.companyName)")

        await MainActor.run {
            // 移除加载消息
            if let idx = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                appState.chatMessages.remove(at: idx)
            }

            // 显示开票提示消息
            let confirmMessage = ChatMessage(
                role: .agent,
                content: "检测到开票二维码！\n\n即将为【\(companyInfo.companyName)】自动申请开票，请稍候..."
            )
            appState.chatMessages.append(confirmMessage)
            appState.saveMessageToStorage(confirmMessage, modelContext: modelContext)

            HapticFeedback.success()

            // 延迟一下，让用户看到提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // 打开自动开票 WebView
                self.invoiceURL = qrCode
                self.companyInfoForInvoice = companyInfo
                self.showAutoInvoiceWebView = true
            }
        }
    }

    // 提取待处理的报销数据（已废弃，保留以防编译错误）
    private func extractPendingExpenseData(from message: ChatMessage) -> ExpenseParseResult? {
        guard let notes = message.notes, !notes.isEmpty else { return nil }
        let components = notes.split(separator: "|")
        guard components.count >= 6 else { return nil }
        
        guard let amount = Double(components[0]),
              let occurredAtTimestamp = Double(components[3]),
              let _ = Int(components[5]) else {
            return nil
        }
        
        let title = String(components[1])
        let category = String(components[2]).isEmpty ? nil : String(components[2])
        let occurredAt = Date(timeIntervalSince1970: occurredAtTimestamp)
        let notesText = String(components[4]).isEmpty ? nil : String(components[4])
        
        // 注意：这里无法恢复imageData，需要在调用时重新获取
        return ExpenseParseResult(
            amount: amount,
            title: title,
            category: category,
            occurredAt: occurredAt,
            notes: notesText,
            imageData: [] // 需要在调用时重新获取
        )
    }
    
    // 处理报销事件回复
    private func handleExpenseEventReply(event: String, expenseData: ExpenseParseResult, messageId: UUID) async {
        // 需要重新获取图片数据，从询问消息之前的用户消息中获取
        var imageData: [Data] = []
        
        // 找到询问消息的索引
        if let askMessageIndex = appState.chatMessages.firstIndex(where: { msg in
            msg.role == .agent && msg.content.contains("报销项目") && msg.content.contains("什么情形")
        }) {
            // 从询问消息之前查找用户发送的图片消息
            for i in (0..<askMessageIndex).reversed() {
                let msg = appState.chatMessages[i]
                if msg.role == .user && !msg.images.isEmpty {
                    imageData = msg.images.compactMap { $0.jpegData(compressionQuality: 0.8) }
                    break
                }
            }
        }
        
        await MainActor.run {
        let expensePreview = ExpensePreviewData(
                amount: expenseData.amount,
                title: expenseData.title,
                category: expenseData.category,
                event: event.trimmingCharacters(in: .whitespaces),
                occurredAt: expenseData.occurredAt,
                notes: expenseData.notes,
                imageData: imageData.isEmpty ? expenseData.imageData : imageData
            )
            
            if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[idx]
                msg.content = "为你生成了报销信息，可以调整后点击完成~"
                msg.expensePreview = expensePreview
                appState.chatMessages[idx] = msg
                appState.saveMessageToStorage(msg, modelContext: modelContext)
                HapticFeedback.success()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 聊天顶部栏
                ChatRoomTopBar(
                    isTextFieldFocused: $isTextFieldFocused,
                    onBack: {
                        dismiss()
                    },
                    showHistory: $showHistory
                )

                // 聊天消息区
                ChatRoomMessagesArea(
                    isLoadingHistory: $isLoadingHistory,
                    isTextFieldFocused: $isTextFieldFocused
                )

                // 底部输入栏
                if !shouldHideInputBar {
                    ChatRoomInputBar(
                        displayText: $displayText,
                        isTextFieldFocused: $isTextFieldFocused,
                        onShowAutoInvoiceWebView: { url, companyInfo in
                            // 触发自动开票WebView
                            invoiceURL = url
                            companyInfoForInvoice = companyInfo
                            showAutoInvoiceWebView = true
                        }
                    )
                }
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.94))
            .navigationBarHidden(true)
            .environmentObject(appState)
            .environment(\.hideInputBar, $shouldHideInputBar)
            .sheet(isPresented: $showHistory) {
                ChatHistoryView()
                    .environment(\.modelContext, modelContext)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAutoInvoiceWebView) {
                if let companyInfo = companyInfoForInvoice {
                    AutoInvoiceWebView(
                        url: invoiceURL,
                        companyInfo: companyInfo,
                        onSuccess: {
                            // 开票成功
                            let successMessage = ChatMessage(
                                role: .agent,
                                content: "✅ 开票申请已成功提交！请注意查收发票~"
                            )
                            appState.chatMessages.append(successMessage)
                            appState.saveMessageToStorage(successMessage, modelContext: modelContext)
                        },
                        onError: { error in
                            // 开票失败
                            let errorMessage = ChatMessage(
                                role: .agent,
                                content: "❌ 自动开票失败：\(error)\n\n请手动打开链接完成开票。"
                            )
                            appState.chatMessages.append(errorMessage)
                            appState.saveMessageToStorage(errorMessage, modelContext: modelContext)
                        }
                    )
                        .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: appState.shouldSendClipboardImage) { oldValue, newValue in
                // 监听截图发送标记的变化
                if newValue {
                    print("📸 检测到截图分析请求（onChange），准备从剪贴板发送")
                    appState.shouldSendClipboardImage = false  // 立即清空标记，避免重复触发
                    
                    // 延迟确保准备就绪后，从剪贴板直接发送
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("🚀 调用 sendScreenshotFromClipboard")
                        sendScreenshotFromClipboard()
                    }
                }
            }
            .onAppear {
                print("💬 ChatRoomPage onAppear")
                print("   - shouldSendClipboardImage: \(appState.shouldSendClipboardImage)")
                print("   - 当前消息数: \(appState.chatMessages.count)")

                appState.currentMode = initialMode
                
                // 保存是否需要发送截图的标志
                let needsSendScreenshot = appState.shouldSendClipboardImage
                if needsSendScreenshot {
                    print("📸 检测到截图分析请求，将在加载历史记录后发送")
                    appState.shouldSendClipboardImage = false
                }

                        // 异步加载最近的聊天记录（无论是否有截图都要加载）
                Task {
                    print("🚀 开始懒加载聊天记录...")
                    appState.loadRecentMessages(modelContext: modelContext, limit: 50)

                    await MainActor.run {
                            print("✅ 聊天记录加载完成，消息数: \(appState.chatMessages.count)")
                            
                            // 加载完成，隐藏加载图层
                            isLoadingHistory = false

                        // 如果需要发送截图，在历史记录加载完成后发送
                        if needsSendScreenshot {
                            print("📸 历史记录加载完成，现在发送截图")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                sendScreenshotFromClipboard()
                            }
                        } else {
                            // 延迟聚焦输入框
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isTextFieldFocused = true
                            }
                        }
                    }
                }
            }
            .onDisappear {
                // 关闭聊天室时更新当天的聊天总结
                appState.updateTodaySummary(modelContext: modelContext)
            }
        }
    }
}

// ===== 聊天室顶部栏 =====
struct ChatRoomTopBar: View {
    @EnvironmentObject var appState: AppState
    @FocusState.Binding var isTextFieldFocused: Bool
    let onBack: () -> Void
    @Binding var showHistory: Bool
    
    var body: some View {
        HStack {
            Button(action: {
                HapticFeedback.light()
                isTextFieldFocused = false
                onBack()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black)
                )
            }
            
            Spacer()

            // 圆圆标题 - 霓虹渐变，AI输入时显示Typing...
            ChatRoomTypingTitle()

            Spacer()
            
            Button(action: {
                HapticFeedback.light()
                isTextFieldFocused = false
                showHistory = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                    Text("历史")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // 主背景 - 和聊天区域一致
                Color(red: 0.95, green: 0.95, blue: 0.94)

                // 底部虚化渐变过渡
                VStack(spacing: 0) {
                    Spacer()

                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.95, blue: 0.94),
                            Color(red: 0.95, green: 0.95, blue: 0.94).opacity(0.7),
                            Color(red: 0.95, green: 0.95, blue: 0.94).opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)
                    .blur(radius: 2)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击顶部栏空白处时，取消输入框焦点，收起键盘
            if isTextFieldFocused {
                isTextFieldFocused = false
            }
        }
    }
}

// Typing标题视图
struct ChatRoomTypingTitle: View {
    @EnvironmentObject var appState: AppState
    @State private var dotCount = 0

    var body: some View {
        Text(displayText)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .italic()
            .foregroundColor(Color.white)
            .shadow(color: Color.black, radius: 0, x: -1, y: -1)
            .shadow(color: Color.black, radius: 0, x: 1, y: -1)
            .shadow(color: Color.black, radius: 0, x: -1, y: 1)
            .shadow(color: Color.black, radius: 0, x: 1, y: 1)
            .shadow(color: Color.black, radius: 1, x: 0, y: 0)
            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.7), radius: 8, x: 0, y: 0)
            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.5), radius: 14, x: 0, y: 0)
            .onAppear {
                startDotAnimation()
            }
    }

    private var displayText: String {
        if appState.isAgentTyping {
            return "Typing" + String(repeating: ".", count: dotCount)
        } else {
            return "圆圆"
        }
    }

    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                if appState.isAgentTyping {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        dotCount = (dotCount % 3) + 1
                    }
                } else {
                    dotCount = 0
                }
            }
        }
    }
}

// ===== 聊天消息区 =====
struct ChatRoomMessagesArea: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Binding var isLoadingHistory: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    @State private var anchorMessageId: UUID? = nil
    
    // 获取最早的消息时间戳（用于加载更早的消息）
    private var oldestMessageTimestamp: Date? {
        appState.chatMessages.first?.timestamp
    }
    
    // 下拉刷新加载更多历史消息
    private func loadMoreHistory() async {
        guard let oldestTimestamp = oldestMessageTimestamp else { return }
        
        print("🔄 下拉刷新：开始加载更早的消息")
        
        // 保存当前第一条消息的ID，用于加载后保持滚动位置
        await MainActor.run {
            anchorMessageId = appState.chatMessages.first?.id
        }
        
        // 加载更早的50条消息
        appState.loadOlderMessages(modelContext: modelContext, before: oldestTimestamp, limit: 50)
        
        // 等待加载完成
        while appState.isLoadingOlderMessages {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        }
        
        print("✅ 下拉刷新：历史消息加载完成")
    }
    
    var body: some View {
        ZStack {
            // 消息列表（ScrollView）
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        // 显示所有消息
                        ForEach(appState.chatMessages) { message in
                            // 如果是打招呼消息，显示时间分块标签
                            if message.isGreeting {
                                TimeStampView(timestamp: message.timestamp)
                                    .padding(.top, 8)
                            }

                            // 如果是空的AI消息且正在输入中，不显示（避免两个头像）
                            if !(message.role == .agent && message.content.trimmingCharacters(in: .whitespaces).isEmpty && appState.isAgentTyping) {
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }

                        if appState.isAgentTyping {
                            ChatRoomTypingIndicator()
                                .id("typing")
                        }

                        // 底部占位符，用于滚动到底部
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 点击消息区域时，取消输入框焦点，收起键盘
                        if isTextFieldFocused {
                            isTextFieldFocused = false
                        }
                    }
                }
                .refreshable {
                    // 下拉刷新加载更早的消息
                    await loadMoreHistory()
                }
                .onChange(of: appState.isLoadingOlderMessages) { _, isLoading in
                // 当加载完成后，滚动回之前的位置
                if !isLoading, let anchorId = anchorMessageId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(anchorId, anchor: .top)
                        }
                        anchorMessageId = nil
                    }
                }
                }
                .onChange(of: isLoadingHistory) { _, isLoading in
                // 加载完成后滚动到底部
                if !isLoading {
                    print("📜 历史记录加载完成，准备滚动到底部")
                    print("   - 消息总数: \(appState.chatMessages.count)")

                    // 由于使用懒加载，数据量小，延迟可以减少
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("🚀 开始执行滚动到底部（onChange）")

                        // 直接滚动到底部占位符
                        if appState.isAgentTyping {
                            print("   - 滚动到 typing 指示器")
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        } else if !appState.chatMessages.isEmpty {
                            print("   - 滚动到底部占位符")
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }

                        print("✅ 滚动完成")
                    }
                }
                }
                .onChange(of: isTextFieldFocused) { oldValue, isFocused in
                    print("📍 MessagesArea: isTextFieldFocused 变化 \(oldValue) -> \(isFocused)")
                    // 当输入框获得焦点时，延迟滚动到底部，等待键盘完全弹起
                    if isFocused {
                        print("⌨️ 键盘即将弹起，0.4秒后滚动到底部")
                        // 延迟0.4秒，确保键盘动画完成后再滚动
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            print("📜 执行滚动到底部")
                            withAnimation(.easeOut(duration: 0.25)) {
                                if appState.isAgentTyping {
                                    proxy.scrollTo("typing", anchor: .bottom)
                                } else if !appState.chatMessages.isEmpty {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .onChange(of: appState.chatMessages.count) { _, _ in
                    // 当消息数量变化时（新消息添加），自动滚动到底部
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            if appState.isAgentTyping {
                                proxy.scrollTo("typing", anchor: .bottom)
                            } else if !appState.chatMessages.isEmpty {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: appState.isAgentTyping) { _, isTyping in
                    // 当 AI 开始或停止输入时，滚动到相应位置
                    if isTyping {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }
                .onAppear {
                    // 视图出现时，滚动到底部
                    // 由于懒加载，消息数量少，延迟可以减少
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        print("🎯 MessagesArea onAppear 触发滚动到底部")
                        print("   - 消息数量: \(appState.chatMessages.count)")
                        print("   - isAgentTyping: \(appState.isAgentTyping)")

                        withAnimation {
                            if appState.isAgentTyping {
                                proxy.scrollTo("typing", anchor: .bottom)
                            } else if !appState.chatMessages.isEmpty {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    
                    // 监听键盘弹起通知，触发滚动
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("KeyboardDidShow"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        print("📬 收到键盘弹起通知，0.4秒后滚动到底部")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            print("📜 执行滚动到底部（通过通知）")
                            withAnimation(.easeOut(duration: 0.25)) {
                                if appState.isAgentTyping {
                                    proxy.scrollTo("typing", anchor: .bottom)
                                } else if !appState.chatMessages.isEmpty {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                ZStack {
                    Color(red: 0.95, green: 0.95, blue: 0.94)

                    // 顶部虚化渐变过渡
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                        .blur(radius: 3)

                        Spacer()
                    }
                }
            )

            // 加载图层（仅在加载历史记录时显示）
            if isLoadingHistory {
                ChatMessagesLoadingOverlay()
                    .transition(.opacity)
            }
        }
    }
}

// ===== 聊天消息加载图层 =====
struct ChatMessagesLoadingOverlay: View {
    @State private var pulseAnimation1: CGFloat = 0
    @State private var pulseAnimation2: CGFloat = 0
    @State private var pulseAnimation3: CGFloat = 0
    @State private var textOpacity: Double = 0.3

    var body: some View {
        ZStack {
            // 半透明背景 + 毛玻璃效果
            Color(red: 0.95, green: 0.95, blue: 0.94)
                .opacity(0.95)
                .background(.ultraThinMaterial)

            // 顶部虚化渐变（保持与消息区一致）
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.5),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                .blur(radius: 3)

                Spacer()
            }

            // 中央加载动画
            VStack(spacing: 20) {
                // 脉动圆圈动画
                ZStack {
                    // 第三层圆圈（最外层）
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3),
                                    Color(red: 0.75, green: 0.95, blue: 0.2).opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseAnimation3)
                        .opacity(1 - pulseAnimation3)

                    // 第二层圆圈（中间层）
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.5),
                                    Color(red: 0.75, green: 0.95, blue: 0.2).opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 60, height: 60)
                        .scaleEffect(pulseAnimation2)
                        .opacity(1 - pulseAnimation2)

                    // 第一层圆圈（最内层）
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25),
                                    Color(red: 0.75, green: 0.95, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulseAnimation1)
                        .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.5), radius: 12, x: 0, y: 0)
                }

                // 加载文字
                Text("正在加载聊天记录...")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.6))
                    .opacity(textOpacity)
            }
        }
        .ignoresSafeArea(edges: [])
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // 脉动动画 - 三层圆圈依次扩散
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            pulseAnimation1 = 1.5
        }

        withAnimation(.easeOut(duration: 1.5).delay(0.2).repeatForever(autoreverses: false)) {
            pulseAnimation2 = 1.5
        }

        withAnimation(.easeOut(duration: 1.5).delay(0.4).repeatForever(autoreverses: false)) {
            pulseAnimation3 = 1.5
        }

        // 文字淡入淡出动画
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            textOpacity = 1.0
        }
    }
}

// ===== 历史记录加载气泡 =====
struct HistoryLoadingBubble: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .opacity(opacityForDot(index))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
            )
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .onAppear {
            startAnimation()
        }
    }
    
    private func opacityForDot(_ index: Int) -> Double {
        let adjustedPhase = (animationPhase + index) % 3
        return adjustedPhase == 0 ? 1.0 : 0.3
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// ===== 时间分块标签 =====
struct TimeStampView: View {
    let timestamp: Date
    
    var body: some View {
        Text(formattedTimestamp)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color.black.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.6))
            )
            .padding(.vertical, 4)
    }
    
    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: timestamp)
    }
}

// ===== 聊天气泡组件 =====
// 图片项结构体，用于ForEach的唯一标识
struct ImageItem: Identifiable {
    let id: ObjectIdentifier
    let index: Int
    let image: UIImage
}

struct ChatBubbleView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    let message: ChatMessage
    @State private var selectedImageGallery: ImageGallery? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .agent {
                // AI消息 - 左对齐（不显示头像）
                VStack(alignment: .leading, spacing: 6) {
                    // 显示图片（如果有）- 但如果有预览气泡则不显示（重新分类气泡需要显示图片）
                    if !message.images.isEmpty && 
                       message.todoPreview == nil && 
                       message.contactPreview == nil && 
                       message.expensePreview == nil {
                        ForEach(Array(message.images.enumerated()), id: \.offset) { index, image in
                            Button(action: {
                                HapticFeedback.light()
                                selectedImageGallery = ImageGallery(images: message.images, initialIndex: index)
                            }) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: 140, maxHeight: 140)
                                    .cornerRadius(12)
                                    .clipped()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: 140, maxHeight: 140)
                            .contentShape(Rectangle())
                        }
                    }
                    
                    // 检查是否有待处理操作
                    if let pendingAction = message.pendingAction {
                        // 显示询问文本和操作按钮（融合在一个气泡中）
                        VStack(alignment: .leading, spacing: 12) {
                            // 如果还没有询问语，显示三个点等待动画
                            if message.displayedContent.isEmpty {
                                LoadingDotsView()
                            } else {
                                // 询问文本
                                Text(message.displayedContent)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.black.opacity(0.85))
                            }
                            
                            // 操作按钮（只在showActionButtons为true时显示，带动画）
                            if message.showActionButtons {
                                if pendingAction == .imageAnalysis {
                                    ImageActionButtons(
                                        messageId: message.id,
                                        pendingAction: pendingAction
                                    )
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                } else if pendingAction == .textAnalysis {
                                    TextActionButtons(
                                        messageId: message.id,
                                        pendingAction: pendingAction
                                    )
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                        )
                    } else if let todoPreview = message.todoPreview {
                        // 显示待办预览气泡
                        VStack(alignment: .leading, spacing: 8) {
                            // 如果有文字内容，先显示文字
                            if !message.displayedContent.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(message.displayedContent)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.black.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // 待办预览（包含识别错了按钮）
                            TodoPreviewBubble(
                                messageId: message.id,
                                todoPreview: todoPreview,
                                originalImages: message.images
                            )
                        }
                    } else if let contactPreview = message.contactPreview {
                        // 显示人脉预览气泡
                        VStack(alignment: .leading, spacing: 8) {
                            // 如果有文字内容，先显示文字
                            if !message.displayedContent.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(message.displayedContent)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.black.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // 人脉预览（包含识别错了按钮）
                            ContactPreviewBubble(
                                messageId: message.id,
                                contactPreview: contactPreview,
                                originalImages: message.images
                            )
                        }
                    } else if let expensePreview = message.expensePreview {
                        // 显示报销预览气泡
                        VStack(alignment: .leading, spacing: 8) {
                            // 如果有文字内容，先显示文字
                            if !message.displayedContent.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(message.displayedContent)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.black.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // 报销预览（包含识别错了按钮）
                            ExpensePreviewBubble(
                                messageId: message.id,
                                expensePreview: expensePreview,
                                originalImages: message.images
                            )
                        }
                    } else if message.showReclassifyBubble {
                        // 显示重新分类气泡
                        ReclassifyBubble(
                            originalImages: message.images,
                            onConfirm: { intent, note in
                                // 调用处理方法
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("HandleReclassifyConfirm"),
                                    object: nil,
                                    userInfo: ["messageId": message.id, "intent": intent, "note": note]
                                )
                            },
                            onCancel: {
                                // 调用取消处理
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("HandleReclassifyCancel"),
                                    object: nil,
                                    userInfo: ["messageId": message.id]
                                )
                            }
                        )
                    } else if !message.displayedContent.trimmingCharacters(in: .whitespaces).isEmpty {
                        // 显示文字内容（只在有内容时显示）
                        Text(message.displayedContent)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.black.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(isErrorMessage ? Color.red.opacity(0.1) : Color.white)
                                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .leading)
                
                Spacer()
            } else {
                // 用户消息 - 右对齐，头像在顶部
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    // 显示图片（如果有）
                    if !message.images.isEmpty {
                        ForEach(Array(message.images.enumerated()), id: \.offset) { index, image in
                            Button(action: {
                                HapticFeedback.light()
                                selectedImageGallery = ImageGallery(images: message.images, initialIndex: index)
                            }) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: 140, maxHeight: 140)
                                    .cornerRadius(12)
                                    .clipped()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: 140, maxHeight: 140)
                            .contentShape(Rectangle())
                        }
                    }
                    
                    // 显示文字内容
                    if !message.displayedContent.isEmpty {
                        Text(message.displayedContent)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.white)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.black)
                                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
                
                // 用户头像
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 1.0, blue: 0.25),
                                Color(red: 0.75, green: 0.95, blue: 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.white)
                    )
            }
        }
        .padding(.horizontal, 12)
        .fullScreenCover(item: $selectedImageGallery) { gallery in
            FullScreenImageGallery(
                images: gallery.images,
                initialIndex: gallery.initialIndex,
                onDismiss: {
                    selectedImageGallery = nil
                }
            )
        }
    }
    
    private var isErrorMessage: Bool {
        if case .error = message.streamingState {
            return true
        }
        return false
    }
}

// 正在输入提示
struct ChatRoomTypingIndicator: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .opacity(opacityForDot(index))
                        .animation(.easeInOut(duration: 0.4), value: animationPhase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
            )
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .id("typing")
        .onAppear {
            startAnimation()
        }
    }
    
    private func opacityForDot(_ index: Int) -> Double {
        let adjustedPhase = (animationPhase + index) % 3
        return adjustedPhase == 0 ? 1.0 : 0.3
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            animationPhase = (animationPhase + 1) % 3
        }
    }
}

// ===== 聊天输入栏 =====
struct ChatRoomInputBar: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Binding var displayText: String
    @FocusState.Binding var isTextFieldFocused: Bool
    @State private var showImagePicker = false
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isOptimizingText = false  // 是否正在优化文本
    @State private var internalFocused: Bool = false  // 内部焦点状态（用于桥接FocusState）
    @State private var isLongPressing = false  // 是否正在长按
    @State private var dragStartLocation: CGPoint?  // 拖拽起始位置

    // 回调：触发自动开票WebView
    var onShowAutoInvoiceWebView: ((String, CompanyInfo) -> Void)?
    
    // 开始录音
    private func startRecording() {
        guard !appState.isAgentTyping && !isOptimizingText else { return }
        
        // 触感反馈
        HapticFeedback.medium()
        isLongPressing = true
        
        // 开始录音，实时转文字
        speechRecognizer.startRecording { text in
            displayText = text
        }
    }
    
    // 停止录音
    private func stopRecording() {
        if speechRecognizer.isRecording {
            HapticFeedback.light()
            speechRecognizer.stopRecording()
            isLongPressing = false
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 输入栏
            HStack(spacing: 8) {
                // 条形输入框
                TextField("发送消息或按住说话", text: $displayText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.black, lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    )
                    .simultaneousGesture(
                        // 使用 DragGesture 检测按下和松开，零延迟进入录音
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartLocation == nil {
                                    dragStartLocation = value.startLocation
                                }
                                
                                // 移动超过阈值视为拖拽，取消录音尝试
                                if let start = dragStartLocation {
                                    let distance = sqrt(pow(value.location.x - start.x, 2) + pow(value.location.y - start.y, 2))
                                    if distance > 5 {
                                        dragStartLocation = nil
                                        return
                                    }
                                }
                                
                                // 首次按下立即启动录音
                                if !isLongPressing && !speechRecognizer.isRecording {
                                    HapticFeedback.medium()
                                    if isTextFieldFocused {
                                        // 先收起键盘，再立刻开始录音，避免冲突
                                        isTextFieldFocused = false
                                        DispatchQueue.main.async {
                                            startRecording()
                                        }
                                    } else {
                                        startRecording()
                                    }
                                }
                            }
                            .onEnded { _ in
                                dragStartLocation = nil
                                if speechRecognizer.isRecording {
                                    stopRecording()
                                }
                            }
                    )
                    .onChange(of: isTextFieldFocused) { oldValue, newValue in
                        // 同步焦点状态
                        internalFocused = newValue
                        // 键盘弹起时，发送通知触发滚动
                        if newValue {
                            print("⌨️ 键盘弹起，发送滚动通知")
                            NotificationCenter.default.post(name: NSNotification.Name("KeyboardDidShow"), object: nil)
                            // 点击focus时添加触感反馈
                            HapticFeedback.light()
                        }
                        // 如果键盘弹起，停止录音
                        if newValue && speechRecognizer.isRecording {
                            speechRecognizer.stopRecording()
                            isLongPressing = false
                        }
                    }
                    .onChange(of: internalFocused) { oldValue, newValue in
                        // 从外部同步焦点状态
                        if isTextFieldFocused != newValue {
                            isTextFieldFocused = newValue
                        }
                    }
                
                // 工具按钮组（放在输入框右边）
                HStack(spacing: 8) {
                    // 附件按钮
                    Button(action: {
                        HapticFeedback.light()
                        isTextFieldFocused = false
                        print("🖼️ 打开图片选择器")
                        showImagePicker = true
                    }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.black)
                            )
                    }
                    .disabled(appState.isAgentTyping)
                    
                    // 发送按钮
                    Button(action: {
                        HapticFeedback.medium()
                        isTextFieldFocused = false

                        // 如果正在录音，先停止录音
                        if speechRecognizer.isRecording {
                            speechRecognizer.stopRecording()
                            isLongPressing = false
                        }

                        let currentText = displayText.trimmingCharacters(in: .whitespaces)
                        if !currentText.isEmpty {
                            displayText = ""
                            sendTextMessageWithText(currentText)
                        }
                    }) {
                        let isActive = !displayText.isEmpty && !appState.isAgentTyping

                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isActive ? Color.white : Color.gray.opacity(0.6))
                            .shadow(color: isActive ? Color.black : Color.clear, radius: 0, x: -1, y: -1)
                            .shadow(color: isActive ? Color.black : Color.clear, radius: 0, x: 1, y: -1)
                            .shadow(color: isActive ? Color.black : Color.clear, radius: 0, x: -1, y: 1)
                            .shadow(color: isActive ? Color.black : Color.clear, radius: 0, x: 1, y: 1)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(isActive ? Color.white : Color.gray.opacity(0.3))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black, lineWidth: isActive ? 2 : 0)
                                    )
                            )
                    }
                    .disabled(displayText.isEmpty || appState.isAgentTyping)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: internalFocused)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.95))
                        .ignoresSafeArea(edges: .bottom)
                    
                    // 顶部虚化渐变过渡
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.2),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .blur(radius: 2)
                        
                        Spacer()
                    }
                }
            )
        }
        .sheet(isPresented: $showImagePicker, onDismiss: {
            print("📷 图片选择器已关闭")
        }) {
            ImagePickerView(onImagesSelected: { images in
                print("📸 从选择器接收到 \(images.count) 张图片，立即发送")
                // 选择图片后立即发送
                sendImagesDirectly(images)
            })
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            speechRecognizer.requestAuthorization()
            
            // 监听重新分类确认通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("HandleReclassifyConfirm"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let messageId = userInfo["messageId"] as? UUID,
                   let intent = userInfo["intent"] as? String {
                    let note = userInfo["note"] as? String ?? ""
                    handleReclassifyConfirm(messageId: messageId, intent: intent, additionalNote: note)
                }
            }
            
            // 监听重新分类取消通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("HandleReclassifyCancel"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let messageId = userInfo["messageId"] as? UUID {
                    handleReclassifyCancel(messageId: messageId)
                }
            }
            
            // 监听"识别错了"通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("HandleWrongClassification"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let messageId = userInfo["messageId"] as? UUID,
                   let images = userInfo["images"] as? [UIImage] {
                    handleWrongClassification(for: messageId, images: images)
                }
            }
        }
        .onDisappear {
            // 移除通知监听
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("HandleReclassifyConfirm"),
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("HandleReclassifyCancel"),
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("HandleWrongClassification"),
                object: nil
            )
        }
    }
    
    // 优化语音识别文本
    private func optimizeSpeechText(_ text: String) async {
        guard !text.isEmpty else { return }
        
        await MainActor.run {
            isOptimizingText = true
        }
        
        do {
            print("🔧 开始优化语音文本...")
            let optimizedText = try await QwenAPIService.optimizeSpeechText(text)
            
            await MainActor.run {
                // 更新输入框文本为优化后的内容
                displayText = optimizedText
                isOptimizingText = false
                HapticFeedback.success()
                print("✅ 文本优化完成")
            }
        } catch {
            print("❌ 文本优化失败: \(error)")
            await MainActor.run {
                // 优化失败时保留原文本
                isOptimizingText = false
            }
        }
    }
    
    // 发送文字消息（从输入框读取）
    private func sendTextMessage() {
        let messageText = displayText.trimmingCharacters(in: .whitespaces)
        guard !messageText.isEmpty && !appState.isAgentTyping else { 
            print("⚠️ 文字为空或AI正在输入")
            return 
        }
        
        // 清空输入框
        displayText = ""
        
        // 调用内部发送函数
        sendTextMessageWithText(messageText)
    }
    
    // 发送文字消息（使用指定文本）
    private func sendTextMessageWithText(_ messageText: String) {
        guard !messageText.isEmpty && !appState.isAgentTyping else { 
            print("⚠️ 文字为空或AI正在输入")
            return 
        }
        
        HapticFeedback.success()
        
        print("📤 发送文字消息: \(messageText)")
        
        // 添加用户消息
        let userMessage = ChatMessage(role: .user, content: messageText)
        appState.chatMessages.append(userMessage)
        appState.saveMessageToStorage(userMessage, modelContext: modelContext)
        print("✅ 用户文字消息已添加并保存")
        
        // 创建AI消息
        let agentMessage = ChatMessage(role: .agent, content: "")
        appState.chatMessages.append(agentMessage)
        let messageId = agentMessage.id
        print("✅ AI消息已添加")
        
        // 先判断用户意图
        Task {
            do {
                let intent = try await QwenOmniService.detectUserIntent(text: messageText)
                print("🎯 识别到意图: \(intent)")
                
                switch intent {
                case "todo":
                    // 生成待办
                    await handleTextToTodo(messageText: messageText, messageId: messageId)
                    
                case "contact":
                    // 生成人脉
                    await handleTextToContact(messageText: messageText, messageId: messageId)
                    
                case "expense":
                    // 生成报销
                    await handleTextToExpense(messageText: messageText, messageId: messageId)
                    
                default:
                    // 普通聊天
                    await handleNormalChat(messageId: messageId)
                }
            } catch {
                print("❌ 意图识别失败: \(error)，默认进行聊天")
                // 识别失败，默认聊天
                await handleNormalChat(messageId: messageId)
            }
        }
    }
    
    // 处理文字生成待办
    private func handleTextToTodo(messageText: String, messageId: UUID) async {
        await MainActor.run {
            if let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[index]
                msg.content = "正在解析文字生成待办..."
                appState.chatMessages[index] = msg
            }
        }
        
        do {
            let result = try await QwenOmniService.parseTextForTodo(text: messageText)
            print("✅ 文字解析成功: \(result.title)")
            
            await MainActor.run {
                let todoPreview = TodoPreviewData(
                    title: result.title,
                    description: result.description,
                    startTime: result.startTime,
                    endTime: result.endTime,
                    reminderTime: result.startTime.addingTimeInterval(-15 * 60),
                    imageData: result.imageData
                )
                
                if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                    var msg = appState.chatMessages[idx]
                    msg.content = "为你生成了待办事项，可以调整时间后点击完成~"
                    msg.todoPreview = todoPreview
                    appState.chatMessages[idx] = msg
                    appState.saveMessageToStorage(msg, modelContext: modelContext)
                    HapticFeedback.success()
                }
            }
        } catch {
            print("❌ 解析文字失败: \(error)")
            await handleNormalChat(messageId: messageId)
        }
    }
    
    // 处理文字生成人脉
    private func handleTextToContact(messageText: String, messageId: UUID) async {
        await MainActor.run {
            if let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[index]
                msg.content = "正在解析文字生成人脉..."
                appState.chatMessages[index] = msg
            }
        }
        
        do {
            let result = try await QwenOmniService.parseTextForContact(text: messageText)
            print("✅ 文字解析成功: \(result.name)")
            
            await MainActor.run {
                let allContacts = try? modelContext.fetch(FetchDescriptor<Contact>(sortBy: [SortDescriptor(\Contact.name)]))
                let existingContact = allContacts?.first(where: { $0.name == result.name })
                
                // 准备预览数据（无论是否重名都显示预览）
                let contactPreview = ContactPreviewData(
                    name: result.name,
                    phoneNumber: result.phoneNumber,
                    company: result.company,
                    identity: result.identity,
                    hobbies: result.hobbies,
                    relationship: result.relationship,
                    avatarData: result.avatarData,
                    imageData: result.imageData,
                    isEditMode: false,
                    existingContactId: existingContact?.id  // 如果存在重名，传入现有联系人ID
                )
                
                // 根据是否重名显示不同的提示文字
                let messageContent: String
                if existingContact != nil {
                    messageContent = "检测到人脉库中已存在「\(result.name)」，可以调整后点击完成更新信息~"
                    print("⚠️ 检测到重名联系人：\(result.name)，仍显示预览卡片供用户更新")
                } else {
                    messageContent = "为你生成了人脉信息，可以调整后点击完成~"
                }
                
                if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                    var msg = appState.chatMessages[idx]
                    msg.content = messageContent
                    msg.contactPreview = contactPreview
                    appState.chatMessages[idx] = msg
                    appState.saveMessageToStorage(msg, modelContext: modelContext)
                    HapticFeedback.success()
                }
            }
        } catch {
            print("❌ 解析文字失败: \(error)")
            await handleNormalChat(messageId: messageId)
        }
    }
    
    // 处理文字生成报销
    private func handleTextToExpense(messageText: String, messageId: UUID) async {
        await MainActor.run {
            if let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[index]
                msg.content = "正在解析文字生成报销..."
                appState.chatMessages[index] = msg
            }
        }
        
        do {
            let result = try await QwenOmniService.parseTextForExpense(text: messageText)
            print("✅ 文字解析成功: \(result.title) - ¥\(result.amount)")
            
            await MainActor.run {
                // 移除加载消息
                if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                    appState.chatMessages.remove(at: idx)
                }
                // 直接创建报销预览
                createExpensePreviewMessage(result: result)
            }
        } catch {
            print("❌ 解析文字失败: \(error)")
            await handleNormalChat(messageId: messageId)
        }
    }
    
    // 处理普通聊天
    private func handleNormalChat(messageId: UUID) async {
        appState.isAgentTyping = true
        appState.startStreaming(messageId: messageId)

        await SmartModelRouter.sendMessageStream(
            messages: appState.chatMessages,
            mode: appState.currentMode,
            onComplete: { finalText in
                await self.appState.playResponse(finalText, for: messageId)
                await MainActor.run {
                    if let completedMessage = self.appState.chatMessages.first(where: { $0.id == messageId }) {
                        self.appState.saveMessageToStorage(completedMessage, modelContext: self.modelContext)
                    }
                }
            },
            onError: { error in
                self.appState.handleStreamingError(error, for: messageId)
                self.appState.isAgentTyping = false
            }
        )
    }
    
    // 直接发送图片（支持批量智能识别）
    private func sendImagesDirectly(_ images: [UIImage]) {
        guard !images.isEmpty && !appState.isAgentTyping else {
            print("⚠️ 图片为空或AI正在输入")
            return
        }

        HapticFeedback.success()

        print("📤 发送 \(images.count) 张图片，开始智能识别")

        // 添加用户消息（只包含图片，不含文字）
        let userMessage = ChatMessage(role: .user, images: images, content: "")
        appState.chatMessages.append(userMessage)
        appState.saveMessageToStorage(userMessage, modelContext: modelContext)
        print("✅ 用户图片消息已添加并保存")

        // 创建AI消息，显示处理状态
        let agentMessage = ChatMessage(role: .agent, content: "正在分析图片...")
        appState.chatMessages.append(agentMessage)
        let messageId = agentMessage.id
        print("✅ AI消息已添加")

        // 后台批量智能识别图片（包含二维码专线）
        Task {
            await processImagesWithQRCodeCheck(images: images, userMessageId: userMessage.id, agentMessageId: messageId)
        }
    }

    // 图片处理：优先检查二维码（专线），否则走AI分析
    private func processImagesWithQRCodeCheck(images: [UIImage], userMessageId: UUID, agentMessageId: UUID) async {
        print("🔍 开始智能分析\(images.count)张图片...")

        // 🆕 优先检查是否有开票二维码（专线）
        print("🔍 步骤1: 检查是否包含开票二维码...")
        let qrCodes = await QRCodeScanner.detectQRCodes(in: images)

        print("📊 二维码识别结果: 共识别到 \(qrCodes.count) 个二维码")
        if qrCodes.isEmpty {
            print("⚠️ 未识别到任何二维码，可能原因：")
            print("   - 图片中没有二维码")
            print("   - 二维码模糊或被遮挡")
            print("   - 二维码太小或太大")
        } else {
            for (index, qrCode) in qrCodes.enumerated() {
                let preview = qrCode.count > 100 ? "\(qrCode.prefix(100))..." : qrCode
                print("   二维码 \(index + 1): \(preview)")
            }
        }

        print("🔍 步骤2: 判断二维码类型...")
        if let invoiceQRCode = qrCodes.first(where: { QRCodeScanner.isInvoiceQRCode($0) }) {
            print("✅ 检测到开票二维码，进入自动开票流程")
            await handleInvoiceQRCodeInInputBar(invoiceQRCode, agentMessageId: agentMessageId)
            return
        }
        
        if !qrCodes.isEmpty {
            print("⚠️ 识别到二维码但不是开票链接，可能是：")
            print("   - 普通小票信息码")
            print("   - 商家二维码")
            print("   - 其他类型二维码")
        }

        print("ℹ️ 未检测到开票二维码，使用AI分析图片内容...")

        // 走原有的AI图片分析逻辑
        await performAIImageAnalysis(images: images, userMessageId: userMessageId, agentMessageId: agentMessageId)
    }

    // 处理开票二维码（InputBar专用）
    private func handleInvoiceQRCodeInInputBar(_ qrCode: String, agentMessageId: UUID) async {
        print("🎫 开始处理开票二维码...")
        print("🔗 二维码内容: \(qrCode)")

        // 获取公司信息
        let companyInfo = await getCompanyInfo()

        // 更新消息并打开WebView
        await MainActor.run {
            // 移除"正在分析"消息
            if let idx = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                appState.chatMessages.remove(at: idx)
            }

            // 添加成功消息
            let successMessage = ChatMessage(
                role: .agent,
                content: "✅ 已识别发票二维码，正在为你自动填写开票信息..."
            )
            appState.chatMessages.append(successMessage)
            appState.saveMessageToStorage(successMessage, modelContext: modelContext)

            // 通过回调触发WebView显示（直接使用二维码URL）
            print("🌐 准备打开自动开票WebView")
            onShowAutoInvoiceWebView?(qrCode, companyInfo)
        }
    }

    // 获取公司信息
    private func getCompanyInfo() async -> CompanyInfo {
        // 从数据库获取公司信息
        let descriptor = FetchDescriptor<CompanyInfo>(sortBy: [SortDescriptor(\CompanyInfo.companyName)])
        if let companyInfo = try? modelContext.fetch(descriptor).first {
            print("✅ 已获取公司信息: \(companyInfo.companyName)")
            return companyInfo
        }

        print("⚠️ 未找到公司信息，使用默认值")
        return CompanyInfo(
            companyName: "请设置公司名称",
            taxNumber: "请设置税号",
            phoneNumber: "请设置电话",
            email: "请设置邮箱",
            address: "请设置地址",
            bankName: "请设置开户行",
            bankAccount: "请设置银行账号"
        )
    }

    // 执行AI图片分析（原有逻辑）
    private func performAIImageAnalysis(images: [UIImage], userMessageId: UUID, agentMessageId: UUID) async {
        do {
            // 使用新的批量分析API
            let batchResult = try await QwenOmniService.analyzeMultipleImages(images: images)

            // 回到主线程更新UI
            await MainActor.run {
                // 检查是否有任何有效结果
                let hasAnyResult = !batchResult.todos.isEmpty || !batchResult.contacts.isEmpty || !batchResult.expenses.isEmpty

                if !hasAnyResult {
                    // 所有图片都无法识别，显示重新分类气泡
                    // 移除加载消息
                    if let index = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                        appState.chatMessages.remove(at: index)
                    }
                    
                    // 创建重新分类气泡消息
                    var reclassifyMessage = ChatMessage(
                        role: .agent,
                        content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
                    )
                    reclassifyMessage.showReclassifyBubble = true
                    reclassifyMessage.images = images  // 保存原始图片
                    appState.chatMessages.append(reclassifyMessage)
                    appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
                    return
                }
                
                // 检查是否识别出任何意图，如果都为空则显示重新分类气泡
                if batchResult.todos.isEmpty && batchResult.contacts.isEmpty && batchResult.expenses.isEmpty {
                    print("⚠️ AI未识别出任何意图，显示重新分类气泡让用户确认")
                    // 移除加载消息
                    if let index = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                        appState.chatMessages.remove(at: index)
                    }
                    
                    // 创建重新分类气泡消息
                    var reclassifyMessage = ChatMessage(
                        role: .agent,
                        content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
                    )
                    reclassifyMessage.showReclassifyBubble = true
                    reclassifyMessage.images = images  // 保存原始图片
                    appState.chatMessages.append(reclassifyMessage)
                    appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
                    return
                }

                // 移除加载消息
                if let idx = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                    appState.chatMessages.remove(at: idx)
                }

                // 生成待办预览消息
                for todoResult in batchResult.todos {
                    print("✅ 生成待办: \(todoResult.title)")
                    createTodoPreviewMessage(result: todoResult)
                }

                // 生成联系人预览消息
                for contactResult in batchResult.contacts {
                    print("✅ 生成联系人: \(contactResult.name)")
                    createContactPreviewMessage(result: contactResult)
                }

                // 生成报销预览消息
                for expenseResult in batchResult.expenses {
                    print("✅ 生成报销: \(expenseResult.title) - ¥\(expenseResult.amount)")
                    createExpensePreviewMessage(result: expenseResult)
                }

                HapticFeedback.success()
            }

        } catch {
            print("⚠️ 图片分析失败: \(error)")

            await MainActor.run {
                // 分析失败，显示重新分类气泡
                // 移除加载消息
                if let index = appState.chatMessages.firstIndex(where: { $0.id == agentMessageId }) {
                    appState.chatMessages.remove(at: index)
                }
                
                // 创建重新分类气泡消息
                var reclassifyMessage = ChatMessage(
                    role: .agent,
                    content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
                )
                reclassifyMessage.showReclassifyBubble = true
                reclassifyMessage.images = images  // 保存原始图片
                appState.chatMessages.append(reclassifyMessage)
                appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
            }
        }
    }
    
    // 按分类解析图片（用于手动选择后的重新分析）
    private func parseImagesByCategory(images: [UIImage], category: ScreenshotCategory, additionalNote: String = "") async throws -> BatchParseResult {
        // 如果有补充说明，在日志中输出
        if !additionalNote.isEmpty {
            print("📝 用户补充说明: \(additionalNote)")
        }
        
        // 根据分类调用对应的解析方法
        // 注意：这里暂时不传递补充说明给AI，因为当前的parseImageForTodo等方法不支持额外参数
        // 未来可以优化这些方法来接收补充说明，帮助AI更准确地理解图片
        switch category {
        case .todo:
            var todos: [TodoParseResult] = []
            for image in images {
                if let result = try? await QwenOmniService.parseImageForTodo(image: image, additionalContext: additionalNote) {
                    todos.append(result)
                }
            }
            return BatchParseResult(confidence: "high", todos: todos, contacts: [], expenses: [])
            
        case .contact:
            var contacts: [ContactParseResult] = []
            for image in images {
                if let result = try? await QwenOmniService.parseImageForContact(image: image, additionalContext: additionalNote) {
                    contacts.append(result)
                }
            }
            return BatchParseResult(confidence: "high", todos: [], contacts: contacts, expenses: [])
            
        case .expense:
            var expenses: [ExpenseParseResult] = []
            for image in images {
                if let result = try? await QwenOmniService.parseImageForExpense(image: image, additionalContext: additionalNote) {
                    expenses.append(result)
                }
            }
            return BatchParseResult(confidence: "high", todos: [], contacts: [], expenses: expenses)
            
        case .unknown:
            // 未知类型，使用通用分析
            return try await QwenOmniService.analyzeMultipleImages(images: images)
        }
    }
    
    // 处理"识别错了"按钮点击 - 显示重新分类气泡
    private func handleWrongClassification(for messageId: UUID, images: [UIImage]) {
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("⚠️ 找不到消息")
            return
        }
        
        print("⚠️ 用户点击「识别错了」，messageId: \(messageId)")
        
        // 移除预览卡片消息
        appState.chatMessages.remove(at: messageIndex)
        
        // 创建重新分类气泡消息
        var reclassifyMessage = ChatMessage(
            role: .agent,
            content: "这张图片我看不太明白呢，你是想创建待办事项、记录人脉信息，还是报销记录？"
        )
        reclassifyMessage.showReclassifyBubble = true
        reclassifyMessage.images = images  // 保存原始图片
        appState.chatMessages.append(reclassifyMessage)
        appState.saveMessageToStorage(reclassifyMessage, modelContext: modelContext)
        
        print("✅ 已显示重新分类气泡")
    }
    
    // 处理重新分类确认
    private func handleReclassifyConfirm(messageId: UUID, intent: String, additionalNote: String) {
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("⚠️ 找不到消息")
            return
        }
        
        let message = appState.chatMessages[messageIndex]
        let images = message.images
        
        print("✅ 用户确认重新分类: \(intent), 补充说明: \(additionalNote)")
        
        // 移除重新分类气泡
        appState.chatMessages.remove(at: messageIndex)
        
        // 根据意图重新分析
        let loadingMessage = ChatMessage(role: .agent, content: "正在重新分析图片...")
        appState.chatMessages.append(loadingMessage)
        let loadingMessageId = loadingMessage.id
        
        Task {
            do {
                // 判断意图类型
                let category: ScreenshotCategory
                if intent == "生成待办" {
                    category = .todo
                } else if intent == "生成人脉" {
                    category = .contact
                } else if intent == "生成报销" {
                    category = .expense
                } else {
                    // 不应该走到这里，因为已经强制选择三个之一
                    category = .todo
                }
                
                // 带补充说明的解析
                let batchResult = try await parseImagesByCategory(images: images, category: category, additionalNote: additionalNote)
                
                await MainActor.run {
                    // 移除加载消息
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == loadingMessageId }) {
                        appState.chatMessages.remove(at: idx)
                    }
                    
                    // 生成预览消息
                    for todoResult in batchResult.todos {
                        createTodoPreviewMessage(result: todoResult)
                    }
                    for contactResult in batchResult.contacts {
                        createContactPreviewMessage(result: contactResult)
                    }
                    for expenseResult in batchResult.expenses {
                        createExpensePreviewMessage(result: expenseResult)
                    }
                    
                    HapticFeedback.success()
                }
            } catch {
                print("⚠️ 重新分析失败: \(error)")
                await MainActor.run {
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == loadingMessageId }) {
                        var errorMessage = appState.chatMessages[idx]
                        errorMessage.content = "抱歉，重新分析失败了，请重试"
                        appState.chatMessages[idx] = errorMessage
                    }
                }
            }
        }
    }
    
    // 处理重新分类取消
    private func handleReclassifyCancel(messageId: UUID) {
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("⚠️ 找不到消息")
            return
        }
        
        print("❌ 用户取消重新分类")
        
        // 移除重新分类气泡
        appState.chatMessages.remove(at: messageIndex)
        
        // 显示取消提示
        let cancelMessage = ChatMessage(
            role: .agent,
            content: "好的，已取消这次图片分析操作"
        )
        appState.chatMessages.append(cancelMessage)
        appState.saveMessageToStorage(cancelMessage, modelContext: modelContext)
        
        HapticFeedback.light()
    }
    
    // 创建待办预览消息
    private func createTodoPreviewMessage(result: TodoParseResult) {
        let todoPreview = TodoPreviewData(
            title: result.title,
            description: result.description,
            startTime: result.startTime,
            endTime: result.endTime,
            reminderTime: result.startTime.addingTimeInterval(-15 * 60),
            imageData: result.imageData
        )
        
        // 从 imageData 重建 UIImage
        var originalImage: UIImage? = nil
        if let image = UIImage(data: result.imageData) {
            originalImage = image
        }
        
        var todoMessage = ChatMessage(role: .agent, content: "为你生成了待办事项，可以调整时间后点击完成~")
        todoMessage.todoPreview = todoPreview
        if let image = originalImage {
            todoMessage.images = [image]  // 保存原始图片供"识别错了"使用
        }
        appState.chatMessages.append(todoMessage)
        appState.saveMessageToStorage(todoMessage, modelContext: modelContext)
        print("✅ 待办预览消息已创建")
    }
    
    // 创建人脉预览消息
    private func createContactPreviewMessage(result: ContactParseResult) {
        // 检查是否存在同名联系人
        let nameToMatch = result.name
        let existingContact = try? modelContext.fetch(
            FetchDescriptor<Contact>(
                predicate: #Predicate { $0.name == nameToMatch }
            )
        ).first
        
        // 准备预览数据（无论是否重名都显示预览）
        let contactPreview = ContactPreviewData(
            name: result.name,
            phoneNumber: result.phoneNumber,
            company: result.company,
            identity: result.identity,
            hobbies: result.hobbies,
            relationship: result.relationship,
            avatarData: result.avatarData,
            imageData: result.imageData,
            isEditMode: existingContact != nil,  // 如果存在重名，设置为编辑模式
            existingContactId: existingContact?.id  // 如果存在重名，传入现有联系人ID
        )
        
        // 从 imageData 重建 UIImage
        var originalImage: UIImage? = nil
        if let image = UIImage(data: result.imageData) {
            originalImage = image
        }
        
        // 根据是否重名显示不同的提示文字
        let messageContent: String
        if existingContact != nil {
            messageContent = "检测到人脉库中已存在「\(result.name)」，可以调整后点击完成更新信息~"
            print("⚠️ 检测到重名联系人：\(result.name)，仍显示预览卡片供用户更新")
        } else {
            messageContent = "为你生成了人脉信息，可以调整后点击完成~"
        }
        
        var contactMessage = ChatMessage(
            role: .agent,
            content: messageContent
        )
        contactMessage.contactPreview = contactPreview
        if let image = originalImage {
            contactMessage.images = [image]  // 保存原始图片供"识别错了"使用
        }
        appState.chatMessages.append(contactMessage)
        appState.saveMessageToStorage(contactMessage, modelContext: modelContext)
        print("✅ 人脉预览消息已创建")
    }
    
    // 创建报销预览消息
    private func createExpensePreviewMessage(result: ExpenseParseResult) {
        let expensePreview = ExpensePreviewData(
            amount: result.amount,
            title: result.title,
            category: result.category,
            event: nil, // 事件字段为空，让用户在预览中填写
            occurredAt: result.occurredAt,
            notes: result.notes,
            imageData: result.imageData
        )
        
        var expenseMessage = ChatMessage(role: .agent, content: "为你生成了报销信息，可以调整后点击完成~")
        expenseMessage.expensePreview = expensePreview
        appState.chatMessages.append(expenseMessage)
        appState.saveMessageToStorage(expenseMessage, modelContext: modelContext)
        print("✅ 报销预览消息已创建")
    }
}

// ===== 图片操作按钮组件 =====
struct ImageActionButtons: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Query(sort: \Contact.name) private var allContacts: [Contact]

    let messageId: UUID
    let pendingAction: PendingActionType

    var body: some View {
        VStack(spacing: 8) {
            // 解析内容按钮
            Button(action: {
                HapticFeedback.medium()
                handleParseContent()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("解析内容")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }

            // 生成待办按钮
            Button(action: {
                HapticFeedback.medium()
                handleGenerateTodo()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("生成待办")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }

            // 生成人脉按钮（统一按钮，自动检测是新建还是更新）
            Button(action: {
                HapticFeedback.medium()
                handleGenerateContact()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("生成人脉")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }

            // 生成报销按钮
            Button(action: {
                HapticFeedback.medium()
                handleGenerateExpense()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("生成报销")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }
        }
    }
    
    // 处理解析内容操作
    private func handleParseContent() {
        print("🔍 开始解析图片内容")
        
        // 找到当前消息
        guard let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("⚠️ 找不到消息")
            return
        }
        
        // 移除pendingAction标记，将消息转换为普通AI消息
        var updatedMessage = appState.chatMessages[index]
        updatedMessage.pendingAction = nil
        appState.chatMessages[index] = updatedMessage
        
        print("✅ 已移除操作按钮，准备调用API")
        
        // 流式API调用
        Task {
            appState.isAgentTyping = true
            appState.startStreaming(messageId: messageId)
            
            await SmartModelRouter.sendMessageStream(
                messages: appState.chatMessages,
                mode: appState.currentMode,
                onComplete: { finalText in
                    print("✅ 收到onComplete回调，内容长度: \(finalText.count)")
                    await appState.playResponse(finalText, for: messageId)

                    // AI响应完成后，保存到本地存储
                    await MainActor.run {
                        if let completedMessage = appState.chatMessages.first(where: { $0.id == messageId }) {
                            appState.saveMessageToStorage(completedMessage, modelContext: modelContext)
                            print("✅ AI消息已保存到本地")
                        }
                    }
                },
                onError: { error in
                    print("❌ 收到onError回调: \(error)")
                    appState.handleStreamingError(error, for: messageId)
                    appState.isAgentTyping = false
                }
            )
        }
    }
    
    // 处理生成待办操作
    private func handleGenerateTodo() {
        print("📝 开始生成待办")
        
        // 找到用户发送的图片消息
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }),
              messageIndex > 0 else {
            print("⚠️ 找不到消息")
            return
        }
        
        // 获取前一条用户消息中的图片
        let userMessage = appState.chatMessages[messageIndex - 1]
        guard !userMessage.images.isEmpty else {
            print("⚠️ 没有找到图片")
            return
        }
        
        let image = userMessage.images[0]
        
        // 移除操作按钮，显示加载状态
        var updatedMessage = appState.chatMessages[messageIndex]
        updatedMessage.pendingAction = nil
        updatedMessage.content = "正在解析图片生成待办..."
        appState.chatMessages[messageIndex] = updatedMessage
        
        print("✅ 开始解析图片")
        print("   图片尺寸: \(image.size)")
        
        Task {
            do {
                // 调用QwenOmni解析图片
                let result = try await QwenOmniService.parseImageForTodo(image: image)
                
                print("✅ 图片解析成功")
                print("   标题: \(result.title)")
                print("   描述: \(result.description)")
                print("   开始时间: \(result.startTime)")
                print("   结束时间: \(result.endTime)")
                print("   图片数据大小: \(result.imageData.count) bytes")
                
                await MainActor.run {
                    // 创建待办预览数据（不直接保存到数据库）
                    let todoPreview = TodoPreviewData(
                        title: result.title,
                        description: result.description,
                        startTime: result.startTime,
                        endTime: result.endTime,
                        reminderTime: result.startTime.addingTimeInterval(-15 * 60),
                        imageData: result.imageData
                    )
                    
                    print("📝 待办预览信息:")
                    print("   标题: \(todoPreview.title)")
                    print("   描述: \(todoPreview.description)")
                    print("   图片数据大小: \(todoPreview.imageData.count) bytes")
                    
                    // 更新AI消息，显示待办预览
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "为你生成了待办事项，可以调整时间后点击完成~"
                        msg.todoPreview = todoPreview
                        appState.chatMessages[idx] = msg
                        
                        // 保存AI消息
                        appState.saveMessageToStorage(msg, modelContext: modelContext)
                        
                        HapticFeedback.success()
                    }
                }
            } catch {
                print("❌ 解析图片失败: \(error)")
                await MainActor.run {
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "抱歉，解析图片时出错了: \(error.localizedDescription)"
                        appState.chatMessages[idx] = msg
                    }
                }
            }
        }
    }

    // 处理生成报销操作
    private func handleGenerateExpense() {
        print("💰 开始生成报销")

        // 找到用户发送的图片消息
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }),
              messageIndex > 0 else {
            print("⚠️ 找不到消息")
            return
        }

        // 获取前一条用户消息中的图片
        let userMessage = appState.chatMessages[messageIndex - 1]
        guard !userMessage.images.isEmpty else {
            print("⚠️ 没有找到图片")
            return
        }

        let image = userMessage.images[0]

        // 移除操作按钮，显示加载状态
        var updatedMessage = appState.chatMessages[messageIndex]
        updatedMessage.pendingAction = nil
        updatedMessage.content = "正在解析图片生成报销..."
        appState.chatMessages[messageIndex] = updatedMessage

        print("✅ 开始解析图片")
        print("   图片尺寸: \(image.size)")

        Task {
            do {
                // 调用QwenOmni解析图片
                let result = try await QwenOmniService.parseImageForExpense(image: image)

                print("✅ 图片解析成功")
                print("   标题: \(result.title)")
                print("   金额: \(result.amount)")
                print("   类别: \(result.category ?? "未指定")")
                print("   发生时间: \(result.occurredAt)")
                print("   图片数据大小: \(result.imageData.count) bytes")

                await MainActor.run {
                    // 移除加载消息
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        appState.chatMessages.remove(at: idx)
                    }
                    // 询问事件
                    createExpensePreviewMessage(result: result)
                }
            } catch {
                print("❌ 解析图片失败: \(error)")
                await MainActor.run {
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "抱歉，解析图片时出错了: \(error.localizedDescription)"
                        appState.chatMessages[idx] = msg
                    }
                }
            }
        }
    }

    // 处理生成人脉操作（统一逻辑：自动检测是新建还是更新）
    private func handleGenerateContact() {
        print("👤 开始生成人脉")

        // 找到用户发送的图片消息
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }),
              messageIndex > 0 else {
            print("⚠️ 找不到消息")
            return
        }

        // 获取前一条用户消息中的图片
        let userMessage = appState.chatMessages[messageIndex - 1]
        guard !userMessage.images.isEmpty else {
            print("⚠️ 没有找到图片")
            return
        }

        let image = userMessage.images[0]

        // 移除操作按钮，显示加载状态
        var updatedMessage = appState.chatMessages[messageIndex]
        updatedMessage.pendingAction = nil
        updatedMessage.content = "正在解析图片生成人脉..."
        appState.chatMessages[messageIndex] = updatedMessage

        print("✅ 开始解析图片")
        print("   图片尺寸: \(image.size)")

        Task {
            do {
                // 调用QwenOmni解析图片
                let result = try await QwenOmniService.parseImageForContact(image: image)

                print("✅ 图片解析成功")
                print("   姓名: \(result.name)")
                if let phone = result.phoneNumber { print("   手机号: \(phone)") }
                if let company = result.company { print("   公司: \(company)") }
                if let hobbies = result.hobbies { print("   兴趣: \(hobbies)") }
                if let relationship = result.relationship { print("   关系: \(relationship)") }
                print("   图片数据大小: \(result.imageData.count) bytes")

                await MainActor.run {
                    // 检查是否存在同名联系人
                    let existingContact = allContacts.first(where: { $0.name == result.name })

                    // 准备预览数据（无论是否重名都显示预览）
                    let contactPreview = ContactPreviewData(
                        name: result.name,
                        phoneNumber: result.phoneNumber,
                        company: result.company,
                        identity: result.identity,
                        hobbies: result.hobbies,
                        relationship: result.relationship,
                        avatarData: result.avatarData,
                        imageData: result.imageData,
                        isEditMode: false,
                        existingContactId: existingContact?.id  // 如果存在重名，传入现有联系人ID
                    )
                    
                    if existingContact != nil {
                        print("⚠️ 检测到重名联系人：\(result.name)，显示预览卡片供用户更新")
                    } else {
                        print("✨ 未发现同名联系人，将创建新人脉")
                    }

                    print("👤 人脉预览信息:")
                    print("   姓名: \(contactPreview.name)")
                    print("   模式: \(existingContact != nil ? "更新现有人脉" : "创建新人脉")")
                    print("   图片数据大小: \(contactPreview.imageData.count) bytes")

                    // 更新AI消息，显示人脉预览
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        // 根据是否重名显示不同的提示文字
                        msg.content = existingContact != nil 
                            ? "检测到人脉库中已存在「\(result.name)」，可以调整后点击完成更新信息~"
                            : "为你生成了人脉信息，可以调整后点击完成~"
                        msg.contactPreview = contactPreview
                        appState.chatMessages[idx] = msg

                        // 保存AI消息
                        appState.saveMessageToStorage(msg, modelContext: modelContext)

                        HapticFeedback.success()
                    }
                }
            } catch {
                print("❌ 解析图片失败: \(error)")
                await MainActor.run {
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "抱歉，解析图片时出错了: \(error.localizedDescription)"
                        appState.chatMessages[idx] = msg
                    }
                }
            }
        }
    }
    
    // 创建报销预览消息
    private func createExpensePreviewMessage(result: ExpenseParseResult) {
        let expensePreview = ExpensePreviewData(
            amount: result.amount,
            title: result.title,
            category: result.category,
            event: nil, // 事件字段为空，让用户在预览中填写
            occurredAt: result.occurredAt,
            notes: result.notes,
            imageData: result.imageData
        )
        
        var expenseMessage = ChatMessage(role: .agent, content: "为你生成了报销信息，可以调整后点击完成~")
        expenseMessage.expensePreview = expensePreview
        appState.chatMessages.append(expenseMessage)
        appState.saveMessageToStorage(expenseMessage, modelContext: modelContext)
        print("✅ 报销预览消息已创建")
    }
}

// ===== 文字操作按钮组件 =====
struct TextActionButtons: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Query(sort: \Contact.name) private var allContacts: [Contact]

    let messageId: UUID
    let pendingAction: PendingActionType

    var body: some View {
        VStack(spacing: 8) {
            // 聊天按钮
            Button(action: {
                HapticFeedback.medium()
                handleChat()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("聊天")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }

            // 生成待办按钮
            Button(action: {
                HapticFeedback.medium()
                handleGenerateTodo()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("生成待办")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }

            // 生成人脉按钮
            Button(action: {
                HapticFeedback.medium()
                handleGenerateContact()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("生成人脉")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }

            // 生成报销按钮
            Button(action: {
                HapticFeedback.medium()
                handleGenerateExpense()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, alignment: .center)
                    Text("生成报销")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }
        }
    }
    
    // 处理聊天操作
    private func handleChat() {
        print("💬 开始聊天")
        
        // 找到当前消息
        guard let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) else {
            print("⚠️ 找不到消息")
            return
        }
        
        // 移除pendingAction标记，将消息转换为普通AI消息
        var updatedMessage = appState.chatMessages[index]
        updatedMessage.pendingAction = nil
        appState.chatMessages[index] = updatedMessage
        
        print("✅ 已移除操作按钮，准备调用API")
        
        // 流式API调用
        Task {
            appState.isAgentTyping = true
            appState.startStreaming(messageId: messageId)
            
            await SmartModelRouter.sendMessageStream(
                messages: appState.chatMessages,
                mode: appState.currentMode,
                onComplete: { finalText in
                    print("✅ 收到onComplete回调，内容长度: \(finalText.count)")
                    await appState.playResponse(finalText, for: messageId)

                    // AI响应完成后，保存到本地存储
                    await MainActor.run {
                        if let completedMessage = appState.chatMessages.first(where: { $0.id == messageId }) {
                            appState.saveMessageToStorage(completedMessage, modelContext: modelContext)
                            print("✅ AI消息已保存到本地")
                        }
                    }
                },
                onError: { error in
                    print("❌ 收到onError回调: \(error)")
                    appState.handleStreamingError(error, for: messageId)
                    appState.isAgentTyping = false
                }
            )
        }
    }
    
    // 处理生成待办操作（从文字）
    private func handleGenerateTodo() {
        print("📝 开始从文字生成待办")
        
        // 找到用户发送的文字消息
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }),
              messageIndex > 0 else {
            print("⚠️ 找不到消息")
            return
        }

        // 获取前一条用户消息中的文字
        let userMessage = appState.chatMessages[messageIndex - 1]
        let text = userMessage.content

        // 移除操作按钮，显示加载状态
        var updatedMessage = appState.chatMessages[messageIndex]
        updatedMessage.pendingAction = nil
        updatedMessage.content = "正在解析文字生成待办..."
        appState.chatMessages[messageIndex] = updatedMessage

        print("✅ 开始解析文字")
        print("   文字内容: \(text)")

        Task {
            do {
                // 调用QwenOmni解析文字
                let result = try await QwenOmniService.parseTextForTodo(text: text)

                print("✅ 文字解析成功")
                print("   标题: \(result.title)")
                print("   描述: \(result.description)")

                await MainActor.run {
                    // 创建待办预览数据
                    let todoPreview = TodoPreviewData(
                        title: result.title,
                        description: result.description,
                        startTime: result.startTime,
                        endTime: result.endTime,
                        reminderTime: result.startTime.addingTimeInterval(-15 * 60),
                        imageData: result.imageData
                    )

                    // 更新AI消息，显示待办预览
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "为你生成了待办事项，可以调整时间后点击完成~"
                        msg.todoPreview = todoPreview
                        appState.chatMessages[idx] = msg

                        // 保存AI消息
                        appState.saveMessageToStorage(msg, modelContext: modelContext)

                        HapticFeedback.success()
                    }
                }
            } catch {
                print("❌ 解析文字失败: \(error)")
                await MainActor.run {
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "抱歉，解析文字时出错了: \(error.localizedDescription)"
                        appState.chatMessages[idx] = msg
                    }
                }
            }
        }
    }

    // 处理生成人脉操作（从文字）
    private func handleGenerateContact() {
        print("👤 开始从文字生成人脉")

        // 找到用户发送的文字消息
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }),
              messageIndex > 0 else {
            print("⚠️ 找不到消息")
            return
        }

        // 获取前一条用户消息中的文字
        let userMessage = appState.chatMessages[messageIndex - 1]
        let text = userMessage.content

        // 移除操作按钮，显示加载状态
        var updatedMessage = appState.chatMessages[messageIndex]
        updatedMessage.pendingAction = nil
        updatedMessage.content = "正在解析文字生成人脉..."
        appState.chatMessages[messageIndex] = updatedMessage

        print("✅ 开始解析文字")

        Task {
            do {
                // 调用QwenOmni解析文字
                let result = try await QwenOmniService.parseTextForContact(text: text)

                print("✅ 文字解析成功")
                print("   姓名: \(result.name)")

                await MainActor.run {
                    // 检测是否是更新现有联系人
                    let existingContact = allContacts.first(where: { contact in
                        contact.name == result.name
                    })

                    // 准备预览数据（无论是否重名都显示预览）
                    let contactPreview = ContactPreviewData(
                        name: result.name,
                        phoneNumber: result.phoneNumber,
                        company: result.company,
                        identity: result.identity,
                        hobbies: result.hobbies,
                        relationship: result.relationship,
                        avatarData: result.avatarData,
                        imageData: result.imageData,
                        isEditMode: false,
                        existingContactId: existingContact?.id  // 如果存在重名，传入现有联系人ID
                    )
                    
                    // 根据是否重名显示不同的提示文字
                    let messageContent: String
                    if existingContact != nil {
                        messageContent = "检测到人脉库中已存在「\(result.name)」，可以调整后点击完成更新信息~"
                        print("⚠️ 检测到重名联系人：\(result.name)，仍显示预览卡片供用户更新")
                    } else {
                        messageContent = "为你生成了人脉信息，可以调整后点击完成~"
                    }

                    // 更新AI消息，显示人脉预览
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = messageContent
                        msg.contactPreview = contactPreview
                        appState.chatMessages[idx] = msg

                        // 保存AI消息
                        appState.saveMessageToStorage(msg, modelContext: modelContext)

                        HapticFeedback.success()
                    }
                }
            } catch {
                print("❌ 解析文字失败: \(error)")
                await MainActor.run {
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "抱歉，解析文字时出错了: \(error.localizedDescription)"
                        appState.chatMessages[idx] = msg
                    }
                }
            }
        }
    }

    // 处理生成报销操作（从文字）
    private func handleGenerateExpense() {
        print("💰 开始从文字生成报销")

        // 找到用户发送的文字消息
        guard let messageIndex = appState.chatMessages.firstIndex(where: { $0.id == messageId }),
              messageIndex > 0 else {
            print("⚠️ 找不到消息")
            return
        }

        // 获取前一条用户消息中的文字
        let userMessage = appState.chatMessages[messageIndex - 1]
        let text = userMessage.content

        // 移除操作按钮，显示加载状态
        var updatedMessage = appState.chatMessages[messageIndex]
        updatedMessage.pendingAction = nil
        updatedMessage.content = "正在解析文字生成报销..."
        appState.chatMessages[messageIndex] = updatedMessage

        print("✅ 开始解析文字")

        Task {
            do {
                // 调用QwenOmni解析文字
                let result = try await QwenOmniService.parseTextForExpense(text: text)

                print("✅ 文字解析成功")
                print("   标题: \(result.title)")
                print("   金额: \(result.amount)")

                await MainActor.run {
                    // 移除加载消息
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        appState.chatMessages.remove(at: idx)
                    }
                    // 询问事件
                    createExpensePreviewMessage(result: result)
                }
            } catch {
                print("❌ 解析文字失败: \(error)")
                await MainActor.run {
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        msg.content = "抱歉，解析文字时出错了: \(error.localizedDescription)"
                        appState.chatMessages[idx] = msg
                    }
                }
            }
        }
    }
    
    // 创建报销预览消息
    private func createExpensePreviewMessage(result: ExpenseParseResult) {
        let expensePreview = ExpensePreviewData(
            amount: result.amount,
            title: result.title,
            category: result.category,
            event: nil, // 事件字段为空，让用户在预览中填写
            occurredAt: result.occurredAt,
            notes: result.notes,
            imageData: result.imageData
        )
        
        var expenseMessage = ChatMessage(role: .agent, content: "为你生成了报销信息，可以调整后点击完成~")
        expenseMessage.expensePreview = expensePreview
        appState.chatMessages.append(expenseMessage)
        appState.saveMessageToStorage(expenseMessage, modelContext: modelContext)
        print("✅ 报销预览消息已创建")
    }
}

// ===== 待办预览气泡组件 =====
struct TodoPreviewBubble: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Environment(\.hideInputBar) private var hideInputBar
    let messageId: UUID
    @State private var todoPreview: TodoPreviewData
    @State private var showPreviewImage = false
    @FocusState private var isTitleFieldFocused: Bool
    @FocusState private var isDescriptionFieldFocused: Bool
    let originalImages: [UIImage]  // 原始图片，用于"识别错了"
    
    init(messageId: UUID, todoPreview: TodoPreviewData, originalImages: [UIImage] = []) {
        self.messageId = messageId
        self._todoPreview = State(initialValue: todoPreview)
        self.originalImages = originalImages
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题和描述
            VStack(alignment: .leading, spacing: 8) {
                TextField("待办标题", text: $todoPreview.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.9))
                    .focused($isTitleFieldFocused)
                
                TextField("备注（可选）", text: $todoPreview.description)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.6))
                    .focused($isDescriptionFieldFocused)
            }
            .onChange(of: isTitleFieldFocused) { _, isFocused in
                withAnimation(.easeInOut(duration: 0.2)) {
                    hideInputBar.wrappedValue = isFocused || isDescriptionFieldFocused
                }
            }
            .onChange(of: isDescriptionFieldFocused) { _, isFocused in
                withAnimation(.easeInOut(duration: 0.2)) {
                    hideInputBar.wrappedValue = isFocused || isTitleFieldFocused
                }
            }
            .onDisappear {
                hideInputBar.wrappedValue = false
            }
            
            Divider()
                .background(Color.black.opacity(0.1))
            
            // 时间调节区域
            VStack(spacing: 10) {
                // 开始时间
                TimePickerRow(
                    icon: "clock.fill",
                    label: "开始",
                    time: $todoPreview.startTime,
                    onChange: { newValue in
                        if todoPreview.endTime <= newValue {
                            todoPreview.endTime = newValue.addingTimeInterval(3600)
                        }
                        todoPreview.reminderTime = newValue.addingTimeInterval(-15 * 60)
                    }
                )
                
                // 结束时间
                TimePickerRow(
                    icon: "flag.fill",
                    label: "结束",
                    time: $todoPreview.endTime,
                    timeRange: todoPreview.startTime...
                )
                
                // 提醒时间
                TimePickerRow(
                    icon: "bell.fill",
                    label: "提醒",
                    time: $todoPreview.reminderTime
                )
            }
            
            Divider()
                .background(Color.black.opacity(0.1))
            
            // 完成和取消按钮
            HStack(spacing: 12) {
                // 取消按钮
                Button(action: {
                    HapticFeedback.light()
                    handleCancel()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("取消")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                // 完成按钮
                Button(action: {
                    HapticFeedback.medium()
                    handleComplete()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("完成")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            // "识别错了"按钮
            if !originalImages.isEmpty {
                Button(action: {
                    HapticFeedback.light()
                    handleWrongClassification()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                        Text("识别错了？")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.03))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }
    
    // 处理取消操作
    private func handleCancel() {
        print("❌ 用户取消待办预览")
        
        // 移除预览消息
        if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
            appState.chatMessages.remove(at: idx)
        }
        
        HapticFeedback.light()
    }
    
    // 处理完成操作
    private func handleComplete() {
        print("✅ 用户确认待办，准备保存")

        // 创建TodoItem
        let newTodo = TodoItem(
            title: todoPreview.title,
            taskDescription: todoPreview.description,
            startTime: todoPreview.startTime,
            endTime: todoPreview.endTime,
            reminderTime: todoPreview.reminderTime,
            imageData: [todoPreview.imageData],
            textAttachments: nil,
            syncToCalendar: true
        )

        // 保存到数据库
        modelContext.insert(newTodo)

        do {
            try modelContext.save()
            print("✅ 待办已保存到数据库，ID: \(newTodo.id)")

            // 异步同步到日历和创建通知
            Task {
                // 创建日历事件
                let eventId = await CalendarManager.shared.createCalendarEvent(
                    title: todoPreview.title,
                    description: todoPreview.description,
                    startDate: todoPreview.startTime,
                    endDate: todoPreview.endTime,
                    alarmDate: todoPreview.reminderTime
                )
                newTodo.calendarEventId = eventId

                // 创建本地通知
                let notificationId = newTodo.id.uuidString
                newTodo.notificationId = notificationId
                await CalendarManager.shared.scheduleNotification(
                    id: notificationId,
                    title: todoPreview.title,
                    body: todoPreview.description.isEmpty ? nil : todoPreview.description,
                    date: todoPreview.reminderTime
                )

                // 保存更新后的eventId和notificationId
                try? modelContext.save()
                print("✅ 日历事件和通知已创建")
            }

            // 更新消息，移除预览显示确认信息
            if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[idx]
                msg.content = "已经为你创建了待办事项「\(todoPreview.title)」~"
                msg.todoPreview = nil  // 移除预览，显示确认消息
                appState.chatMessages[idx] = msg

                // 保存AI消息
                appState.saveMessageToStorage(msg, modelContext: modelContext)
            }

            HapticFeedback.success()
        } catch {
            print("❌ 保存待办失败: \(error)")
            
            // 显示错误信息
            if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[idx]
                msg.content = "抱歉，保存待办时出错了: \(error.localizedDescription)"
                msg.todoPreview = nil
                appState.chatMessages[idx] = msg
            }
        }
    }
    
    // 处理"识别错了"操作
    private func handleWrongClassification() {
        print("⚠️ 用户点击「识别错了」")
        
        // 发送通知
        NotificationCenter.default.post(
            name: NSNotification.Name("HandleWrongClassification"),
            object: nil,
            userInfo: ["messageId": messageId, "images": originalImages]
        )
    }
}

// ===== 时间选择器行组件（紧凑版） =====
struct TimePickerRow: View {
    let icon: String
    let label: String
    @Binding var time: Date
    var timeRange: PartialRangeFrom<Date>?
    var onChange: ((Date) -> Void)?
    
    var body: some View {
        HStack(spacing: 10) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                .frame(width: 18)
            
            // 标签
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.65))
                .frame(width: 40, alignment: .leading)
            
            Spacer()
            
            // 时间选择器
            if let range = timeRange {
                DatePicker("", selection: $time, in: range)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: time) { _, newValue in
                        onChange?(newValue)
                    }
            } else {
                DatePicker("", selection: $time)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: time) { _, newValue in
                        onChange?(newValue)
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.03))
        )
    }
}

// ===== 人脉预览气泡组件 =====
struct ContactPreviewBubble: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Query(sort: \Contact.name) private var allContacts: [Contact]

    let messageId: UUID
    @State private var contactPreview: ContactPreviewData
    @State private var shouldCreateTodo: Bool = false
    @State private var todoTitle: String = ""
    let originalImages: [UIImage]  // 原始图片，用于"识别错了"

    init(messageId: UUID, contactPreview: ContactPreviewData, originalImages: [UIImage] = []) {
        self.messageId = messageId
        self._contactPreview = State(initialValue: contactPreview)
        self.originalImages = originalImages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头像和姓名
            HStack(spacing: 12) {
                // 头像
                ZStack {
                    if let avatarData = contactPreview.avatarData,
                       let uiImage = UIImage(data: avatarData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3),
                                        Color(red: 0.78, green: 0.98, blue: 0.2).opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(String(contactPreview.name.prefix(1)))
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color.black.opacity(0.6))
                            )
                    }
                }

                // 姓名
                VStack(alignment: .leading, spacing: 4) {
                    TextField("姓名", text: $contactPreview.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.9))

                    if contactPreview.isEditMode {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .medium))
                            Text("将更新现有人脉")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(Color.orange.opacity(0.8))
                    }
                }
            }

            Divider()
                .background(Color.black.opacity(0.1))

            // 联系信息编辑区域
            VStack(spacing: 10) {
                // 手机号
                ContactInfoEditRow(
                    icon: "phone.fill",
                    label: "手机号",
                    text: Binding(
                        get: { contactPreview.phoneNumber ?? "" },
                        set: { contactPreview.phoneNumber = $0.isEmpty ? nil : $0 }
                    ),
                    placeholder: "输入手机号"
                )

                // 公司
                ContactInfoEditRow(
                    icon: "building.2.fill",
                    label: "公司",
                    text: Binding(
                        get: { contactPreview.company ?? "" },
                        set: { contactPreview.company = $0.isEmpty ? nil : $0 }
                    ),
                    placeholder: "输入公司名称"
                )

                // 身份（职位）
                ContactInfoEditRow(
                    icon: "briefcase.fill",
                    label: "身份",
                    text: Binding(
                        get: { contactPreview.identity ?? "" },
                        set: { contactPreview.identity = $0.isEmpty ? nil : $0 }
                    ),
                    placeholder: "输入职位"
                )

                // 兴趣爱好
                ContactInfoEditRow(
                    icon: "heart.fill",
                    label: "兴趣",
                    text: Binding(
                        get: { contactPreview.hobbies ?? "" },
                        set: { contactPreview.hobbies = $0.isEmpty ? nil : $0 }
                    ),
                    placeholder: "输入兴趣爱好"
                )

                // 与我关系
                ContactInfoEditRow(
                    icon: "person.2.fill",
                    label: "关系",
                    text: Binding(
                        get: { contactPreview.relationship ?? "" },
                        set: { contactPreview.relationship = $0.isEmpty ? nil : $0 }
                    ),
                    placeholder: "输入关系"
                )
            }

            Divider()
                .background(Color.black.opacity(0.1))

            // 同时添加待办选项
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $shouldCreateTodo) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 14, weight: .semibold))
                        Text("同时添加待办")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(Color.black.opacity(0.75))
                }
                .tint(Color(red: 0.85, green: 1.0, blue: 0.25))

                if shouldCreateTodo {
                    TextField("待办标题（如：联系\(contactPreview.name)）", text: $todoTitle)
                        .font(.system(size: 14, weight: .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.03))
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider()
                .background(Color.black.opacity(0.1))

            // 完成和取消按钮
            HStack(spacing: 12) {
                // 取消按钮
                Button(action: {
                    HapticFeedback.light()
                    handleCancel()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("取消")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                // 完成按钮
                Button(action: {
                    HapticFeedback.medium()
                    handleComplete()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(contactPreview.isEditMode ? "保存修改" : "完成")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            // "识别错了"按钮
            if !originalImages.isEmpty {
                Button(action: {
                    HapticFeedback.light()
                    handleWrongClassification()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                        Text("识别错了？")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.03))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }

    // 处理取消操作
    private func handleCancel() {
        print("❌ 用户取消人脉预览")
        
        // 移除预览消息
        if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
            appState.chatMessages.remove(at: idx)
        }
        
        HapticFeedback.light()
    }

    // 处理完成操作
    private func handleComplete() {
        print("✅ 用户确认人脉，准备保存")

        // 如果有 existingContactId，说明是更新现有联系人
        if let existingContactId = contactPreview.existingContactId {
            // 更新模式：更新现有联系人
            if let existingContact = allContacts.first(where: { $0.id == existingContactId }) {
                existingContact.name = contactPreview.name
                existingContact.phoneNumber = contactPreview.phoneNumber
                existingContact.company = contactPreview.company
                existingContact.identity = contactPreview.identity
                existingContact.hobbies = contactPreview.hobbies
                existingContact.relationship = contactPreview.relationship
                existingContact.avatarData = contactPreview.avatarData

                // 添加图片附件
                if var imageData = existingContact.imageData {
                    imageData.append(contactPreview.imageData)
                    existingContact.imageData = imageData
                } else {
                    existingContact.imageData = [contactPreview.imageData]
                }

                existingContact.lastModified = Date()

                do {
                    try modelContext.save()
                    print("✅ 人脉已更新，ID: \(existingContact.id)")

                    // 如果需要创建待办
                    if shouldCreateTodo && !todoTitle.isEmpty {
                        createTodoForContact(contactId: existingContact.id)
                    }

                    // 更新消息
                    if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                        var msg = appState.chatMessages[idx]
                        let todoMessage = shouldCreateTodo && !todoTitle.isEmpty ? "，并已添加待办" : ""
                        msg.content = "已经为你更新了人脉「\(contactPreview.name)」\(todoMessage)~"
                        msg.contactPreview = nil
                        appState.chatMessages[idx] = msg
                        appState.saveMessageToStorage(msg, modelContext: modelContext)
                    }

                    HapticFeedback.success()
                } catch {
                    print("❌ 更新人脉失败: \(error)")
                    showError(error)
                }
            } else {
                print("⚠️ 找不到要编辑的联系人")
            }
        } else {
            // 新建模式：创建新联系人
            let newContact = Contact(
                name: contactPreview.name,
                phoneNumber: contactPreview.phoneNumber,
                company: contactPreview.company,
                identity: contactPreview.identity,
                hobbies: contactPreview.hobbies,
                relationship: contactPreview.relationship,
                avatarData: contactPreview.avatarData,
                imageData: [contactPreview.imageData],
                textAttachments: nil
            )

            modelContext.insert(newContact)

            do {
                try modelContext.save()
                print("✅ 人脉已保存到数据库，ID: \(newContact.id)")

                // 如果需要创建待办
                if shouldCreateTodo && !todoTitle.isEmpty {
                    createTodoForContact(contactId: newContact.id)
                }

                // 更新消息
                if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                    var msg = appState.chatMessages[idx]
                    let todoMessage = shouldCreateTodo && !todoTitle.isEmpty ? "，并已添加待办" : ""
                    msg.content = "已经为你创建了人脉「\(contactPreview.name)」\(todoMessage)~"
                    msg.contactPreview = nil
                    appState.chatMessages[idx] = msg
                    appState.saveMessageToStorage(msg, modelContext: modelContext)
                }

                HapticFeedback.success()
            } catch {
                print("❌ 保存人脉失败: \(error)")
                showError(error)
            }
        }
    }

    // 创建关联待办
    private func createTodoForContact(contactId: UUID) {
        let now = Date()
        let calendar = Calendar.current
        let startTime = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let endTime = calendar.date(byAdding: .hour, value: 1, to: startTime) ?? startTime

        let todo = TodoItem(
            title: todoTitle.isEmpty ? "联系\(contactPreview.name)" : todoTitle,
            taskDescription: "与\(contactPreview.name)相关的待办事项",
            startTime: startTime,
            endTime: endTime,
            reminderTime: startTime.addingTimeInterval(-15 * 60),
            imageData: nil,
            textAttachments: nil,
            syncToCalendar: true
        )

        modelContext.insert(todo)

        do {
            try modelContext.save()
            print("✅ 已创建关联待办: \(todo.title)")

            // 创建日历事件和通知
            Task {
                let eventId = await CalendarManager.shared.createCalendarEvent(
                    title: todo.title,
                    description: todo.taskDescription,
                    startDate: todo.startTime,
                    endDate: todo.endTime,
                    alarmDate: todo.reminderTime
                )
                todo.calendarEventId = eventId

                let notificationId = todo.id.uuidString
                todo.notificationId = notificationId
                await CalendarManager.shared.scheduleNotification(
                    id: notificationId,
                    title: todo.title,
                    body: todo.taskDescription.isEmpty ? nil : todo.taskDescription,
                    date: todo.reminderTime
                )

                try? modelContext.save()
            }
        } catch {
            print("❌ 创建待办失败: \(error)")
        }
    }

    private func showError(_ error: Error) {
        if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
            var msg = appState.chatMessages[idx]
            msg.content = "抱歉，保存人脉时出错了: \(error.localizedDescription)"
            msg.contactPreview = nil
            appState.chatMessages[idx] = msg
        }
    }
    
    // 处理"识别错了"操作
    private func handleWrongClassification() {
        print("⚠️ 用户点击「识别错了」")
        
        // 发送通知
        NotificationCenter.default.post(
            name: NSNotification.Name("HandleWrongClassification"),
            object: nil,
            userInfo: ["messageId": messageId, "images": originalImages]
        )
    }
}

// ===== 报销预览气泡组件 =====
struct ExpensePreviewBubble: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Environment(\.hideInputBar) private var hideInputBar
    let messageId: UUID
    @State private var expensePreview: ExpensePreviewData
    @State private var shouldCreateTodo: Bool = false
    @State private var todoTitle: String = ""
    @State private var todoStartTime: Date
    @State private var todoEndTime: Date
    @State private var todoReminderTime: Date
    @FocusState private var isEventFieldFocused: Bool
    @FocusState private var isTitleFieldFocused: Bool
    let originalImages: [UIImage]  // 原始图片，用于"识别错了"

    init(messageId: UUID, expensePreview: ExpensePreviewData, originalImages: [UIImage] = []) {
        self.messageId = messageId
        self._expensePreview = State(initialValue: expensePreview)
        self.originalImages = originalImages
        
        // 初始化待办时间（1小时后开始，2小时后结束）
        let now = Date()
        let calendar = Calendar.current
        let startTime = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let endTime = calendar.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
        let reminderTime = startTime.addingTimeInterval(-15 * 60)
        
        self._todoStartTime = State(initialValue: startTime)
        self._todoEndTime = State(initialValue: endTime)
        self._todoReminderTime = State(initialValue: reminderTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题和事件（同等重要）
            VStack(alignment: .leading, spacing: 8) {
                TextField("报销标题", text: $expensePreview.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.9))
                    .focused($isTitleFieldFocused)
                
                TextField("事件（如：项目会议、客户拜访等）", text: Binding(
                    get: { expensePreview.event ?? "" },
                    set: { expensePreview.event = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.8))
                .focused($isEventFieldFocused)
            }
            .onAppear {
                // 当气泡出现时，自动聚焦事件字段，弹出键盘
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isEventFieldFocused = true
                }
            }
            .onChange(of: isEventFieldFocused) { _, isFocused in
                // 当事件字段获得或失去焦点时，控制底部输入栏的显示
                withAnimation(.easeInOut(duration: 0.2)) {
                    hideInputBar.wrappedValue = isFocused || isTitleFieldFocused
                }
            }
            .onChange(of: isTitleFieldFocused) { _, isFocused in
                // 当标题字段获得或失去焦点时，控制底部输入栏的显示
                withAnimation(.easeInOut(duration: 0.2)) {
                    hideInputBar.wrappedValue = isFocused || isEventFieldFocused
                }
            }
            .onDisappear {
                // 当气泡消失时，确保恢复输入栏显示
                hideInputBar.wrappedValue = false
            }

            Divider()
                .background(Color.black.opacity(0.1))

            // 信息编辑区域
            VStack(spacing: 10) {
                // 金额
                ExpenseInfoEditRow(
                    icon: "yensign.circle.fill",
                    label: "金额",
                    text: Binding(
                        get: { String(format: "%.2f", expensePreview.amount) },
                        set: { 
                            if let value = Double($0) {
                                expensePreview.amount = value
                            }
                        }
                    ),
                    placeholder: "输入金额"
                )

                // 类别
                ExpenseInfoEditRow(
                    icon: "tag.fill",
                    label: "类别",
                    text: Binding(
                        get: { expensePreview.category ?? "" },
                        set: { expensePreview.category = $0.isEmpty ? nil : $0 }
                    ),
                    placeholder: "输入类别"
                )

                // 发生时间
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                        .frame(width: 18)

                    Text("时间")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.65))
                        .frame(width: 50, alignment: .leading)

                    Spacer()

                    DatePicker("", selection: $expensePreview.occurredAt)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.03))
                )
            }

            Divider()
                .background(Color.black.opacity(0.1))

            // 同时添加待办选项
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $shouldCreateTodo) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 14, weight: .semibold))
                        Text("同时添加待办")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(Color.black.opacity(0.75))
                }
                .tint(Color(red: 0.85, green: 1.0, blue: 0.25))

                if shouldCreateTodo {
                    VStack(spacing: 10) {
                        // 待办标题
                        TextField("待办标题（如：提交报销）", text: $todoTitle)
                            .font(.system(size: 14, weight: .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.03))
                            )

                        // 开始时间
                        TimePickerRow(
                            icon: "clock.fill",
                            label: "开始",
                            time: $todoStartTime,
                            onChange: { newValue in
                                if todoEndTime <= newValue {
                                    todoEndTime = newValue.addingTimeInterval(3600)
                                }
                                todoReminderTime = newValue.addingTimeInterval(-15 * 60)
                            }
                        )

                        // 结束时间
                        TimePickerRow(
                            icon: "flag.fill",
                            label: "结束",
                            time: $todoEndTime,
                            timeRange: todoStartTime...
                        )

                        // 提醒时间
                        TimePickerRow(
                            icon: "bell.fill",
                            label: "提醒",
                            time: $todoReminderTime
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider()
                .background(Color.black.opacity(0.1))

            // 完成和取消按钮
            HStack(spacing: 12) {
                // 取消按钮
                Button(action: {
                    HapticFeedback.light()
                    handleCancel()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("取消")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                // 完成按钮
                Button(action: {
                    HapticFeedback.medium()
                    handleComplete()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("完成")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            // "识别错了"按钮
            if !originalImages.isEmpty {
                Button(action: {
                    HapticFeedback.light()
                    handleWrongClassification()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                        Text("识别错了？")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.03))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }

    // 处理取消操作
    private func handleCancel() {
        print("❌ 用户取消报销预览")
        
        // 移除预览消息
        if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
            appState.chatMessages.remove(at: idx)
        }
        
        HapticFeedback.light()
    }

    // 处理完成操作
    private func handleComplete() {
        print("✅ 用户确认报销，准备保存")

        // 创建Expense（支持多张图片）
        let newExpense = Expense(
            amount: expensePreview.amount,
            title: expensePreview.title,
            category: expensePreview.category,
            event: expensePreview.event,
            occurredAt: expensePreview.occurredAt,
            notes: expensePreview.notes,
            imageData: expensePreview.imageData.isEmpty ? nil : expensePreview.imageData,
            textAttachments: nil
        )

        // 保存到数据库
        modelContext.insert(newExpense)

        do {
            try modelContext.save()
            print("✅ 报销已保存到数据库，ID: \(newExpense.id)")

            // 如果需要创建待办
            if shouldCreateTodo && !todoTitle.isEmpty {
                createTodoForExpense(expenseId: newExpense.id)
            }

            // 更新消息，移除预览显示确认信息
            if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[idx]
                let todoMessage = shouldCreateTodo && !todoTitle.isEmpty ? "，并已添加待办" : ""
                msg.content = "已经为你创建了报销项目「\(expensePreview.title)」- ¥\(expensePreview.amount)\(todoMessage)~"
                msg.expensePreview = nil  // 移除预览，显示确认消息
                appState.chatMessages[idx] = msg

                // 保存AI消息
                appState.saveMessageToStorage(msg, modelContext: modelContext)
            }

            HapticFeedback.success()
        } catch {
            print("❌ 保存报销失败: \(error)")

            // 显示错误信息
            if let idx = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var msg = appState.chatMessages[idx]
                msg.content = "抱歉，保存报销时出错了: \(error.localizedDescription)"
                msg.expensePreview = nil
                appState.chatMessages[idx] = msg
            }
        }
    }

    // 创建关联待办
    private func createTodoForExpense(expenseId: UUID) {
        let todo = TodoItem(
            title: todoTitle.isEmpty ? "提交报销" : todoTitle,
            taskDescription: "报销项目：\(expensePreview.title) - ¥\(expensePreview.amount)",
            startTime: todoStartTime,
            endTime: todoEndTime,
            reminderTime: todoReminderTime,
            imageData: nil,
            textAttachments: nil,
            syncToCalendar: true
        )

        // 关联报销ID
        todo.linkedExpenseId = expenseId

        modelContext.insert(todo)

        do {
            try modelContext.save()
            print("✅ 已创建关联待办: \(todo.title)")

            // 创建日历事件和通知
            Task {
                let eventId = await CalendarManager.shared.createCalendarEvent(
                    title: todo.title,
                    description: todo.taskDescription,
                    startDate: todo.startTime,
                    endDate: todo.endTime,
                    alarmDate: todo.reminderTime
                )
                todo.calendarEventId = eventId

                let notificationId = todo.id.uuidString
                todo.notificationId = notificationId
                await CalendarManager.shared.scheduleNotification(
                    id: notificationId,
                    title: todo.title,
                    body: todo.taskDescription.isEmpty ? nil : todo.taskDescription,
                    date: todo.reminderTime
                )

                try? modelContext.save()
            }
        } catch {
            print("❌ 创建待办失败: \(error)")
        }
    }
    
    // 处理识别错了
    private func handleWrongClassification() {
        print("⚠️ 用户点击「识别错了」按钮")
        NotificationCenter.default.post(
            name: NSNotification.Name("HandleWrongClassification"),
            object: nil,
            userInfo: ["messageId": messageId, "images": originalImages]
        )
    }
}

// ===== 报销信息编辑行组件 =====
struct ExpenseInfoEditRow: View {
    let icon: String
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                .frame(width: 18)

            // 标签
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.65))
                .frame(width: 50, alignment: .leading)

            // 输入框
            TextField(placeholder, text: $text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.black.opacity(0.85))
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.03))
        )
    }
}

// ===== 联系信息编辑行组件 =====
struct ContactInfoEditRow: View {
    let icon: String
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                .frame(width: 18)

            // 标签
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.65))
                .frame(width: 50, alignment: .leading)

            // 输入框
            TextField(placeholder, text: $text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.black.opacity(0.85))
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.03))
        )
    }
}

// ===== 联系人选择器 Sheet =====
struct ContactPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contacts: [Contact]
    @Binding var selectedContact: Contact?
    let onSelect: (Contact) -> Void

    @State private var searchText = ""

    var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contacts
        } else {
            return contacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                contact.company?.localizedCaseInsensitiveContains(searchText) == true ||
                contact.phoneNumber?.contains(searchText) == true
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索框
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color.black.opacity(0.4))

                    TextField("搜索联系人", text: $searchText)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // 联系人列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredContacts) { contact in
                            Button(action: {
                                HapticFeedback.light()
                                selectedContact = contact
                                onSelect(contact)
                                dismiss()
                            }) {
                                HStack(spacing: 12) {
                                    // 头像
                                    ZStack {
                                        if let avatarData = contact.avatarData,
                                           let uiImage = UIImage(data: avatarData) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 44, height: 44)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3),
                                                            Color(red: 0.78, green: 0.98, blue: 0.2).opacity(0.2)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    Text(String(contact.name.prefix(1)))
                                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                                        .foregroundColor(Color.black.opacity(0.6))
                                                )
                                        }
                                    }

                                    // 信息
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(contact.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color.black.opacity(0.9))

                                        if let desc = contact.displayDescription {
                                            Text(desc)
                                                .font(.system(size: 13))
                                                .foregroundColor(Color.black.opacity(0.5))
                                        }
                                    }

                                    Spacer()

                                    // 选中标记
                                    if selectedContact?.id == contact.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
            .navigationTitle("选择联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(Color.black.opacity(0.6))
                }
            }
        }
    }
}

// ===== 自定义 TextEditor（移除默认内边距）=====
struct TextEditorWithoutInsets: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero

        // 设置字体样式
        if let roundedDescriptor = UIFont.systemFont(ofSize: 16, weight: .semibold).fontDescriptor.withDesign(.rounded) {
            textView.font = UIFont(descriptor: roundedDescriptor, size: 16)
        } else {
            textView.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        }
        textView.textColor = UIColor.black.withAlphaComponent(0.9)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // 更新文本
        if uiView.text != text {
            uiView.text = text
        }

        // 处理焦点 - 强制同步状态
        context.coordinator.isUpdatingFocus = true

        if isFocused && !uiView.isFirstResponder {
            print("🔵 TextEditor: 获取焦点")
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            print("🔴 TextEditor: 释放焦点，收起键盘")
            uiView.resignFirstResponder()
        }

        context.coordinator.isUpdatingFocus = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextEditorWithoutInsets
        var isUpdatingFocus = false  // 防止循环更新

        init(_ parent: TextEditorWithoutInsets) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isUpdatingFocus {
                print("📝 TextEditor: 用户开始编辑")
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if !isUpdatingFocus {
                print("✅ TextEditor: 用户结束编辑")
                parent.isFocused = false
            }
        }
    }
}


