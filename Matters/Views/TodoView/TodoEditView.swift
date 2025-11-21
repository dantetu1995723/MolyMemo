import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// 待办事项编辑/创建界面
struct TodoEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var taskDescription: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var reminderTime: Date
    @State private var selectedImages: [UIImage] = []
    @State private var textAttachment: String = ""
    @State private var textNotes: [String] = [] // 文本附件列表
    @State private var syncToCalendar: Bool = true
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var selectedFiles: [(name: String, data: Data)] = []
    @State private var showContent = false
    @State private var showMoreOptions = false
    @FocusState private var focusedField: Field?
    
    // 语音输入相关
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isVoiceInputActive = false
    @State private var recognizedVoiceText = ""
    @State private var isParsingVoice = false
    @State private var lastVoiceUpdateTime: Date?
    @State private var autoStopTask: Task<Void, Never>?
    @State private var countdownSeconds: Int = 0
    @State private var countdownTimer: Timer?
    @State private var hasVoiceInput: Bool = false // 是否有语音输入
    @State private var silenceStartTime: Date? // 无声音开始时间
    @State private var isApplyingVoiceParse: Bool = false // 是否正在应用语音解析结果
    
    enum Field: Hashable {
        case title
        case description
        case textAttachment
    }
    
    private let todo: TodoItem?
    private let isEditing: Bool
    
    init(todo: TodoItem? = nil) {
        self.todo = todo
        self.isEditing = todo != nil
        
        // 初始化状态
        let defaultStartTime = todo?.startTime ?? Date()
        _title = State(initialValue: todo?.title ?? "")
        _taskDescription = State(initialValue: todo?.taskDescription ?? "")
        _startTime = State(initialValue: defaultStartTime)
        _endTime = State(initialValue: todo?.endTime ?? defaultStartTime.addingTimeInterval(3600))
        _reminderTime = State(initialValue: todo?.reminderTime ?? defaultStartTime.addingTimeInterval(-15 * 60))
        _textAttachment = State(initialValue: "")
        _textNotes = State(initialValue: todo?.textAttachments ?? [])
        _syncToCalendar = State(initialValue: todo?.syncToCalendar ?? true)
        
        // 加载图片
        if let imageDataArray = todo?.imageData {
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
                            // 语音输入区域
                            if isVoiceInputActive || !recognizedVoiceText.isEmpty {
                                VoiceInputCard(
                                    isRecording: speechRecognizer.isRecording,
                                    recognizedText: recognizedVoiceText,
                                    isParsing: isParsingVoice,
                                    hasVoiceInput: hasVoiceInput,
                                    countdownSeconds: countdownSeconds
                                )
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                            }
                            
                            // 核心信息卡片
                            VStack(spacing: 0) {
                                // 标题输入
                                TextField("事项名称", text: $title)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .background(Color.white)
                                    .focused($focusedField, equals: .title)
                                
                                Divider()
                                    .padding(.horizontal, 18)
                                
                                // 描述输入
                                ZStack(alignment: .topLeading) {
                                    if taskDescription.isEmpty {
                                        Text("添加描述...")
                                            .font(.system(size: 15, design: .rounded))
                                            .foregroundColor(Color.black.opacity(0.3))
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 16)
                                    }
                                    
                                    TextEditor(text: $taskDescription)
                                        .font(.system(size: 15, weight: .regular, design: .rounded))
                                        .frame(minHeight: 80)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.white)
                                        .focused($focusedField, equals: .description)
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            // 时间卡片 - 紧凑设计
                            VStack(spacing: 12) {
                                // 开始时间
                                TimeRowView(
                                    icon: "clock.fill",
                                    label: "开始",
                                    time: $startTime,
                                    onChange: { newValue in
                                        if endTime <= newValue {
                                            endTime = newValue.addingTimeInterval(3600)
                                        }
                                        // 只有在非语音解析模式下才自动调整提醒时间
                                        if !isApplyingVoiceParse {
                                        reminderTime = newValue.addingTimeInterval(-15 * 60)
                                        }
                                    }
                                )
                                
                                Divider()
                                    .padding(.horizontal, 18)
                                
                                // 结束时间
                                TimeRowView(
                                    icon: "flag.fill",
                                    label: "结束",
                                    time: $endTime,
                                    timeRange: startTime...
                                )
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                            )
                            .padding(.horizontal, 20)
                            
                            // 提醒时间
                            VStack(spacing: 0) {
                                TimeRowView(
                                    icon: "bell.fill",
                                    label: "提醒",
                                    time: $reminderTime
                                )
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                            )
                            .padding(.horizontal, 20)
                            
                            // 同步到日历开关
                            HStack(spacing: 14) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("同步到系统日历")
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.75))
                                    
                                    Text("在系统日历中创建事件并设置提醒")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundColor(Color.black.opacity(0.4))
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $syncToCalendar)
                                    .labelsHidden()
                                    .tint(Color(red: 0.85, green: 1.0, blue: 0.25))
                                    .onChange(of: syncToCalendar) { _, _ in
                                        HapticFeedback.light()
                                    }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                            )
                            .padding(.horizontal, 20)
                            
                            // 更多选项切换
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
                                    
                                    Text(showMoreOptions ? "收起选项" : "更多选项")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                                        .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                                        .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                                        .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
                                    
                                    Spacer()
                                    
                                    let hasAttachments = !selectedImages.isEmpty || !selectedFiles.isEmpty
                                    
                                    if hasAttachments {
                                        Circle()
                                            .fill(Color(red: 0.85, green: 1.0, blue: 0.25))
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            
                            // 展开的更多选项
                            if showMoreOptions {
                                VStack(spacing: 16) {
                                    // 附件区域
                                    VStack(spacing: 12) {
                                        // 简化的附件列表
                                        let totalAttachments = selectedImages.count + selectedFiles.count
                                        
                                        if totalAttachments > 0 {
                                            VStack(alignment: .leading, spacing: 8) {
                                                // 标题
                                                HStack(spacing: 8) {
                                                    Image(systemName: "paperclip")
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                                                    
                                                    Text("附件 (\(totalAttachments))")
                                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                        .foregroundColor(Color.black.opacity(0.7))
                                                }
                                                .padding(.horizontal, 18)
                                                
                                                // 附件列表
                                                VStack(spacing: 6) {
                                                    // 图片附件
                                                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                                        AttachmentListRow(
                                                            icon: "photo",
                                                            title: "图片 \(index + 1)",
                                                            subtitle: nil,
                                                            color: .blue,
                                                            onDelete: {
                                                                selectedImages.remove(at: index)
                                                                HapticFeedback.light()
                                                            }
                                                        )
                                                    }
                                                    
                                                    // 文件附件
                                                    ForEach(Array(selectedFiles.enumerated()), id: \.offset) { index, file in
                                                        AttachmentListRow(
                                                            icon: "doc",
                                                            title: file.name,
                                                            subtitle: formatFileSize(file.data.count),
                                                            color: Color(red: 0.85, green: 1.0, blue: 0.25),
                                                            onDelete: {
                                                                selectedFiles.remove(at: index)
                                                                HapticFeedback.light()
                                                            }
                                                        )
                                                    }
                                                }
                                                .padding(.horizontal, 18)
                                            }
                                            .padding(.vertical, 8)
                                        }
                                        
                                        // 附件按钮
                                        HStack(spacing: 10) {
                                            Button(action: {
                                                showImagePicker = true
                                                HapticFeedback.light()
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "photo")
                                                        .font(.system(size: 14, weight: .medium))
                                                    Text("图片")
                                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                                }
                                                .foregroundColor(Color.black.opacity(0.6))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 11)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(Color.black.opacity(0.15), lineWidth: 1.5)
                                                )
                                            }
                                            
                                            Button(action: {
                                                showFilePicker = true
                                                HapticFeedback.light()
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "doc")
                                                        .font(.system(size: 14, weight: .medium))
                                                    Text("文件")
                                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                                }
                                                .foregroundColor(Color.black.opacity(0.6))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 11)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(Color.black.opacity(0.15), lineWidth: 1.5)
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 18)
                                    }
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                                    )
                                }
                                .padding(.horizontal, 20)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                
                // 底部按钮区域
                VStack {
                    Spacer()
                    
                    if showContent {
                        HStack(spacing: 12) {
                            // 删除按钮（仅编辑模式显示）
                            if isEditing {
                                Button(action: deleteTodo) {
                                    Text("删除")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundColor(.red.opacity(0.8))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.red.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1.5)
                                                )
                                        )
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                            
                            // 保存按钮
                            Button(action: saveTodo) {
                                Text(isEditing ? "保存修改" : "创建待办")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.white)
                                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
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
                                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.4), radius: 16, x: 0, y: 4)
                                    )
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(title.isEmpty)
                            .opacity(title.isEmpty ? 0.5 : 1.0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑待办" : "新建待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(Color.black.opacity(0.6))
                }
                
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? "编辑待办" : "新建待办")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        toggleVoiceInput()
                    }) {
                        Image(systemName: isVoiceInputActive ? "mic.fill" : "mic")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isVoiceInputActive ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.black.opacity(0.6))
                    }
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            TodoImagePickerView(selectedImages: $selectedImages, isPresented: $showImagePicker)
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker(selectedFiles: $selectedFiles, isPresented: $showFilePicker)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                showContent = true
            }
            
            // 自动聚焦到标题
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = .title
            }
            
            // 请求语音识别权限
            speechRecognizer.requestAuthorization()
        }
    }
    
    // MARK: - 语音输入功能
    
    private func toggleVoiceInput() {
        if isVoiceInputActive {
            stopVoiceInput()
        } else {
            startVoiceInput()
        }
    }
    
    private func startVoiceInput() {
        HapticFeedback.light()
        isVoiceInputActive = true
        recognizedVoiceText = ""
        lastVoiceUpdateTime = Date()
        countdownSeconds = 2
        hasVoiceInput = false
        silenceStartTime = nil
        
        // 取消之前的自动停止任务和计时器
        autoStopTask?.cancel()
        countdownTimer?.invalidate()
        
        speechRecognizer.startRecording { text in
            recognizedVoiceText = text
            
            // 检测到有新的语音输入
            if !text.isEmpty {
                DispatchQueue.main.async {
                    hasVoiceInput = true
                    lastVoiceUpdateTime = Date()
                    countdownSeconds = 2
                    silenceStartTime = nil
                    resetAutoStop()
                }
            }
        }
        
        // 启动检测无声音的倒计时
        startSilenceDetection()
    }
    
    private func startSilenceDetection() {
        countdownTimer?.invalidate()
        countdownSeconds = 2
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] timer in
            DispatchQueue.main.async {
                guard let lastUpdate = lastVoiceUpdateTime else { return }
                
                let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
                
                // 如果超过0.5秒没有新输入，认为无声音
                if timeSinceLastUpdate >= 0.5 {
                    if hasVoiceInput {
                        // 刚进入无声音状态
                        hasVoiceInput = false
                        silenceStartTime = Date()
                        countdownSeconds = 2
                    } else if let silenceStart = silenceStartTime {
                        // 已经在无声音状态，计算剩余时间
                        let silenceDuration = Date().timeIntervalSince(silenceStart)
                        let remaining = max(0, 2 - Int(silenceDuration))
                        
                        if remaining != countdownSeconds {
                            countdownSeconds = remaining
                        }
                        
                        // 如果无声音超过2秒，自动停止
                        if silenceDuration >= 2.0 {
                            timer.invalidate()
                            if isVoiceInputActive {
                                stopVoiceInput()
                            }
                        }
                    }
                } else {
                    // 有声音输入，重置无声音状态
                    if !hasVoiceInput {
                        hasVoiceInput = true
                        silenceStartTime = nil
                        countdownSeconds = 2
                    }
                }
            }
        }
    }
    
    private func resetAutoStop() {
        // 重置倒计时
        countdownSeconds = 2
        
        // 取消之前的任务
        autoStopTask?.cancel()
        
        // 重新启动自动停止任务
        scheduleAutoStop()
    }
    
    private func scheduleAutoStop() {
        // 取消之前的任务
        autoStopTask?.cancel()
        
        // 创建新的自动停止任务：如果2秒内没有新的语音输入，自动停止
        autoStopTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
            
            // 检查是否仍在录音且没有新的更新
            if isVoiceInputActive && !Task.isCancelled {
                if let lastUpdate = lastVoiceUpdateTime,
                   Date().timeIntervalSince(lastUpdate) >= 1.8 {
                    await MainActor.run {
                        stopVoiceInput()
                    }
                }
            }
        }
    }
    
    private func stopVoiceInput() {
        guard isVoiceInputActive else { return }
        
        HapticFeedback.medium()
        
        // 取消自动停止任务和计时器
        autoStopTask?.cancel()
        autoStopTask = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownSeconds = 0
        hasVoiceInput = false
        silenceStartTime = nil
        
        speechRecognizer.stopRecording()
        isVoiceInputActive = false
        
        // 如果有识别到的文字，自动进行解析
        if !recognizedVoiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parseAndApplyVoiceCommand()
        } else {
            // 如果没有识别到文字，清空状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                recognizedVoiceText = ""
            }
        }
    }
    
    private func parseAndApplyVoiceCommand() {
        guard !recognizedVoiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isParsingVoice = true
        
        Task {
            do {
                let parseResult = try await TodoVoiceParser.parseVoiceCommand(
                    voiceText: recognizedVoiceText,
                    existingTitle: title,
                    existingDescription: taskDescription,
                    existingStartTime: startTime,
                    existingEndTime: endTime,
                    existingReminderTime: reminderTime,
                    existingSyncToCalendar: syncToCalendar
                )
                
                await MainActor.run {
                    // 标记正在应用语音解析结果
                    isApplyingVoiceParse = true
                    
                    let voiceTextLower = recognizedVoiceText.lowercased()
                    
                    // 应用解析结果
                    var finalTitle = title
                    var titleUpdated = false
                    if let newTitle = parseResult.title {
                        finalTitle = newTitle
                        title = newTitle
                        titleUpdated = true
                        print("📝 更新title: \(newTitle)")
                    }
                    
                    var finalDescription = taskDescription
                    if let newDescription = parseResult.taskDescription {
                        // 判断是替换还是追加
                        // 明确说要修改/改成/改为/替换/设置备注 -> 完全替换
                        let replaceKeywords = ["修改", "改成", "改为", "替换", "设置备注", "备注是", "备注为"]
                        let shouldReplace = replaceKeywords.contains { voiceTextLower.contains($0) }
                        
                        // 明确说要添加/补充 -> 追加
                        let appendKeywords = ["添加", "补充", "追加", "加上"]
                        let shouldAppend = appendKeywords.contains { voiceTextLower.contains($0) }
                        
                        if shouldReplace {
                            // 替换模式：完全替换备注
                            finalDescription = newDescription
                            taskDescription = newDescription
                        } else if shouldAppend {
                            // 追加模式：追加到现有备注
                            if taskDescription.isEmpty {
                                finalDescription = newDescription
                                taskDescription = newDescription
                            } else {
                                finalDescription = taskDescription + "\n" + newDescription
                                taskDescription = finalDescription
                            }
                        } else {
                            // 默认模式：如果备注为空则设置，否则替换（避免累积错误信息）
                            finalDescription = newDescription
                            taskDescription = newDescription
                        }
                        print("📝 更新备注: \(newDescription)")
                    } else if titleUpdated && !taskDescription.isEmpty {
                        // 关键修复：如果title更新了，但AI没有返回新的备注
                        // 说明新的语音输入没有包含备注信息，应该清空旧备注
                        print("🔄 title已更新但AI未返回备注，清空旧备注避免不一致")
                        taskDescription = ""
                        finalDescription = ""
                    }
                    
                    // 应用解析结果 - 优先计算并设置提醒时间，避免被 startTime 的 onChange 覆盖
                    
                    // 计算最终的提醒时间（在设置 startTime 之前）
                    var finalReminderTime: Date? = nil
                    
                    if let newReminderTime = parseResult.reminderTime {
                        // AI已经解析出提醒时间，检查是否合理
                        let currentStartTime = parseResult.startTime ?? startTime
                        
                        if newReminderTime < currentStartTime {
                            // 提醒时间早于开始时间，合理，直接使用
                            finalReminderTime = newReminderTime
                            print("✅ 使用AI解析的提醒时间: \(newReminderTime)")
                        } else {
                            // 提醒时间晚于或等于开始时间，不合理，需要重新计算
                            print("⚠️ AI返回的提醒时间(\(newReminderTime))不早于开始时间(\(currentStartTime))，需要重新计算")
                            
                            // 检查语音中是否明确说了相对时间
                            var timeOffset: TimeInterval = -900 // 默认15分钟前
                            
                            if voiceTextLower.contains("前一小时") || voiceTextLower.contains("前1小时") {
                                timeOffset = -3600
                            } else if voiceTextLower.contains("前半小时") || voiceTextLower.contains("前30分钟") {
                                timeOffset = -1800
                            } else if voiceTextLower.contains("前15分钟") {
                                timeOffset = -900
                            } else if voiceTextLower.contains("前两小时") || voiceTextLower.contains("前2小时") {
                                timeOffset = -7200
                            } else if voiceTextLower.contains("提前") {
                                if voiceTextLower.contains("一小时") || voiceTextLower.contains("1小时") {
                                    timeOffset = -3600
                                } else if voiceTextLower.contains("半小时") || voiceTextLower.contains("30分钟") {
                                    timeOffset = -1800
                                }
                            }
                            
                            finalReminderTime = currentStartTime.addingTimeInterval(timeOffset)
                            print("🔄 重新计算提醒时间: \(finalReminderTime!)")
                        }
                    } else {
                        // AI没有返回提醒时间
                        if let newStartTime = parseResult.startTime {
                            // 如果更新了开始时间，检查当前提醒时间是否还合理
                        if reminderTime >= newStartTime {
                                // 当前提醒时间不合理，重新计算
                                // 检查语音中是否说了相对时间
                                var timeOffset: TimeInterval = -900 // 默认15分钟前
                                
                                if voiceTextLower.contains("前一小时") || voiceTextLower.contains("前1小时") {
                                    timeOffset = -3600
                                } else if voiceTextLower.contains("前半小时") || voiceTextLower.contains("前30分钟") {
                                    timeOffset = -1800
                                } else if voiceTextLower.contains("前15分钟") {
                                    timeOffset = -900
                                } else if voiceTextLower.contains("前两小时") || voiceTextLower.contains("前2小时") {
                                    timeOffset = -7200
                                } else if voiceTextLower.contains("提前") {
                                    if voiceTextLower.contains("一小时") || voiceTextLower.contains("1小时") {
                                        timeOffset = -3600
                                    } else if voiceTextLower.contains("半小时") || voiceTextLower.contains("30分钟") {
                                        timeOffset = -1800
                                    }
                                }
                                
                                finalReminderTime = newStartTime.addingTimeInterval(timeOffset)
                                print("🔄 AI未返回提醒时间，根据开始时间计算: \(finalReminderTime!)")
                        }
                            // 如果reminderTime < newStartTime，说明已经是合理的，不需要修改
                        }
                    }
                    
                    // 1. 先设置提醒时间（在设置 startTime 之前）
                    if let finalReminder = finalReminderTime {
                        reminderTime = finalReminder
                    }
                    
                    // 2. 应用结束时间
                    if let newEndTime = parseResult.endTime {
                        endTime = newEndTime
                    }
                    
                    // 3. 最后应用开始时间（此时提醒时间已经设置好了，即使触发 onChange 也不会被覆盖）
                    if let newStartTime = parseResult.startTime {
                        startTime = newStartTime
                        
                        // 如果结束时间早于开始时间，自动调整
                        if endTime <= newStartTime {
                            endTime = newStartTime.addingTimeInterval(3600)
                        }
                    }
                    
                    if let newSyncToCalendar = parseResult.syncToCalendar {
                        syncToCalendar = newSyncToCalendar
                    }
                    
                    isParsingVoice = false
                    
                    // 延迟取消标记，确保 SwiftUI 的 onChange 回调执行完毕
                    // SwiftUI 会在当前 MainActor.run 闭包执行完后批量更新 UI 并触发 onChange
                    // 我们需要等待这些 onChange 执行完毕后再重置标记
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isApplyingVoiceParse = false
                    }
                    
                    // 延迟清空识别文字
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        recognizedVoiceText = ""
                    }
                    
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    isParsingVoice = false
                    print("❌ 解析语音指令失败: \(error)")
                    
                    // 延迟清空识别文字
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        recognizedVoiceText = ""
                    }
                }
            }
        }
    }
    
    private func saveTodo() {
        HapticFeedback.medium()
        
        Task {
            if isEditing, let todo = todo {
                // 更新现有待办
                todo.title = title
                todo.taskDescription = taskDescription
                todo.startTime = startTime
                todo.endTime = endTime
                todo.reminderTime = reminderTime
                todo.imageData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
                todo.textAttachments = textNotes.isEmpty ? nil : textNotes
                
                // 处理日历同步变化
                let wasSynced = todo.syncToCalendar
                todo.syncToCalendar = syncToCalendar
                
                if syncToCalendar {
                    // 如果之前有事件ID，更新；否则创建新事件
                    if let eventId = todo.calendarEventId {
                        await CalendarManager.shared.updateCalendarEvent(
                            eventIdentifier: eventId,
                            title: title,
                            description: taskDescription,
                            startDate: startTime,
                            endDate: endTime,
                            alarmDate: reminderTime
                        )
                    } else {
                        // 创建新的日历事件
                        let eventId = await CalendarManager.shared.createCalendarEvent(
                            title: title,
                            description: taskDescription,
                            startDate: startTime,
                            endDate: endTime,
                            alarmDate: reminderTime
                        )
                        todo.calendarEventId = eventId
                    }
                    
                    // 更新本地通知
                    let notificationId = todo.notificationId ?? todo.id.uuidString
                    todo.notificationId = notificationId
                    await CalendarManager.shared.updateNotification(
                        id: notificationId,
                        title: title,
                        body: taskDescription.isEmpty ? nil : taskDescription,
                        date: reminderTime
                    )
                } else if wasSynced {
                    // 如果之前是同步的，现在取消同步，则删除事件和通知
                    if let eventId = todo.calendarEventId {
                        await CalendarManager.shared.deleteCalendarEvent(eventIdentifier: eventId)
                        todo.calendarEventId = nil
                    }
                    if let notificationId = todo.notificationId {
                        CalendarManager.shared.cancelNotification(id: notificationId)
                        todo.notificationId = nil
                    }
                }
            } else {
                // 创建新待办
                let newTodo = TodoItem(
                    title: title,
                    taskDescription: taskDescription,
                    startTime: startTime,
                    endTime: endTime,
                    reminderTime: reminderTime,
                    imageData: selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) },
                    textAttachments: textNotes.isEmpty ? nil : textNotes,
                    syncToCalendar: syncToCalendar
                )
                
                // 如果需要同步到日历
                if syncToCalendar {
                    let eventId = await CalendarManager.shared.createCalendarEvent(
                        title: title,
                        description: taskDescription,
                        startDate: startTime,
                        endDate: endTime,
                        alarmDate: reminderTime
                    )
                    newTodo.calendarEventId = eventId
                    
                    // 创建本地通知
                    let notificationId = newTodo.id.uuidString
                    newTodo.notificationId = notificationId
                    await CalendarManager.shared.scheduleNotification(
                        id: notificationId,
                        title: title,
                        body: taskDescription.isEmpty ? nil : taskDescription,
                        date: reminderTime
                    )
                }
                
                modelContext.insert(newTodo)
            }
            
            try? modelContext.save()
            
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    private func deleteTodo() {
        guard let todo = todo else { return }
        
        HapticFeedback.medium()
        
        Task {
            // 删除日历事件
            if let eventId = todo.calendarEventId {
                await CalendarManager.shared.deleteCalendarEvent(eventIdentifier: eventId)
            }
            
            // 取消本地通知
            if let notificationId = todo.notificationId {
                CalendarManager.shared.cancelNotification(id: notificationId)
            }
            
            await MainActor.run {
                modelContext.delete(todo)
                try? modelContext.save()
                dismiss()
            }
        }
    }
    
    // 格式化文件大小
    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

