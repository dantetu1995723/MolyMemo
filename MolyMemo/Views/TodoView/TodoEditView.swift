import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// 扩展 NSNotification.Name
extension NSNotification.Name {
    static let todoDataDidChange = NSNotification.Name("todoDataDidChange")
}

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
    @State private var textNotes: [String] = []
    @State private var syncToCalendar: Bool = true
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var selectedFiles: [(name: String, data: Data)] = []
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
    @State private var hasVoiceInput: Bool = false
    @State private var silenceStartTime: Date?
    @State private var isApplyingVoiceParse: Bool = false
    
    enum Field: Hashable {
        case title
        case description
        case textAttachment
    }
    
    private let todo: TodoItem?
    private let isEditing: Bool
    
    init(todo: TodoItem? = nil, defaultStartTime: Date? = nil) {
        self.todo = todo
        self.isEditing = todo != nil
        
        var finalStartTime = todo?.startTime ?? defaultStartTime ?? Date()
        
        if todo == nil {
            let calendar = Calendar.current
            if let selectedDate = defaultStartTime {
                finalStartTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
            }
        }
        
        _title = State(initialValue: todo?.title ?? "")
        _taskDescription = State(initialValue: todo?.taskDescription ?? "")
        _startTime = State(initialValue: finalStartTime)
        _endTime = State(initialValue: todo?.endTime ?? finalStartTime.addingTimeInterval(3600))
        _reminderTime = State(initialValue: todo?.reminderTime ?? finalStartTime.addingTimeInterval(-15 * 60))
        _textAttachment = State(initialValue: "")
        _textNotes = State(initialValue: todo?.textAttachments ?? [])
        _syncToCalendar = State(initialValue: todo?.syncToCalendar ?? true)
        
        if let imageDataArray = todo?.imageData {
            let images = imageDataArray.compactMap { UIImage(data: $0) }
            _selectedImages = State(initialValue: images)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义导航栏
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(10)
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                    }
                    
                    Spacer()
                    
                    Text(isEditing ? "编辑日程" : "新建日程")
                        .font(.system(size: 17, weight: .bold))
                    
                    Spacer()
                    
                    Button(action: saveTodo) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.blue))
                    }
                    .disabled(title.isEmpty)
                    .opacity(title.isEmpty ? 0.5 : 1.0)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 标题和描述
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Title", text: $title)
                                .font(.system(size: 28, weight: .bold))
                                .submitLabel(.next)
                                .focused($focusedField, equals: .title)
                            
                            TextField("Description", text: $taskDescription)
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .submitLabel(.done)
                                .focused($focusedField, equals: .description)
                        }
                        .padding(.horizontal, 24)
                        
                        Divider()
                            .padding(.horizontal, 24)
                        
                        // 时间选择
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 20))
                                    .frame(width: 20)
                                
                                // 开始时间胶囊
                                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                    .onChange(of: startTime) { _, newValue in
                                        if endTime <= newValue {
                                            endTime = newValue.addingTimeInterval(3600)
                                        }
                                        if !isApplyingVoiceParse {
                                            reminderTime = newValue.addingTimeInterval(-15 * 60)
                                        }
                                    }
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                
                                // 结束时间胶囊
                                DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                
                                Spacer()
                                
                                let duration = endTime.timeIntervalSince(startTime)
                                Text("\(Int(duration / 3600))h")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                            
                            // 日期显示
                            HStack(spacing: 12) {
                                Color.clear.frame(width: 20)
                                
                                DatePicker("", selection: $startTime, displayedComponents: .date)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // 提醒时间
                        HStack(spacing: 12) {
                            Image(systemName: "bell")
                                .foregroundColor(.gray)
                                .font(.system(size: 20))
                            
                            Text("提醒时间")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            DatePicker("", selection: $reminderTime, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                        }
                        .padding(.horizontal, 24)
                        
                        // 同步日历
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .foregroundColor(.gray)
                                .font(.system(size: 20))
                            
                            Text("同步至系统日历")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Toggle("", isOn: $syncToCalendar)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 24)
                        
                        Divider()
                            .padding(.horizontal, 24)
                        
                        // 附件区域
                        VStack(alignment: .leading, spacing: 16) {
                            Button(action: { 
                                showImagePicker = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "paperclip")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 20))
                                    
                                    Text("上传附件")
                                        .font(.system(size: 16))
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                }
                            }
                            
                            // 显示已选附件
                            if !selectedImages.isEmpty || !selectedFiles.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                            AttachmentImageCard(image: image) {
                                                selectedImages.remove(at: index)
                                            }
                                        }
                                        
                                        ForEach(Array(selectedFiles.enumerated()), id: \.offset) { index, file in
                                            AttachmentFileCard(fileName: file.name, fileSize: formatFileSize(file.data.count)) {
                                                selectedFiles.remove(at: index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 100)
                }
                
                // 底部语音按钮
                VStack {
                    if isVoiceInputActive || isParsingVoice {
                        Text(isParsingVoice ? "正在解析..." : "正在听...")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .padding(.bottom, 8)
                    }
                    
                    ZStack {
                        Capsule()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            .background(Capsule().fill(Color.white))
                            .frame(height: 56)
                        
                        HStack(spacing: 8) {
                            Image(systemName: isVoiceInputActive ? "mic.fill" : "mic")
                                .font(.system(size: 20))
                                .foregroundColor(isVoiceInputActive ? .red : .gray)
                            
                            Text(isVoiceInputActive ? "松开结束" : "长按可语音编辑")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .scaleEffect(isVoiceInputActive ? 0.95 : 1.0)
                    .animation(.spring(response: 0.3), value: isVoiceInputActive)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isVoiceInputActive && !isParsingVoice {
                                    startVoiceInput()
                                }
                            }
                            .onEnded { _ in
                                stopVoiceInput()
                            }
                    )
                }
                .background(Color.white)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showImagePicker) {
            TodoImagePickerView(selectedImages: $selectedImages, isPresented: $showImagePicker)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker(selectedFiles: $selectedFiles, isPresented: $showFilePicker)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            if !isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .title
                }
            }
            speechRecognizer.requestAuthorization()
        }
    }
    
    // MARK: - 语音输入功能
    
    private func startVoiceInput() {
        HapticFeedback.light()
        isVoiceInputActive = true
        recognizedVoiceText = ""
        lastVoiceUpdateTime = Date()
        countdownSeconds = 2
        hasVoiceInput = false
        silenceStartTime = nil
        
        autoStopTask?.cancel()
        countdownTimer?.invalidate()
        
        speechRecognizer.startRecording { text in
            recognizedVoiceText = text
            
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
        
        startSilenceDetection()
    }
    
    private func startSilenceDetection() {
        countdownTimer?.invalidate()
        countdownSeconds = 2
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] timer in
            DispatchQueue.main.async {
                guard let lastUpdate = lastVoiceUpdateTime else { return }
                
                let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
                
                if timeSinceLastUpdate >= 0.5 {
                    if hasVoiceInput {
                        hasVoiceInput = false
                        silenceStartTime = Date()
                        countdownSeconds = 2
                    } else if let silenceStart = silenceStartTime {
                        let silenceDuration = Date().timeIntervalSince(silenceStart)
                        let remaining = max(0, 2 - Int(silenceDuration))
                        
                        if remaining != countdownSeconds {
                            countdownSeconds = remaining
                        }
                        
                        if silenceDuration >= 2.0 {
                            timer.invalidate()
                            if isVoiceInputActive {
                                stopVoiceInput()
                            }
                        }
                    }
                } else {
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
        countdownSeconds = 2
        autoStopTask?.cancel()
        scheduleAutoStop()
    }
    
    private func scheduleAutoStop() {
        autoStopTask?.cancel()
        
        autoStopTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
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
        
        autoStopTask?.cancel()
        autoStopTask = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownSeconds = 0
        hasVoiceInput = false
        silenceStartTime = nil
        
        speechRecognizer.stopRecording()
        isVoiceInputActive = false
        
        if !recognizedVoiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parseAndApplyVoiceCommand()
        } else {
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
                    isApplyingVoiceParse = true
                    
                    if let newTitle = parseResult.title {
                        title = newTitle
                    }
                    
                    if let newDescription = parseResult.taskDescription {
                        taskDescription = newDescription
                    }
                    
                    if let newReminderTime = parseResult.reminderTime {
                        reminderTime = newReminderTime
                    }
                    
                    if let newEndTime = parseResult.endTime {
                        endTime = newEndTime
                    }
                    
                    if let newStartTime = parseResult.startTime {
                        startTime = newStartTime
                        if endTime <= newStartTime {
                            endTime = newStartTime.addingTimeInterval(3600)
                        }
                    }
                    
                    if let newSyncToCalendar = parseResult.syncToCalendar {
                        syncToCalendar = newSyncToCalendar
                    }
                    
                    isParsingVoice = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isApplyingVoiceParse = false
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        recognizedVoiceText = ""
                    }
                    
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    isParsingVoice = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        recognizedVoiceText = ""
                    }
                }
            }
        }
    }
    
    private func saveTodo() {
        HapticFeedback.medium()
        
        
        // 同步更新模型 - 不使用 Task，避免异步问题
        if isEditing, let todo = todo {
            
            // 直接更新模型属性
            todo.title = title
            todo.taskDescription = taskDescription
            todo.startTime = startTime
            todo.endTime = endTime
            todo.reminderTime = reminderTime
            todo.imageData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
            todo.textAttachments = textNotes.isEmpty ? nil : textNotes
            
            
            let wasSynced = todo.syncToCalendar
            todo.syncToCalendar = syncToCalendar
            
            // 检查是否有未保存的更改
            
            // 保存修改
            do {
                try modelContext.save()
            } catch {
            }
            
            // 异步处理日历同步（不影响保存）
            Task {
                if syncToCalendar {
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
                        let eventId = await CalendarManager.shared.createCalendarEvent(
                            title: title,
                            description: taskDescription,
                            startDate: startTime,
                            endDate: endTime,
                            alarmDate: reminderTime
                        )
                        await MainActor.run {
                            todo.calendarEventId = eventId
                            try? modelContext.save()
                        }
                    }
                    
                    let notificationId = todo.notificationId ?? todo.id.uuidString
                    await MainActor.run {
                        todo.notificationId = notificationId
                    }
                    await CalendarManager.shared.updateNotification(
                        id: notificationId,
                        title: title,
                        body: taskDescription.isEmpty ? nil : taskDescription,
                        date: reminderTime
                    )
                } else if wasSynced {
                    if let eventId = todo.calendarEventId {
                        await CalendarManager.shared.deleteCalendarEvent(eventIdentifier: eventId)
                        await MainActor.run {
                            todo.calendarEventId = nil
                            try? modelContext.save()
                        }
                    }
                    if let notificationId = todo.notificationId {
                        CalendarManager.shared.cancelNotification(id: notificationId)
                        await MainActor.run {
                            todo.notificationId = nil
                        }
                    }
                }
            }
        } else {
            // 新建待办
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
            
            modelContext.insert(newTodo)
            
            do {
                try modelContext.save()
            } catch {
            }
            
            // 异步处理日历同步
            if syncToCalendar {
                Task {
                    let eventId = await CalendarManager.shared.createCalendarEvent(
                        title: title,
                        description: taskDescription,
                        startDate: startTime,
                        endDate: endTime,
                        alarmDate: reminderTime
                    )
                    newTodo.calendarEventId = eventId
                    
                    let notificationId = newTodo.id.uuidString
                    newTodo.notificationId = notificationId
                    await CalendarManager.shared.scheduleNotification(
                        id: notificationId,
                        title: title,
                        body: taskDescription.isEmpty ? nil : taskDescription,
                        date: reminderTime
                    )
                    
                    await MainActor.run {
                        try? modelContext.save()
                    }
                }
            }
        }
        
        // 发送数据变更通知
        NotificationCenter.default.post(name: .todoDataDidChange, object: nil)
        dismiss()
    }
    
    // 格式化时间
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    // 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
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

