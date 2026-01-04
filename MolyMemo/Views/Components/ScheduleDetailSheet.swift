import SwiftUI

struct ScheduleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var event: ScheduleEvent
    var onDelete: () -> Void
    var onSave: (ScheduleEvent) -> Void
    
    @State private var editedEvent: ScheduleEvent
    @State private var showDeleteMenu = false
    @State private var activeDatePicker: DatePickerType? = nil
    @State private var startTimeAreaFrame: CGRect = .zero
    @State private var endTimeAreaFrame: CGRect = .zero
    @State private var hasUserEdited: Bool = false
    
    // 提交状态（保存/删除）
    @State private var isSubmitting: Bool = false
    @State private var submittingAction: SubmittingAction? = nil
    @State private var alertMessage: String? = nil

    // MARK: - 仅用于 UI 复刻（不写回 ScheduleEvent，避免与数据模型冲突）
    @State private var uiAllDay: Bool = false
    @State private var uiReminderText: String = "开始前 30 分钟"
    @State private var uiCategoryName: String = "商务宴请"
    @State private var uiCategoryColor: Color = Color(hex: "FF8A00")
    
    enum DatePickerType {
        case start, end
    }
    
    private enum SubmittingAction {
        case save
        case delete
        
        var text: String {
            switch self {
            case .save: return "正在保存…"
            case .delete: return "正在删除…"
            }
        }
    }
    
    // 语音输入相关
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isRecording = false
    @State private var isAnimatingRecordingExit = false
    @State private var isCanceling = false
    @State private var audioPower: CGFloat = 0.0
    @State private var recordingTranscript: String = ""
    @State private var buttonFrame: CGRect = .zero
    @State private var isPressing = false
    @State private var pressStartTime: Date?
    
    private let silenceGate: Float = 0.12
    
    // 颜色定义
    private let bgColor = Color(red: 0.97, green: 0.97, blue: 0.97)
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    private let iconColor = Color(hex: "CCCCCC")
    
    init(event: Binding<ScheduleEvent>, onDelete: @escaping () -> Void, onSave: @escaping (ScheduleEvent) -> Void) {
        self._event = event
        self.onDelete = onDelete
        self.onSave = onSave
        self._editedEvent = State(initialValue: event.wrappedValue)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header
                ZStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.secondary.opacity(0.15)))
                        }
                        .disabled(isSubmitting)
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showDeleteMenu = true
                                }
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                            .disabled(isSubmitting)
                            
                            Button(action: {
                                Task { await submitSave() }
                            }) {
                                ZStack {
                                    if isSubmitting, submittingAction == .save {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(primaryTextColor)
                                    } else {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(primaryTextColor)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                            .disabled(isSubmitting)
                        }
                    }
                    
                    Text("日程详情")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(primaryTextColor)
                    
                    if showDeleteMenu {
                        TopDeletePillButton(
                            onDelete: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDeleteMenu = false }
                                HapticFeedback.medium()
                                Task { await submitDelete() }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 44 + 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .zIndex(100)
                
                ZStack {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // 标题区域
                            ZStack {
                                TextField("日程标题", text: $editedEvent.title)
                                    .font(.system(size: 34, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(primaryTextColor)
                                    .lineLimit(1)
                                    .padding(.horizontal, 64)
                            }
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .trailing) {
                                if editedEvent.hasConflict {
                                    Text("有日程冲突")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(Color(hex: "F5A623"))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(hex: "F5A623"), lineWidth: 1)
                                        )
                                        .padding(.trailing, 20)
                                }
                            }
                            .padding(.top, 10)
                            
                            // 时间区域
                            HStack(alignment: .center, spacing: 0) {
                                // 开始时间
                                Button(action: {
                                    withAnimation(.spring()) { activeDatePicker = .start }
                                }) {
                                    VStack(alignment: .center, spacing: 4) {
                                        Text(formatDate(editedEvent.startTime))
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundColor(activeDatePicker == .start ? .blue : secondaryTextColor)
                                        
                                        Text(formatTime(editedEvent.startTime))
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(activeDatePicker == .start ? .blue : primaryTextColor)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .modifier(GlobalFrameReporter(frame: $startTimeAreaFrame))
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundColor(Color(hex: "E0E0E0"))
                                    .offset(y: 12)
                                
                                // 结束时间
                                Button(action: {
                                    withAnimation(.spring()) { activeDatePicker = .end }
                                }) {
                                    VStack(alignment: .center, spacing: 4) {
                                        Text(formatDate(editedEvent.endTime))
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundColor(activeDatePicker == .end ? .blue : secondaryTextColor)
                                        
                                        Text(formatTime(editedEvent.endTime))
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(activeDatePicker == .end ? .blue : primaryTextColor)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .modifier(GlobalFrameReporter(frame: $endTimeAreaFrame))
                            }
                            .padding(.horizontal, 20)
                            
                            // 第一条分割线
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            
                            // 设置选项区域（全天、提醒时间、日程分类、地点）
                            VStack(spacing: 20) {
                                // 全天
                                HStack(spacing: 16) {
                                    Image(systemName: "sun.max")
                                        .font(.system(size: 18))
                                        .foregroundColor(iconColor)
                                        .frame(width: 24)
                                    
                                    Text("全天")
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: $uiAllDay)
                                        .labelsHidden()
                                        .tint(.blue)
                                }
                                
                                // 提醒时间
                                HStack(spacing: 16) {
                                    Image(systemName: "bell")
                                        .font(.system(size: 18))
                                        .foregroundColor(iconColor)
                                        .frame(width: 24)
                                    
                                    Text("提醒时间")
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 6) {
                                        Text(uiReminderText)
                                            .font(.system(size: 16))
                                            .foregroundColor(secondaryTextColor)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(iconColor)
                                    }
                                }
                                
                                // 日程分类
                                HStack(spacing: 16) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 18))
                                        .foregroundColor(iconColor)
                                        .frame(width: 24)
                                    
                                    Text("日程分类")
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(uiCategoryColor)
                                            .frame(width: 12, height: 12)
                                        Text(uiCategoryName)
                                            .font(.system(size: 16))
                                            .foregroundColor(primaryTextColor)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(iconColor)
                                    }
                                }
                                
                                // 地点
                                Button(action: {}) {
                                    HStack(spacing: 16) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.system(size: 18))
                                            .foregroundColor(iconColor)
                                            .frame(width: 24)
                                        
                                        Text("地点")
                                            .font(.system(size: 16))
                                            .foregroundColor(primaryTextColor)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14))
                                            .foregroundColor(iconColor)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 20)
                            
                            // 第二条分割线
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            
                            // 备注描述
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 18))
                                    .foregroundColor(iconColor)
                                    .frame(width: 24)
                                
                                TextField("添加备注", text: $editedEvent.description, axis: .vertical)
                                    .font(.system(size: 16))
                                    .foregroundColor(primaryTextColor)
                                    .lineLimit(4...10)
                                    .lineSpacing(6)
                            }
                            .padding(.horizontal, 20)
                            
                            Spacer(minLength: 120)
                        }
                    }
                    
                    // 弹出式 DatePicker
                    if let type = activeDatePicker {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .simultaneousGesture(
                                SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                                    let p = value.location
                                    withAnimation(.spring()) {
                                        if endTimeAreaFrame != .zero, endTimeAreaFrame.contains(p) {
                                            activeDatePicker = .end
                                        } else if startTimeAreaFrame != .zero, startTimeAreaFrame.contains(p) {
                                            activeDatePicker = .start
                                        } else {
                                            activeDatePicker = nil
                                        }
                                    }
                                }
                            )
                        
                        VStack(spacing: 0) {
                            DatePicker(
                                "",
                                selection: type == .start ? $editedEvent.startTime : $editedEvent.endTime,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .glassEffect(in: .rect(cornerRadius: 24))
                        .padding(.horizontal, 20)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                        .zIndex(200)
                    }
                    
                    if showDeleteMenu {
                        Color.black.opacity(0.001)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture { withAnimation { showDeleteMenu = false } }
                    }
                    
                    // 提交中不在页面上额外展示提示（避免“弹窗/胶囊”影响视觉）
                }
            }
            
            // Voice Button
            ZStack {
                Capsule()
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                    .background(Capsule().fill(Color.white))
                    .frame(height: 56)
                    .background(GeometryReader { geo in Color.clear.onAppear { buttonFrame = geo.frame(in: .named("ScheduleDetailSheetSpace")) } })
                
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .foregroundColor(isRecording ? .red : .gray)
                    Text(isRecording ? "正在听..." : "长按可语音编辑")
                        .foregroundColor(Color(hex: "666666"))
                }
            }
            .opacity(isRecording ? 0 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { handleDragChanged($0) }.onEnded { handleDragEnded($0) })
            
            if isRecording || isAnimatingRecordingExit {
                VoiceRecordingOverlay(
                    isRecording: $isRecording,
                    isCanceling: $isCanceling,
                    isExiting: isAnimatingRecordingExit,
                    onExitComplete: {
                        finishRecordingOverlayDismissal()
                    },
                    audioPower: audioPower,
                    transcript: recordingTranscript,
                    inputFrame: buttonFrame,
                    toolboxFrame: .zero
                )
                .zIndex(1000)
            }
        }
        .coordinateSpace(name: "ScheduleDetailSheetSpace")
        .background(bgColor)
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear { speechRecognizer.requestAuthorization() }
        .onAppear {
            // 与数据模型对齐：后端 full_day -> isFullDay
            uiAllDay = editedEvent.isFullDay
        }
        .onReceive(speechRecognizer.$audioLevel) { self.audioPower = mapAudioLevelToPower($0) }
        // 远端详情覆盖 event 时：如果用户还没动过编辑，就同步草稿，避免“看起来没改但其实草稿和最新值不一致”
        .onChange(of: event) { _, newValue in
            guard !isSubmitting else { return }
            guard !hasUserEdited else { return }
            editedEvent = newValue
        }
        // 任何编辑即标记（用于保护草稿不被远端刷新覆盖）
        .onChange(of: editedEvent.title) { _, _ in hasUserEdited = true }
        .onChange(of: editedEvent.description) { _, _ in hasUserEdited = true }
        .onChange(of: editedEvent.startTime) { _, _ in hasUserEdited = true }
        .onChange(of: editedEvent.endTime) { _, _ in hasUserEdited = true }
        .onChange(of: uiAllDay) { _, newValue in
            hasUserEdited = true
            editedEvent.isFullDay = newValue
            guard newValue else { return }
            // 全天：将 start/end 对齐到当天 00:00 ~ 次日 00:00（UI 会展示为 24:00）
            let cal = Calendar.current
            let start = cal.startOfDay(for: editedEvent.startTime)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            editedEvent.startTime = start
            editedEvent.endTime = end
            editedEvent.endTimeProvided = true
        }
        .onChange(of: editedEvent.startTime) { _, newStart in
            if editedEvent.endTime < newStart {
                editedEvent.endTime = newStart
            }
        }
        .onChange(of: editedEvent.endTime) { _, newEnd in
            if newEnd < editedEvent.startTime {
                editedEvent.endTime = editedEvent.startTime
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isPressing {
            isPressing = true
            pressStartTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if isPressing, let s = pressStartTime, Date().timeIntervalSince(s) >= 0.3 {
                    if !isRecording {
                        HapticFeedback.medium()
                        startVoiceInput()
                    }
                }
            }
        }
        if isRecording {
            if value.translation.height < -50 {
                if !isCanceling { withAnimation { isCanceling = true } }
            } else {
                if isCanceling { withAnimation { isCanceling = false } }
            }
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        isPressing = false
        pressStartTime = nil
        if isRecording { stopVoiceInput() }
    }
    
    private func mapAudioLevelToPower(_ level: Float) -> CGFloat {
        let c = max(0, min(level, 1))
        guard c >= silenceGate else { return 0 }
        return CGFloat(pow((c - silenceGate) / max(0.0001, 1 - silenceGate), 0.6))
    }
    
    private func startVoiceInput() {
        isAnimatingRecordingExit = false
        isRecording = true
        isCanceling = false
        recordingTranscript = "正在聆听..."
        speechRecognizer.startRecording { t in
            let tr = t.trimmingCharacters(in: .whitespacesAndNewlines)
            self.recordingTranscript = tr.isEmpty ? "正在聆听..." : tr
        }
    }
    
    private func stopVoiceInput() {
        speechRecognizer.stopRecording()
        if !isCanceling {
            let t = recordingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, t != "正在聆听..." {
                parseVoiceCommand(voiceText: t)
            }
        }
        audioPower = 0
        withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true }
    }
    
    private func finishRecordingOverlayDismissal() {
        isRecording = false
        isAnimatingRecordingExit = false
        isCanceling = false
        audioPower = 0
    }
    
    private func parseVoiceCommand(voiceText: String) {
        Task {
            do {
                let r = try await TodoVoiceParser.parseVoiceCommand(
                    voiceText: voiceText,
                    existingTitle: editedEvent.title,
                    existingDescription: editedEvent.description,
                    existingStartTime: editedEvent.startTime,
                    existingEndTime: editedEvent.endTime,
                    existingReminderTime: editedEvent.startTime.addingTimeInterval(-1800),
                    existingSyncToCalendar: true
                )
                await MainActor.run {
                    if let t = r.title { editedEvent.title = t }
                    if let d = r.taskDescription { editedEvent.description = d }
                    if let s = r.startTime { editedEvent.startTime = s }
                    if let e = r.endTime { editedEvent.endTime = e }
                    HapticFeedback.success()
                }
            } catch {}
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        // ✅ 全天展示语义：00:00 ~ 24:00（endTime 存为次日 00:00）
        if editedEvent.isFullDay {
            // 详情页的 endTime 调用也会走这里：用“是否为次日 00:00”判断显示 24:00
            let cal = Calendar.current
            let start = cal.startOfDay(for: editedEvent.startTime)
            if date == start { return "00:00" }
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            if date == end { return "24:00" }
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
    
    // MARK: - 提交后端
    
    @MainActor
    private func submitSave() async {
        guard !isSubmitting else { return }

        // 未发生任何变更：不触发 loading/网络请求，直接退出即可
        guard editedEvent != event else {
            dismiss()
            return
        }

        isSubmitting = true
        submittingAction = .save
        defer {
            isSubmitting = false
            submittingAction = nil
        }
        
        do {
            var updated = editedEvent
            // 关键：必须有 remoteId 才能 PUT 更新后端。
            func norm(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let rid = norm(updated.remoteId)
            
            // 严格：必须拿到 remoteId 才允许保存，避免出现“只改本地、后端未同步”的链路错乱
            guard !rid.isEmpty else {
                alertMessage = "保存失败：后端未返回日程 id，无法同步到后端。请关闭后重试。"
                return
            }

            let saved = try await ScheduleService.updateSchedule(remoteId: rid, event: updated)
            updated = saved
            editedEvent = saved
            event = updated
            onSave(updated)
            dismiss()
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func submitDelete() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submittingAction = .delete
        defer {
            isSubmitting = false
            submittingAction = nil
        }
        
        do {
            try await DeleteActions.deleteRemoteSchedule(editedEvent)
            onDelete()
            dismiss()
        } catch {
            alertMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Global frame reporter
private struct GlobalFrameReporter: ViewModifier {
    @Binding var frame: CGRect
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        frame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newValue in
                        frame = newValue
                    }
            }
        )
    }
}

struct TopDeletePillButton: View {
    var title: String = "删除日程"
    var onDelete: () -> Void
    var body: some View {
        Button(action: onDelete) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "FF3B30"))
                Text(title)
                    .foregroundColor(Color(hex: "FF3B30"))
                    .font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .frame(width: 200, height: 52)
            .modifier(ConditionalCapsuleBackground(showRescanMenu: false))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