// 图片选择器（不自动关闭）
struct TodoImagePickerView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 9
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedImages: $selectedImages, isPresented: $isPresented)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding var selectedImages: [UIImage]
        @Binding var isPresented: Bool
        
        init(selectedImages: Binding<[UIImage]>, isPresented: Binding<Bool>) {
            _selectedImages = selectedImages
            _isPresented = isPresented
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                isPresented = false
                return
            }
            
            Task {
                var loadedImages: [UIImage] = []
                
                for result in results {
                    let provider = result.itemProvider
                    
                    if provider.canLoadObject(ofClass: UIImage.self) {
                        do {
                            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
                                provider.loadObject(ofClass: UIImage.self) { object, error in
                                    if let error = error {
                                        continuation.resume(throwing: error)
                                    } else if let image = object as? UIImage {
                                        continuation.resume(returning: image)
                                    } else {
                                        continuation.resume(throwing: NSError(domain: "ImagePicker", code: -1))
                                    }
                                }
                            }
                            loadedImages.append(image)
                        } catch {
                            print("加载图片失败: \(error)")
                        }
                    }
                }
                
                await MainActor.run {
                    selectedImages.append(contentsOf: loadedImages)
                    isPresented = false
                }
            }
        }
    }
}

// 文件选择器（支持所有文件类型）
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedFiles: [(name: String, data: Data)]
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 使用 .item 类型支持所有文件
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedFiles: $selectedFiles, isPresented: $isPresented)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        @Binding var selectedFiles: [(name: String, data: Data)]
        @Binding var isPresented: Bool
        
        init(selectedFiles: Binding<[(name: String, data: Data)]>, isPresented: Binding<Bool>) {
            _selectedFiles = selectedFiles
            _isPresented = isPresented
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print("📄 选择了 \(urls.count) 个文件")
            
            for url in urls {
                print("📄 正在处理文件: \(url.lastPathComponent)")
                print("📄 文件路径: \(url.path)")
                print("📄 是否可访问: \(FileManager.default.isReadableFile(atPath: url.path))")
                
                // 尝试直接读取（因为使用了asCopy，文件应该已经复制到app沙盒）
                do {
                    // 先尝试直接读取
                    var data: Data?
                    
                    // 方法1：直接读取
                    if FileManager.default.fileExists(atPath: url.path) {
                        data = try Data(contentsOf: url)
                        print("✅ 方法1成功: 直接读取")
                    } else {
                        // 方法2：使用安全作用域
                        let canAccess = url.startAccessingSecurityScopedResource()
                        print("📄 安全作用域访问: \(canAccess)")
                        
                        if canAccess {
                            defer { url.stopAccessingSecurityScopedResource() }
                            data = try Data(contentsOf: url)
                            print("✅ 方法2成功: 安全作用域读取")
                        }
                    }
                    
                    if let data = data {
                        let fileName = url.lastPathComponent
                        selectedFiles.append((name: fileName, data: data))
                        print("✅ 文件添加成功: \(fileName), 大小: \(data.count) bytes")
                    } else {
                        print("❌ 无法读取文件: \(url.lastPathComponent)")
                    }
                } catch {
                    print("❌ 读取文件失败: \(url.lastPathComponent)")
                    print("❌ 错误详情: \(error.localizedDescription)")
                }
            }
            
            print("📄 最终添加了 \(selectedFiles.count) 个文件")
            isPresented = false
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("📄 用户取消选择")
            isPresented = false
        }
    }
}