// MARK: - 图片选择器
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

// MARK: - 文件选择器
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedFiles: [(name: String, data: Data)]
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
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
            for url in urls {
                do {
                    var data: Data?
                    
                    if FileManager.default.fileExists(atPath: url.path) {
                        data = try Data(contentsOf: url)
                    } else {
                        let canAccess = url.startAccessingSecurityScopedResource()
                        if canAccess {
                            defer { url.stopAccessingSecurityScopedResource() }
                            data = try Data(contentsOf: url)
                        }
                    }
                    
                    if let data = data {
                        let fileName = url.lastPathComponent
                        selectedFiles.append((name: fileName, data: data))
                    }
                } catch {
                }
            }
            
            isPresented = false
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented = false
        }
    }
}

// MARK: - 附件图片卡片
struct AttachmentImageCard: View {
    let image: UIImage
    let onDelete: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
            
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

// MARK: - 附件文件卡片
struct AttachmentFileCard: View {
    let fileName: String
    let fileSize: String
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: getFileIcon(fileName))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.blue.opacity(0.9))
                    
                    Text(getFileExtension(fileName))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.5))
                        .textCase(.uppercase)
                }
                .frame(width: 90, height: 70)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.1))
                )
                
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
            
            VStack(spacing: 2) {
                Text(fileName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(fileSize)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.black.opacity(0.4))
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
