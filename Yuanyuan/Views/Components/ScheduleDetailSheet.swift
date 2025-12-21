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

    // MARK: - 仅用于 UI 复刻（不写回 ScheduleEvent，避免与数据模型冲突）
    @State private var uiAllDay: Bool = false
    @State private var uiReminderText: String = "开始前 30 分钟"
    @State private var uiCategoryName: String = "商务宴请"
    @State private var uiCategoryColor: Color = Color(hex: "FF8A00")
    
    enum DatePickerType {
        case start, end
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
                                .foregroundColor(Color(hex: "999999"))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.secondary.opacity(0.15)))
                        }
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showDeleteMenu = true
                                }
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color(hex: "333333"))
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                            
                            Button(action: {
                                onSave(editedEvent)
                                dismiss()
                            }) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color(hex: "333333"))
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                        }
                    }
                    
                    Text("日程详情")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "333333"))

                    if showDeleteMenu {
                        TopDeletePillButton(
                            onDelete: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showDeleteMenu = false
                                }
                                HapticFeedback.medium()
                                onDelete()
                                dismiss()
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
                .overlay(alignment: .trailing) {
                    if showDeleteMenu {
                        TopDeletePillButton(
                            onDelete: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showDeleteMenu = false
                                }
                                HapticFeedback.medium()
                                onDelete()
                                dismiss()
                            }
                        )
                        .padding(.trailing, 20 + 44 + 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .zIndex(100)
                
                ZStack {
                    ScrollView {
                        VStack(spacing: 18) {
                            // Title（居中大标题 + 右侧冲突标签）
                            ZStack {
                                TextField("日程标题", text: $editedEvent.title)
                                    .font(.system(size: 34, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(Color(hex: "333333"))
                                    .lineLimit(1)
                                    .padding(.horizontal, 64) // 给右侧标签留空间
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
                            
                            // Time Display
                            HStack(alignment: .center, spacing: 0) {
                                // Start Date/Time
                                Button(action: {
                                    withAnimation(.spring()) { activeDatePicker = .start }
                                }) {
                                    VStack(alignment: .center, spacing: 4) {
                                        Text(formatDate(editedEvent.startTime))
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundColor(activeDatePicker == .start ? .blue : Color(hex: "999999"))
                                        
                                        Text(formatTime(editedEvent.startTime))
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(activeDatePicker == .start ? .blue : Color(hex: "333333"))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .modifier(GlobalFrameReporter(frame: $startTimeAreaFrame))
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundColor(Color(hex: "E0E0E0"))
                                    .offset(y: 12)
                                
                                // End Date/Time
                                Button(action: {
                                    withAnimation(.spring()) { activeDatePicker = .end }
                                }) {
                                    VStack(alignment: .center, spacing: 4) {
                                        Text(formatDate(editedEvent.endTime))
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundColor(activeDatePicker == .end ? .blue : Color(hex: "999999"))
                                        
                                        Text(formatTime(editedEvent.endTime))
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(activeDatePicker == .end ? .blue : Color(hex: "333333"))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .modifier(GlobalFrameReporter(frame: $endTimeAreaFrame))
                            }
                            .padding(.top, 2)
                            .padding(.horizontal, 20)
                            
                            Divider().padding(.horizontal, 20)
                            
                            // Options
                            VStack(spacing: 0) {
                                settingsRow(
                                    icon: "sun.max",
                                    title: "全天",
                                    trailing: AnyView(
                                        Toggle("", isOn: $uiAllDay)
                                            .labelsHidden()
                                            .tint(Color(hex: "CFCFCF"))
                                    )
                                )
                                
                                rowDivider
                                
                                settingsRow(
                                    icon: "bell",
                                    title: "提醒时间",
                                    trailing: AnyView(
                                        HStack(spacing: 6) {
                                            Text(uiReminderText)
                                                .foregroundColor(Color(hex: "999999"))
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(Color(hex: "CCCCCC"))
                                        }
                                    )
                                )
                                
                                rowDivider
                                
                                settingsRow(
                                    icon: "calendar",
                                    title: "日程分类",
                                    trailing: AnyView(
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(uiCategoryColor)
                                                .frame(width: 12, height: 12)
                                            Text(uiCategoryName)
                                                .foregroundColor(Color(hex: "333333"))
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(Color(hex: "CCCCCC"))
                                        }
                                    )
                                )
                                
                                rowDivider
                                
                                Button(action: {}) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundColor(Color(hex: "CCCCCC"))
                                            .frame(width: 24)
                                        Text("地点")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(hex: "333333"))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "CCCCCC"))
                                    }
                                    .frame(height: 56)
                                    .contentShape(Rectangle())
                                }
                                
                                rowDivider
                                
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(Color(hex: "CCCCCC"))
                                        .frame(width: 24)
                                    
                                    TextField("添加备注", text: $editedEvent.description, axis: .vertical)
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: "333333"))
                                        .lineLimit(4...10)
                                }
                                .padding(.vertical, 16)
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 120)
                    }
                    
                    // 弹出式 DatePicker
                    if let type = activeDatePicker {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            // 逻辑：当开始/结束日历打开时，点击另一侧时间区域应直接切换，不要先关闭
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
                            // 竖向留白收紧：避免月日历弹层显得“太长”
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
                }
            }
            
            // Voice Button
            ZStack {
                Capsule().stroke(Color(hex: "E5E5E5"), lineWidth: 1).background(Capsule().fill(Color.white)).frame(height: 56)
                    .background(GeometryReader { geo in Color.clear.onAppear { buttonFrame = geo.frame(in: .named("ScheduleDetailSheetSpace")) } })
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "mic.fill" : "mic").foregroundColor(isRecording ? .red : .gray)
                    Text(isRecording ? "正在听..." : "长按可语音编辑").foregroundColor(Color(hex: "666666"))
                }
            }
            .opacity(isRecording ? 0 : 1)
            .padding(.horizontal, 20).padding(.bottom, 20)
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { handleDragChanged($0) }.onEnded { handleDragEnded($0) })
            
            if isRecording {
                VoiceRecordingOverlay(
                    isRecording: $isRecording,
                    isCanceling: $isCanceling,
                    audioPower: audioPower,
                    transcript: recordingTranscript,
                    inputFrame: buttonFrame,
                    toolboxFrame: .zero
                )
                .zIndex(1000)
            }
        }
        .coordinateSpace(name: "ScheduleDetailSheetSpace")
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        .onAppear { speechRecognizer.requestAuthorization() }
        .onReceive(speechRecognizer.$audioLevel) { self.audioPower = mapAudioLevelToPower($0) }
        // 逻辑校验：结束时间不能早于开始时间（仅改逻辑，不改 UI）
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

    private var rowDivider: some View {
        Divider().padding(.leading, 36)
    }
    
    @ViewBuilder
    private func settingsRow(icon: String, title: String, trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "CCCCCC"))
                .frame(width: 24)
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "333333"))
            Spacer()
            trailing
        }
        .frame(height: 56)
        .contentShape(Rectangle())
    }
    
    // Logic Methods ... (Same as before)
    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isPressing { isPressing = true; pressStartTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if isPressing, let s = pressStartTime, Date().timeIntervalSince(s) >= 0.3 { if !isRecording { HapticFeedback.medium(); startVoiceInput() } } }
        }
        if isRecording { if value.translation.height < -50 { if !isCanceling { withAnimation { isCanceling = true } } } else { if isCanceling { withAnimation { isCanceling = false } } } }
    }
    private func handleDragEnded(_ value: DragGesture.Value) { isPressing = false; pressStartTime = nil; if isRecording { stopVoiceInput() } }
    private func mapAudioLevelToPower(_ level: Float) -> CGFloat { let c = max(0, min(level, 1)); guard c >= silenceGate else { return 0 }; return CGFloat(pow((c - silenceGate) / max(0.0001, 1 - silenceGate), 0.6)) }
    private func startVoiceInput() { isAnimatingRecordingExit = false; isRecording = true; isCanceling = false; recordingTranscript = "正在聆听..."; speechRecognizer.startRecording { t in let tr = t.trimmingCharacters(in: .whitespacesAndNewlines); self.recordingTranscript = tr.isEmpty ? "正在聆听..." : tr } }
    private func stopVoiceInput() { speechRecognizer.stopRecording(); if !isCanceling { let t = recordingTranscript.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty, t != "正在聆听..." { parseVoiceCommand(voiceText: t) } }; audioPower = 0; withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true } }
    private func finishRecordingOverlayDismissal() { isRecording = false; isAnimatingRecordingExit = false; isCanceling = false; audioPower = 0 }
    private func parseVoiceCommand(voiceText: String) { Task { do { let r = try await TodoVoiceParser.parseVoiceCommand(voiceText: voiceText, existingTitle: editedEvent.title, existingDescription: editedEvent.description, existingStartTime: editedEvent.startTime, existingEndTime: editedEvent.endTime, existingReminderTime: editedEvent.startTime.addingTimeInterval(-1800), existingSyncToCalendar: true); await MainActor.run { if let t = r.title { editedEvent.title = t }; if let d = r.taskDescription { editedEvent.description = d }; if let s = r.startTime { editedEvent.startTime = s }; if let e = r.endTime { editedEvent.endTime = e }; HapticFeedback.success() } } catch {} } }
    private func formatDate(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd"; return f.string(from: date) }
    private func formatTime(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date) }
}

// MARK: - Global frame reporter (逻辑用，不影响 UI)
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
    var onDelete: () -> Void
    var body: some View {
        Button(action: onDelete) {
            HStack(spacing: 8) {
                Image(systemName: "trash").font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: "FF3B30"))
                Text("删除日程").foregroundColor(Color(hex: "FF3B30")).font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.leading, 20).padding(.trailing, 16).frame(width: 200, height: 52)
            .modifier(ConditionalCapsuleBackground(showRescanMenu: false))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}