// 文本附件卡片
struct AttachmentTextCard: View {
    let content: String
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 文本内容区域
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(Color.blue.opacity(0.8))
                    
                    Text(content.prefix(20))
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                }
                .frame(width: 90, height: 70)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.12),
                                    Color.blue.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                )
                
                // 删除按钮
                Button(action: onDelete) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .offset(x: 6, y: -6)
            }
            
            // 文本信息
            VStack(spacing: 2) {
                Text("文本")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.7))
                
                Text("\(content.count) 字")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.4))
            }
            .frame(width: 90)
            .padding(.top, 4)
        }
    }
}

// 文本输入Sheet
struct TextInputSheet: View {
    @Binding var textNotes: [String]
    @Binding var isPresented: Bool
    @State private var inputText: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $inputText)
                    .font(.system(size: 16, design: .rounded))
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                
                Spacer()
            }
            .background(Color.white)
            .navigationTitle("添加文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            textNotes.append(inputText)
                        }
                        isPresented = false
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// 时间行视图组件
struct TimeRowView: View {
    let icon: String
    let label: String
    @Binding var time: Date
    var timeRange: PartialRangeFrom<Date>?
    var onChange: ((Date) -> Void)?
    
    var body: some View {
        HStack(spacing: 14) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8))
                .frame(width: 24)
            
            // 标签
            Text(label)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.75))
                .frame(width: 50, alignment: .leading)
            
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// 附件列表行组件
struct AttachmentListRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let color: Color
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.12))
                )
            
            // 文本信息
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.8))
                    .lineLimit(1)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.4))
                }
            }
            
            Spacer()
            
            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.black.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

