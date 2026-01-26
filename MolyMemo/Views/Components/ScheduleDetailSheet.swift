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

    // MARK: - 日程字段（与后端一致：reminder_time / category）
    @State private var uiAllDay: Bool = false
    @State private var showReminderMenu: Bool = false
    @State private var showCategoryMenu: Bool = false
    @State private var reminderRowFrame: CGRect = .zero
    @State private var categoryRowFrame: CGRect = .zero
    @State private var deleteMenuAnchorFrame: CGRect = .zero
    
    // 自定义提醒时间
    @State private var customReminderDate: Date = Date()
    private let customReminderSentinelValue: String = "__custom_reminder__"
    
    // 行内编辑（标题/地点/备注）
    private enum FocusField: Hashable { case title, location, description }
    @FocusState private var focusedField: FocusField?

    // MARK: - Debug logging (focus/keyboard)
    private func dbg(_ msg: String) {
#if DEBUG || targetEnvironment(simulator)
        let ts = String(format: "%.3f", Date().timeIntervalSince1970)
        print("🟦[ScheduleDetailSheet][\(ts)] \(msg)")
#endif
    }
    
    private struct ReminderOption: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let value: String // 后端 reminder_time
    }
    
    private struct CategoryOption: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let value: String // 后端 category
    }
    
    private let baseReminderOptions: [ReminderOption] = [
        .init(title: "开始前 5 分钟", value: "-5m"),
        .init(title: "开始前 10 分钟", value: "-10m"),
        .init(title: "开始前 15 分钟", value: "-15m"),
        .init(title: "开始前 30 分钟", value: "-30m"),
        .init(title: "开始前 1 小时", value: "-1h"),
        .init(title: "开始前 2 小时", value: "-2h"),
        .init(title: "开始前 1 天", value: "-1d"),
        .init(title: "开始前 2 天", value: "-2d"),
        .init(title: "开始前 1 周", value: "-1w"),
        .init(title: "开始前 2 周", value: "-2w")
    ]
    
    private let categoryOptions: [CategoryOption] = [
        .init(title: "会议", value: "meeting"),
        .init(title: "拜访", value: "client_visit"),
        .init(title: "行程", value: "travel"),
        .init(title: "聚餐", value: "business_meal"),
        .init(title: "个人事件", value: "personal"),
        .init(title: "其他", value: "other")
    ]
    
    enum DatePickerType {
        case start, end, reminder
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
    @StateObject private var pcmRecorder = HoldToTalkPCMRecorder()
    @State private var isRecording = false
    @State private var isCapturingAudio = false
    @State private var isAnimatingRecordingExit = false
    @State private var isCanceling = false
    @State private var audioPower: CGFloat = 0.0
    @State private var recordingTranscript: String = ""
    /// 缓存服务端推送的 asr_result（即便 UI 不展示，也需要在松手时回传后端做兜底解析）
    @State private var lastASRText: String = ""
    @State private var lastFinalASRText: String = ""
    @State private var isBlueArcExiting: Bool = false
    @State private var buttonFrame: CGRect = .zero
    @State private var isPressing = false
    @State private var pressStartTime: Date?
    @State private var voiceSession: ScheduleVoiceUpdateService.Session? = nil
    @State private var voiceSendTask: Task<Void, Never>? = nil
    @State private var voiceReceiveTask: Task<Void, Never>? = nil
    @State private var voiceDoneTimeoutTask: Task<Void, Never>? = nil
    @State private var didSendAudioRecordDone: Bool = false

    // 键盘状态：用于避免“语音编辑”按钮在编辑备注时被键盘顶上来
    @State private var isKeyboardVisible: Bool = false
    
    private let silenceGate: Float = 0.12
    
    // 颜色定义
    private let bgColor = Color(red: 0.97, green: 0.97, blue: 0.97)
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    private let iconColor = Color(hex: "CCCCCC")

    private func dismissKeyboard() {
        dbg("dismissKeyboard() called. focusedField(before)=\(String(describing: focusedField))")
        focusedField = nil
        // 兜底：即便某些场景没走 FocusState，也强制收起键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        dbg("dismissKeyboard() done. focusedField(after)=\(String(describing: focusedField))")
    }

    private var locationTextBinding: Binding<String> {
        Binding(
            get: { editedEvent.location ?? "" },
            set: { newValue in
                hasUserEdited = true
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                editedEvent.location = trimmed.isEmpty ? nil : newValue
            }
        )
    }
    
    init(event: Binding<ScheduleEvent>, onDelete: @escaping () -> Void, onSave: @escaping (ScheduleEvent) -> Void) {
        self._event = event
        self.onDelete = onDelete
        self.onSave = onSave
        self._editedEvent = State(initialValue: event.wrappedValue)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            bgColor.ignoresSafeArea()
            
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
                                dismissKeyboard()
                                HapticFeedback.light()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    activeDatePicker = nil
                                    showReminderMenu = false
                                    showCategoryMenu = false
                                    showDeleteMenu.toggle()
                                }
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                            .disabled(isSubmitting)
                            .modifier(GlobalFrameReporter(frame: $deleteMenuAnchorFrame))
                            .opacity(showDeleteMenu ? 0 : 1)
                            .allowsHitTesting(!showDeleteMenu)
                            
                            Button(action: {
                                dismissKeyboard()
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
                        .onTapGesture { dismissKeyboard() }
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
                                    .focused($focusedField, equals: .title)
                                    .submitLabel(.done)
                                    .onSubmit { dismissKeyboard() }
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
                                    dismissKeyboard()
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
                                    dismissKeyboard()
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
                                .contentShape(Rectangle())
                                .onTapGesture { dismissKeyboard() }
                                
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
                                    
                                    Button(action: {
                                        dismissKeyboard()
                                        HapticFeedback.light()
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                            showCategoryMenu = false
                                            showReminderMenu.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Text(reminderDisplayText(editedEvent.reminderTime))
                                                .font(.system(size: 16))
                                                .foregroundColor(secondaryTextColor)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(iconColor)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { dismissKeyboard() }
                                .modifier(GlobalFrameReporter(frame: $reminderRowFrame))
                                
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
                                    
                                    Button(action: {
                                        dismissKeyboard()
                                        HapticFeedback.light()
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                            showReminderMenu = false
                                            showCategoryMenu.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 10) {
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(categoryDisplayColor(editedEvent.category))
                                                .frame(width: 12, height: 12)
                                            Text(categoryDisplayText(editedEvent.category))
                                                .font(.system(size: 16))
                                                .foregroundColor(primaryTextColor)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(iconColor)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { dismissKeyboard() }
                                .modifier(GlobalFrameReporter(frame: $categoryRowFrame))
                                
                                // 地点（接入后端 location）
                                HStack(spacing: 16) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 18))
                                        .foregroundColor(iconColor)
                                        .frame(width: 24)
                                    
                                    Text("地点")
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                    
                                    Spacer()
                                    
                                    TextField(
                                        "",
                                        text: locationTextBinding,
                                        prompt: Text("无地点").foregroundColor(secondaryTextColor)
                                    )
                                    .font(.system(size: 16))
                                    .foregroundColor(primaryTextColor)
                                    .multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .location)
                                    .submitLabel(.done)
                                    .onSubmit { dismissKeyboard() }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { dismissKeyboard() }
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
                                
                                // ✅ 关键修复：
                                // FocusState 只有在“对应 .focused(...) 的输入控件已在视图树中存在”时，程序性设焦点才会生效。
                                // 之前这里是「focusedField == .description 才创建 TextField」，导致你点击时 TextField 还不存在，
                                // SwiftUI 会直接丢弃 focusedField 的赋值（你日志里就是 set 后仍为 nil）。
                                // 现在改成：TextField 始终存在，用 overlay 展示 placeholder / LinkifiedText。
                                ZStack(alignment: .topLeading) {
                                    TextField("添加备注", text: $editedEvent.description, axis: .vertical)
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                        .lineLimit(4...10)
                                        .lineSpacing(6)
                                        .focused($focusedField, equals: .description)
                                        // 多行 TextField 默认回车是“换行”，这里改成“完成并收起键盘”
                                        .onChange(of: editedEvent.description) { _, newValue in
                                            guard newValue.contains("\n") else { return }
                                            let sanitized = newValue
                                                .replacingOccurrences(of: "\n", with: " ")
                                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                            if editedEvent.description != sanitized {
                                                editedEvent.description = sanitized
                                            }
                                            dismissKeyboard()
                                        }
                                        // 未聚焦时隐藏真实输入（由 overlay 展示更美观的文本/链接）
                                        .opacity(focusedField == .description ? 1 : 0.01)

                                    if focusedField != .description {
                                        let trimmed = editedEvent.description.trimmingCharacters(in: .whitespacesAndNewlines)
                                        Group {
                                            if trimmed.isEmpty {
                                                Text("添加备注")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(secondaryTextColor)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            } else {
                                                LinkifiedText(
                                                    text: editedEvent.description,
                                                    font: .system(size: 16),
                                                    textColor: primaryTextColor,
                                                    linkColor: .blue,
                                                    lineSpacing: 6,
                                                    lineLimit: 10
                                                )
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            dbg("notes overlay tapped. focusedField(before)=\(String(describing: focusedField))")
                                            focusedField = .description
                                            dbg("notes overlay set focus -> .description. focusedField(now)=\(String(describing: focusedField))")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            Spacer(minLength: 120)
                        }
                    }
                    // ✅ 说明：
                    // 这里如果把“点击收起键盘”的手势挂在内容容器上，会与“备注（未编辑态）点击 -> 程序性聚焦”打架，
                    // 导致备注刚 focus 就被同一次点击清掉，从而无法弹出键盘。
                    // 所以不在内容容器上全局监听点击；仅在确有需要的控件上显式 dismissKeyboard()。
                    
                    // 弹出式 DatePicker
                    if let type = activeDatePicker {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .simultaneousGesture(
                                SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                                    dismissKeyboard()
                                    let p = value.location
                                    withAnimation(.spring()) {
                                        // 只有在“开始/结束时间”日历态下，才支持点击开始/结束区域切换
                                        if type == .reminder {
                                            activeDatePicker = nil
                                            return
                                        }
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
                            Group {
                                switch type {
                                case .start:
                                    DatePicker("", selection: $editedEvent.startTime, displayedComponents: [.date, .hourAndMinute])
                                case .end:
                                    DatePicker("", selection: $editedEvent.endTime, displayedComponents: [.date, .hourAndMinute])
                                case .reminder:
                                    DatePicker("", selection: $customReminderDate, displayedComponents: [.date, .hourAndMinute])
                                }
                            }
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .yy_glassEffectCompat(cornerRadius: 24)
                        .padding(.horizontal, 20)
                        // 视觉微调：日历弹层与上方时间区域拉开一点距离，避免“挨得太紧”
                        .offset(y: 12)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                        .zIndex(200)
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
                    Text(isRecording ? (isCapturingAudio ? "正在听..." : "正在分析...") : "长按可语音编辑")
                        .foregroundColor(Color(hex: "666666"))
                }
            }
            .opacity((isRecording || isKeyboardVisible) ? 0 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            // 关键：键盘弹出时不要因为 safe area 改变而把按钮抬到键盘上方
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // 键盘出现时避免误触（即便在某些场景下仍可点到）
            .allowsHitTesting(!isKeyboardVisible && !isSubmitting)
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { handleDragChanged($0) }.onEnded { handleDragEnded($0) })
            
            if isRecording || isAnimatingRecordingExit {
                VoiceRecordingOverlay(
                    isRecording: $isRecording,
                    isCanceling: $isCanceling,
                    isExiting: isAnimatingRecordingExit,
                    isBlueArcExiting: isBlueArcExiting,
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
        .overlay { menusOverlay }
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
        .onAppear {
            dbg("onAppear. initial focusedField=\(String(describing: focusedField))")
            // 与数据模型对齐：后端 full_day -> isFullDay
            uiAllDay = editedEvent.isFullDay
        }
        .onChange(of: focusedField) { _, newValue in
            dbg("focusedField changed -> \(String(describing: newValue))")
        }
        .onChange(of: customReminderDate) { _, newValue in
            guard activeDatePicker == .reminder else { return }
            hasUserEdited = true
            editedEvent.reminderTime = ScheduleService.localDateTimeStringNoTimeZone(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
            dbg("keyboardWillShow. focusedField=\(String(describing: focusedField))")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
            dbg("keyboardWillHide. focusedField=\(String(describing: focusedField))")
        }
        .onReceive(pcmRecorder.$audioLevel) { self.audioPower = mapAudioLevelToPower($0) }
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
            // 全天：将 start/end 对齐到当天 00:00 ~ 23:59
            let cal = Calendar.current
            let start = cal.startOfDay(for: editedEvent.startTime)
            // 设为当天的 23:59:59
            var components = DateComponents()
            components.hour = 23
            components.minute = 59
            components.second = 59
            let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: start) ?? start.addingTimeInterval(86399)
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
        isCapturingAudio = true
        isCanceling = false
        isBlueArcExiting = false
        recordingTranscript = "正在连接..."
        lastASRText = ""
        lastFinalASRText = ""
        didSendAudioRecordDone = false
        voiceDoneTimeoutTask?.cancel()
        voiceDoneTimeoutTask = nil

        // 清理旧任务/连接
        voiceSendTask?.cancel()
        voiceSendTask = nil
        voiceReceiveTask?.cancel()
        voiceReceiveTask = nil
        Task { await voiceSession?.close() }
        voiceSession = nil

        Task {
            do {
                try await pcmRecorder.start()

                let rid = (editedEvent.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rid.isEmpty else {
                    await MainActor.run {
                        alertMessage = "语音编辑失败：后端未返回日程 id，无法进行语音更新。"
                        stopVoiceAndDismissOverlayImmediately()
                    }
                    return
                }

                let session = try ScheduleVoiceUpdateService.makeSession(scheduleId: rid, keepLocalId: editedEvent.id)
                session.start()
                await MainActor.run {
                    self.voiceSession = session
                    self.recordingTranscript = "正在聆听..."
                }

                try await session.sendWavHeaderOnce()
                startVoiceStreamingTasks(session: session)
            } catch {
                await MainActor.run {
                    alertMessage = "语音启动失败：\(error.localizedDescription)"
                    stopVoiceAndDismissOverlayImmediately()
                }
            }
        }
    }
    
    private func stopVoiceInput() {
        isCapturingAudio = false

        // 停止录音，并拿到最后一段 PCM
        let finalPCM = pcmRecorder.stop(discard: isCanceling)

        // 停止“拉取 PCM”任务（接下来只做收尾/等待后端处理）
        voiceSendTask?.cancel()
        voiceSendTask = nil

        let session = voiceSession

        if isCanceling {
            recordingTranscript = "已取消"
            Task {
                do {
                    try await session?.sendCancel()
                } catch {}
                await session?.close()
                await MainActor.run {
                    stopVoiceAndDismissOverlayImmediately()
                }
            }
            return
        }

        // 正常结束：补发尾巴 PCM + done，然后等待 update_result 再退场
        recordingTranscript = "正在分析语音内容..."
        withAnimation(.easeInOut(duration: 0.22)) { isBlueArcExiting = true }

        if let session {
            didSendAudioRecordDone = true
            let asrTextToSend = (lastFinalASRText.isEmpty ? lastASRText : lastFinalASRText).trimmingCharacters(in: .whitespacesAndNewlines)
            let asrIsFinalToSend: Bool? = lastFinalASRText.isEmpty ? nil : true
            Task.detached(priority: .userInitiated) {
                do {
                    if !finalPCM.isEmpty {
                        try await session.sendPCMChunk(finalPCM)
                    }
                    try await session.sendAudioRecordDone(
                        asrText: asrTextToSend.isEmpty ? nil : asrTextToSend,
                        isFinal: asrIsFinalToSend
                    )
                } catch {
                    // 发送失败：让 receive loop/timeout 收口
                }
            }
        } else {
            // 没连上：直接退出，避免卡住
            withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true }
        }

        // 兜底超时：避免后端无响应导致 overlay 永不退出
        voiceDoneTimeoutTask?.cancel()
        voiceDoneTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000_000)
            if isRecording || isAnimatingRecordingExit {
                alertMessage = "语音更新超时，请稍后重试。"
                stopVoiceAndDismissOverlayImmediately()
            }
        }
    }
    
    private func finishRecordingOverlayDismissal() {
        isRecording = false
        isAnimatingRecordingExit = false
        isCanceling = false
        isCapturingAudio = false
        audioPower = 0
        isBlueArcExiting = false

        didSendAudioRecordDone = false

        voiceDoneTimeoutTask?.cancel()
        voiceDoneTimeoutTask = nil

        voiceSendTask?.cancel()
        voiceSendTask = nil
        voiceReceiveTask?.cancel()
        voiceReceiveTask = nil
        Task { await voiceSession?.close() }
        voiceSession = nil
    }

    private func stopVoiceAndDismissOverlayImmediately() {
        _ = pcmRecorder.stop(discard: true)
        isCapturingAudio = false

        voiceSendTask?.cancel()
        voiceSendTask = nil
        voiceReceiveTask?.cancel()
        voiceReceiveTask = nil
        voiceDoneTimeoutTask?.cancel()
        voiceDoneTimeoutTask = nil

        Task { await voiceSession?.close() }
        voiceSession = nil

        audioPower = 0
        withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true }
    }

    private func startVoiceStreamingTasks(session: ScheduleVoiceUpdateService.Session) {
        // 1) 发送循环：定时 drain PCM，并发送到 WS
        voiceSendTask?.cancel()
        voiceSendTask = Task.detached(priority: .userInitiated) { [pcmRecorder] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
                let chunk = pcmRecorder.drainPCMBytes()
                if chunk.isEmpty { continue }
                do {
                    try await session.sendPCMChunk(chunk)
                } catch {
                    // 发送失败：等待 receive loop/timeout 收口
                }
            }
        }

        // 2) 接收循环：实时更新 transcript；收到 update_result 才应用并退场
        voiceReceiveTask?.cancel()
        voiceReceiveTask = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                do {
                    let ev = try await session.receiveEvent()
                    await MainActor.run {
                        handleVoiceUpdateEvent(ev)
                    }
                    switch ev {
                    case .updateResult, .cancelled, .error:
                        await session.close()
                        return
                    case .asrResult, .processing:
                        break
                    }
                } catch {
                    await MainActor.run {
                        alertMessage = "语音更新失败：\(error.localizedDescription)"
                        stopVoiceAndDismissOverlayImmediately()
                    }
                    await session.close()
                    return
                }
            }
            await session.close()
        }
    }

    @MainActor
    private func handleVoiceUpdateEvent(_ ev: ScheduleVoiceUpdateService.Event) {
        switch ev {
        case let .asrResult(text, isFinal):
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                lastASRText = t
                if isFinal { lastFinalASRText = t }
            }
            // 需求：日程详情“长按语音编辑”时，音浪下方不展示实时转写，始终保持“正在聆听…”
            recordingTranscript = isCapturingAudio ? "正在聆听..." : "正在分析语音内容..."
        case let .processing(message):
            let m = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            recordingTranscript = m.isEmpty ? "正在分析语音内容..." : m
        case let .updateResult(event: updated, message: msg):
            editedEvent = updated
            event = updated
            onSave(updated)
            hasUserEdited = true

            if let m = msg?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
                recordingTranscript = m
            } else {
                recordingTranscript = "已更新"
            }
            HapticFeedback.success()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true }
            }
        case let .cancelled(message: msg):
            let m = (msg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            recordingTranscript = m.isEmpty ? "已取消" : m
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true }
            }
        case let .error(code: _, message: msg):
            alertMessage = "语音更新失败：\(msg)"
            stopVoiceAndDismissOverlayImmediately()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        // ✅ 全天展示语义：00:00 ~ 23:59
        if editedEvent.isFullDay {
            let cal = Calendar.current
            let start = cal.startOfDay(for: editedEvent.startTime)
            if cal.isDate(date, inSameDayAs: start) {
                let hour = cal.component(.hour, from: date)
                let minute = cal.component(.minute, from: date)
                if hour == 0 && minute == 0 { return "00:00" }
                if hour == 23 && minute == 59 { return "23:59" }
            }
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func reminderDisplayText(_ value: String?) -> String {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch v {
        case "-5m": return "开始前 5 分钟"
        case "-10m": return "开始前 10 分钟"
        case "-15m": return "开始前 15 分钟"
        case "-30m": return "开始前 30 分钟"
        case "-1h": return "开始前 1 小时"
        case "-2h": return "开始前 2 小时"
        case "-1d": return "开始前 1 天"
        case "-2d": return "开始前 2 天"
        case "-1w": return "开始前 1 周"
        case "-2w": return "开始前 2 周"
        default:
            if let abs = ScheduleReminderTime.parseAbsoluteDate(v) {
                return customReminderRowDisplayText(date: abs)
            }
            if let offset = ScheduleReminderTime.parseRelativeOffsetSeconds(v), offset != 0 {
                return relativeReminderDisplayText(offsetSeconds: offset)
            }
            return "开始前 30 分钟"
        }
    }

    // MARK: - 自定义提醒：菜单/展示

    private var menusOverlay: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if showReminderMenu || showCategoryMenu || showDeleteMenu {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showReminderMenu = false
                                showCategoryMenu = false
                                showDeleteMenu = false
                            }
                        }
                }
                
                if showReminderMenu {
                    SingleSelectOptionMenu(
                        title: "提醒时间类型",
                        options: reminderMenuOptions(for: editedEvent).map { .init(title: $0.title, value: $0.value) },
                        selectedValue: editedEvent.reminderTime,
                        onSelect: { v in
                            if v == customReminderSentinelValue {
                                hasUserEdited = true
                                customReminderDate = suggestedCustomReminderDate(for: editedEvent)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showReminderMenu = false }
                                // 关闭菜单动画结束后再弹出，避免层级/手势冲突
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    activeDatePicker = .reminder
                                }
                            } else {
                                hasUserEdited = true
                                editedEvent.reminderTime = v
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showReminderMenu = false }
                            }
                        }
                    )
                    .frame(width: 220)
                    .offset(
                        PopupMenuPositioning.coveringRowOffset(
                            for: reminderRowFrame,
                            in: geo.frame(in: .global),
                            menuWidth: 220,
                            menuHeight: SingleSelectOptionMenu.maxHeight(optionCount: reminderMenuOptions(for: editedEvent).count)
                        )
                    )
                    .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity), removal: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity)))
                }
                
                if showCategoryMenu {
                    SingleSelectOptionMenu(
                        title: "日程分类",
                        options: categoryOptions.map { .init(title: $0.title, value: $0.value) },
                        selectedValue: editedEvent.category,
                        onSelect: { v in
                            hasUserEdited = true
                            editedEvent.category = v
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showCategoryMenu = false }
                        }
                    )
                    .frame(width: 220)
                    .offset(
                        PopupMenuPositioning.coveringRowOffset(
                            for: categoryRowFrame,
                            in: geo.frame(in: .global),
                            menuWidth: 220,
                            menuHeight: SingleSelectOptionMenu.maxHeight(optionCount: categoryOptions.count)
                        )
                    )
                    .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity), removal: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity)))
                }
                
                if showDeleteMenu {
                    TopDeletePillButton(
                        onDelete: {
                            dismissKeyboard()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showDeleteMenu = false }
                            HapticFeedback.medium()
                            Task { await submitDelete() }
                        }
                    )
                    .frame(width: 200)
                    .offset(PopupMenuPositioning.rightAlignedCenterOffset(for: deleteMenuAnchorFrame, in: geo.frame(in: .global), width: 200, height: 52))
                    .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity), removal: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity)))
                    .zIndex(30)
                }
            }
        }
    }

    private func reminderMenuOptions(for ev: ScheduleEvent) -> [ReminderOption] {
        // 需求：自定义放到第一个选项
        var opts: [ReminderOption] = [
            .init(title: "自定义…", value: customReminderSentinelValue)
        ]
        let raw = (ev.reminderTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, let abs = ScheduleReminderTime.parseAbsoluteDate(raw) {
            // 若当前就是自定义时间：在菜单里展示具体日期（用于勾选/可见性）
            opts.append(.init(title: customReminderMenuDisplayText(date: abs), value: raw))
        }
        opts.append(contentsOf: baseReminderOptions)
        return opts
    }

    private func suggestedCustomReminderDate(for ev: ScheduleEvent) -> Date {
        let raw = (ev.reminderTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, let d = ScheduleReminderTime.resolveReminderDate(startTime: ev.startTime, reminderTimeRaw: raw) {
            return d
        }
        return ev.startTime
    }

    private func customReminderRowDisplayText(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        // 需求：显示为 “yyyy/MM/dd 12:30” 这种形式
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: date)
    }

    private func customReminderMenuDisplayText(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        // 需求：下拉选项里也显示为 “yyyy/MM/dd 12:30” 这种形式
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: date)
    }

    private func relativeReminderDisplayText(offsetSeconds: TimeInterval) -> String {
        // offsetSeconds < 0 表示“开始前”
        let absSeconds = abs(offsetSeconds)
        let isBefore = offsetSeconds < 0

        let minutes = Int((absSeconds / 60).rounded())
        if minutes == 0 { return isBefore ? "开始时" : "开始后" }

        func fmt(_ n: Int, _ unit: String) -> String {
            isBefore ? "开始前 \(n) \(unit)" : "开始后 \(n) \(unit)"
        }

        if minutes % (60 * 24 * 7) == 0 { return fmt(minutes / (60 * 24 * 7), "周") }
        if minutes % (60 * 24) == 0 { return fmt(minutes / (60 * 24), "天") }
        if minutes % 60 == 0 { return fmt(minutes / 60, "小时") }
        return fmt(minutes, "分钟")
    }
    
    private func categoryDisplayText(_ value: String?) -> String {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch v {
        case "meeting": return "会议"
        case "client_visit": return "拜访"
        case "travel": return "行程"
        case "business_meal": return "商务宴请"
        case "personal": return "个人事件"
        case "other": return "其他"
        default: return "商务宴请"
        }
    }
    
    private func categoryDisplayColor(_ value: String?) -> Color {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch v {
        case "meeting": return Color(hex: "3B82F6")
        case "client_visit": return Color(hex: "8B5CF6")
        case "travel": return Color(hex: "10B981")
        case "business_meal": return Color(hex: "FF8A00")
        case "personal": return Color(hex: "EC4899")
        case "other": return Color(hex: "9CA3AF")
        default: return Color(hex: "FF8A00")
        }
    }
    
    // PopupMenuPositioning.menuOffset 见 SharedComponents（与“联系人-性别”共用）
    
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

// SingleSelectOptionMenu / GlobalFrameReporter 见 SharedComponents

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

// CustomReminderPickerSheet 已移除：自定义提醒已沿用页内日历弹层（与开始/结束时间一致）。