// 图片附件卡片
struct AttachmentImageCard: View {
    let image: UIImage
    let onDelete: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 图片
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
            
            // 删除按钮
            Button(action: onDelete) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(x: 6, y: -6)
        }
    }
}

// 语音输入卡片
struct VoiceInputCard: View {
    let isRecording: Bool
    let recognizedText: String
    let isParsing: Bool
    let hasVoiceInput: Bool
    let countdownSeconds: Int
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 录音指示器
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red.opacity(0.2) : Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    if isRecording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .scaleEffect(isRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
                    } else if isParsing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.85, green: 1.0, blue: 0.25)))
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                    }
                }
                
                // 识别文字
                VStack(alignment: .leading, spacing: 4) {
                    if isParsing {
                        Text("正在解析...")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.6))
                    } else if isRecording {
                        if hasVoiceInput {
                            Text("正在录音")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Color.black.opacity(0.6))
                        } else {
                            Text("检测到无声音，\(countdownSeconds)秒后进行解析")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Color.black.opacity(0.6))
                        }
                    } else {
                        Text("识别完成")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.6))
                    }
                    
                    if !recognizedText.isEmpty {
                        Text(recognizedText)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.8))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
    }
}

// 文件附件卡片
struct AttachmentFileCard: View {
    let fileName: String
    let fileSize: String
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 文件图标区域
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: getFileIcon(fileName))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.9))
                    
                    Text(getFileExtension(fileName))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.5))
                        .textCase(.uppercase)
                }
                .frame(width: 90, height: 70)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.12),
                                    Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), lineWidth: 1)
                )
                
                // 删除按钮
                Button(action: onDelete) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .offset(x: 6, y: -6)
            }
            
            // 文件信息
            VStack(spacing: 2) {
                Text(fileName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(fileSize)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.4))
            }
            .frame(width: 90)
            .padding(.top, 4)
        }
    }
    
    private func getFileExtension(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? "FILE" : ext
    }
    
    private func getFileIcon(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "chart.bar.doc.horizontal.fill"
        case "txt":
            return "text.alignleft"
        case "zip", "rar", "7z":
            return "doc.zipper"
        default:
            return "doc.fill"
        }
    }
}

