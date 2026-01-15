import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Bindable var contact: Contact
    
    @State private var showDeleteMenu = false
    @State private var isLoadingDetail: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submittingAction: SubmittingAction? = nil
    @State private var alertMessage: String? = nil
    /// 严格遵从：remoteId 存在时，必须等后端详情至少应用一次，避免 UI 以本地空值/默认值兜底。
    @State private var didApplyRemoteDetailOnce: Bool = false
    
    // 与「日程详情」一致：用 edited 草稿承载编辑态，✅ 提交保存后再写回 contact
    @State private var editedName: String = ""
    @State private var editedCompany: String = ""
    @State private var editedIdentity: String = ""
    @State private var editedPhone: String = ""
    @State private var editedEmail: String = ""
    @State private var editedIndustry: String = ""
    @State private var editedLocation: String = ""
    @State private var editedBirthday: String = ""
    @State private var editedBirthdayDate: Date? = nil
    @State private var showBirthdayPickerSheet: Bool = false
    @State private var birthdayPickerDate: Date = Date()
    /// 后端约定：male / female / other（空字符串表示未设置）
    @State private var editedGender: String = ""
    @State private var editedNotes: String = ""
    @State private var didInitDraft: Bool = false
    @State private var hasUserEdited: Bool = false
    
    // 下拉菜单：性别（样式对齐“日程详情-提醒时间”）
    @State private var showGenderMenu: Bool = false
    @State private var genderRowFrame: CGRect = .zero
    @State private var deleteMenuAnchorFrame: CGRect = .zero

    private var hasDraftChanges: Bool {
        // 统一：trim + 空字符串当作 nil，避免 “nil vs 空字符串” 导致误判
        func norm(_ s: String?) -> String? {
            let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        return norm(editedName) != norm(contact.name)
            || norm(editedCompany) != norm(contact.company)
            || norm(editedIdentity) != norm(contact.identity)
            || norm(editedPhone) != norm(contact.phoneNumber)
            || norm(editedEmail) != norm(contact.email)
            || norm(editedIndustry) != norm(contact.industry)
            || norm(editedLocation) != norm(contact.location)
            || norm(editedBirthday) != norm(contact.birthday)
            || norm(editedGender) != norm(contact.gender)
            || norm(editedNotes) != norm(contact.notes)
    }
    
    // 颜色定义
    private let bgColor = Color(red: 0.97, green: 0.97, blue: 0.97)
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    private let iconColor = Color(hex: "CCCCCC")
    
    private static let birthdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    private func parseBirthday(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // 1) 最常见：yyyy-MM-dd
        if let d = Self.birthdayFormatter.date(from: s) { return d }
        
        // 2) ISO8601 / 带时间（后端常见）
        if s.contains("T") || s.contains("Z") {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let d = iso2.date(from: s) { return d }
        }
        
        // 3) 其它常见：yyyy-MM-dd HH:mm:ss / yyyy-MM-dd'T'HH:mm:ss / yyyy/MM/dd / 中文年月日
        func tryFormat(_ fmt: String) -> Date? {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = fmt
            return df.date(from: s)
        }
        if let d = tryFormat("yyyy-MM-dd HH:mm:ss") { return d }
        if let d = tryFormat("yyyy-MM-dd'T'HH:mm:ss") { return d }
        if let d = tryFormat("yyyy-MM-dd'T'HH:mm") { return d }
        if let d = tryFormat("yyyy/MM/dd") { return d }
        if let d = tryFormat("yyyy/M/d") { return d }
        if let d = tryFormat("yyyy年M月d日") { return d }
        
        return nil
    }
    
    private func formatBirthday(_ date: Date) -> String {
        Self.birthdayFormatter.string(from: date)
    }
    
    private enum SubmittingAction {
        case save
        case delete
    }
    
    /// 仅在用户真实输入时标记 hasUserEdited（避免程序性同步草稿触发 onChange 误判）。
    private func userEditedBinding(_ binding: Binding<String>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                hasUserEdited = true
            }
        )
    }
    
    private var isBirthdayPickerEnabled: Bool {
        let rid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rid.isEmpty { return !isSubmitting }
        // 有 remoteId：必须等后端详情至少应用一次才允许点开，避免第一次进来默认“今天”
        return !isSubmitting && !isLoadingDetail && didApplyRemoteDetailOnce
    }
    
    // 语音输入相关（与“日程详情语音更新”同链路：PCM -> WS -> update_result）
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
    @State private var voiceSession: ContactVoiceUpdateService.Session? = nil
    @State private var voiceSendTask: Task<Void, Never>? = nil
    @State private var voiceReceiveTask: Task<Void, Never>? = nil
    @State private var voiceDoneTimeoutTask: Task<Void, Never>? = nil
    @State private var didSendAudioRecordDone: Bool = false
    /// 用于“超时续命”：只要服务端仍在回消息，就不要过早退出
    @State private var lastVoiceServerEventAt: Date? = nil
    
    private let silenceGate: Float = 0.12
    
    // 键盘状态：用于避免“语音编辑”按钮被键盘顶上来（与日程详情一致）
    @State private var isKeyboardVisible: Bool = false
    @FocusState private var isNotesFocused: Bool

    // MARK: - Debug logging (focus/keyboard)
    private func dbg(_ msg: String) {
#if DEBUG || targetEnvironment(simulator)
        let ts = String(format: "%.3f", Date().timeIntervalSince1970)
        print("🟩[ContactDetailView][\(ts)] \(msg)")
#endif
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
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                HapticFeedback.light()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    showGenderMenu = false
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
                    
                    Text("人脉详情")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(primaryTextColor)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .zIndex(100)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 姓名
                        TextField("姓名", text: userEditedBinding($editedName))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(primaryTextColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .padding(.horizontal, 64)
                            .padding(.top, 10)
                            .disabled(isSubmitting)
                        
                        // 基础信息内容（时间线暂不展示）
                        VStack(spacing: 20) {
                            // 公司和职位
                            EditableInfoRow(
                                icon: "building.2",
                                placeholder: "公司",
                                text: userEditedBinding($editedCompany),
                                subPlaceholder: "职位",
                                subText: userEditedBinding($editedIdentity),
                                isSubmitting: isSubmitting,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                                iconColor: iconColor
                            )
                            
                            // 行业
                            EditableSingleRow(
                                icon: "bag",
                                placeholder: "行业",
                                text: userEditedBinding($editedIndustry),
                                isSubmitting: isSubmitting,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                                iconColor: iconColor
                            )
                            
                            // 地区
                            EditableSingleRow(
                                icon: "mappin.and.ellipse",
                                placeholder: "地区",
                                text: userEditedBinding($editedLocation),
                                isSubmitting: isSubmitting,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                                iconColor: iconColor
                            )
                            
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            
                            // 电话
                            HStack(spacing: 0) {
                                EditableSingleRow(
                                    icon: "phone",
                                    placeholder: "手机号",
                                    text: userEditedBinding($editedPhone),
                                    keyboardType: .phonePad,
                                    isSubmitting: isSubmitting,
                                    primaryTextColor: primaryTextColor,
                                    secondaryTextColor: secondaryTextColor,
                                    iconColor: iconColor
                                )
                                
                                Button(action: {
                                    let phone = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !phone.isEmpty, let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Image(systemName: "phone.arrow.up.right")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(primaryTextColor)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                                }
                                .padding(.trailing, 20)
                            }
                            
                            // 邮箱
                            EditableSingleRow(
                                icon: "envelope",
                                placeholder: "邮箱",
                                text: userEditedBinding($editedEmail),
                                keyboardType: .emailAddress,
                                isSubmitting: isSubmitting,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                                iconColor: iconColor
                            )
                            
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            
                            // 生日
                            Button(action: {
                                HapticFeedback.light()
                                // sheet 方式：点击即弹出系统弹窗；不依赖行内 frame，逻辑更简单稳定
                                showGenderMenu = false
                                showDeleteMenu = false

                                // 以“后端真相”为准：若草稿为空，优先用 contact.birthday 初始化
                                let rawEdited = editedBirthday.trimmingCharacters(in: .whitespacesAndNewlines)
                                let rawContact = (contact.birthday ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                let raw = rawEdited.isEmpty ? rawContact : rawEdited
                                
                                if raw.isEmpty {
                                    birthdayPickerDate = Date()
                                } else if let d = editedBirthdayDate ?? parseBirthday(raw) {
                                    birthdayPickerDate = d
                                } else {
                                    birthdayPickerDate = Date()
                                }
                                showBirthdayPickerSheet = true
                            }) {
                                HStack(spacing: 0) {
                                    LabelWithIcon(icon: "calendar", title: "生日")
                                    Spacer()
                                    Text(editedBirthday.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置" : editedBirthday)
                                        .font(.system(size: 16))
                                        .foregroundColor(secondaryTextColor)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(iconColor)
                                        .padding(.leading, 6)
                                        .padding(.trailing, 20)
                                }
                                .padding(.leading, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!isBirthdayPickerEnabled)
                            
                            // 性别
                            HStack(spacing: 0) {
                                LabelWithIcon(icon: "person.fill", title: "性别")
                                Spacer()
                                Button(action: {
                                    HapticFeedback.light()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                        showGenderMenu.toggle()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Text(genderDisplayText(editedGender))
                                            .font(.system(size: 16))
                                            .foregroundColor(secondaryTextColor)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(iconColor)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isSubmitting)
                                .padding(.trailing, 20)
                            }
                            .padding(.leading, 20)
                            .modifier(GlobalFrameReporter(frame: $genderRowFrame))
                            
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            
                            // 备注/详细描述
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "tag")
                                    .font(.system(size: 18))
                                    .foregroundColor(iconColor)
                                    .frame(width: 24, alignment: .leading)
                                
                                // ✅ 与日程详情一致的根治：
                                // FocusState 只有在绑定的输入控件已存在于视图树中时，程序性设焦点才会生效。
                                // 之前这里是「isNotesFocused 才创建 TextField」，会导致点击文本态时 focus 设不进去。
                                // 现在改成：TextField 始终存在，用 overlay 展示 placeholder / LinkifiedText。
                                ZStack(alignment: .topLeading) {
                                    TextField("添加备注", text: userEditedBinding($editedNotes), axis: .vertical)
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                        .lineLimit(4...10)
                                        .lineSpacing(6)
                                        .disabled(isSubmitting)
                                        .focused($isNotesFocused)
                                        // 多行 TextField 默认回车是“换行”，这里改成“完成并收起键盘”（与日程详情一致）
                                        .onChange(of: editedNotes) { _, newValue in
                                            guard newValue.contains("\n") else { return }
                                            let sanitized = newValue
                                                .replacingOccurrences(of: "\n", with: " ")
                                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                            if editedNotes != sanitized {
                                                editedNotes = sanitized
                                            }
                                            dismissKeyboard()
                                        }
                                        // 未聚焦时隐藏真实输入（由 overlay 展示更美观的文本/链接）
                                        .opacity(isNotesFocused ? 1 : 0.01)
                                    
                                    if !isNotesFocused {
                                        let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                                        Group {
                                            if trimmed.isEmpty {
                                                Text("添加备注")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(secondaryTextColor)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            } else {
                                                LinkifiedText(
                                                    text: editedNotes,
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
                                            dbg("notes overlay tapped. isNotesFocused(before)=\(isNotesFocused)")
                                            isNotesFocused = true
                                            dbg("notes overlay set focus -> true. isNotesFocused(now)=\(isNotesFocused)")
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 120)
                    }
                }
                
            }
            
            // Voice Button
            ZStack {
                Capsule()
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                    .background(Capsule().fill(Color.white))
                    .frame(height: 56)
                    .background(GeometryReader { geo in Color.clear.onAppear { buttonFrame = geo.frame(in: .named("ContactDetailViewSpace")) } })
                
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
        .coordinateSpace(name: "ContactDetailViewSpace")
        // 与“日程详情”一致：全屏背景，避免键盘弹出时底部露出系统默认白底
        .background(bgColor.ignoresSafeArea())
        .onReceive(pcmRecorder.$audioLevel) { self.audioPower = mapAudioLevelToPower($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
            dbg("keyboardWillShow. isNotesFocused=\(isNotesFocused)")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
            dbg("keyboardWillHide. isNotesFocused=\(isNotesFocused)")
        }
        .onChange(of: isNotesFocused) { _, newValue in
            dbg("isNotesFocused changed -> \(newValue)")
        }
        .onDisappear {
            stopVoiceAndDismissOverlayImmediately()
        }
        .navigationBarHidden(true)
        .onAppear { syncDraftFromContactIfNeeded(force: true) }
        .task {
            await loadDetailIfNeeded()
        }
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
        // 点击空白处关闭菜单（与日程一致）
        .overlay {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if showGenderMenu || showDeleteMenu {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    showGenderMenu = false
                                    showDeleteMenu = false
                                }
                            }
                    }
                    
                    if showGenderMenu {
                        SingleSelectOptionMenu(
                            title: "性别",
                            options: genderOptions,
                            selectedValue: normalizedGenderValue(editedGender),
                            onSelect: { v in
                                hasUserEdited = true
                                editedGender = v
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    showGenderMenu = false
                                }
                            }
                        )
                        .frame(width: 220)
                        .offset(
                            PopupMenuPositioning.coveringRowOffset(
                                for: genderRowFrame,
                                in: geo.frame(in: .global),
                                menuWidth: 220,
                                menuHeight: SingleSelectOptionMenu.maxHeight(optionCount: genderOptions.count)
                            )
                        )
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                        .zIndex(20)
                    }

                    if showDeleteMenu {
                        TopDeletePillButton(title: "删除人脉") {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showDeleteMenu = false }
                            HapticFeedback.medium()
                            Task { await submitDelete() }
                        }
                        .frame(width: 200)
                        .offset(PopupMenuPositioning.rightAlignedCenterOffset(for: deleteMenuAnchorFrame, in: geo.frame(in: .global), width: 200, height: 52))
                        .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity), removal: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity)))
                        .zIndex(30)
                    }
                }
            }
        }
        // ✅ hasUserEdited 由 userEditedBinding / 显式交互（性别/生日）统一触发，避免程序性同步误判
        .sheet(isPresented: $showBirthdayPickerSheet) {
            BirthdayPickerSheet(
                date: $birthdayPickerDate,
                onDateChange: { d in
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        hasUserEdited = true
                        editedBirthdayDate = d
                        editedBirthday = formatBirthday(d)
                    }
                    // 选中日期后自动收起（日历 sheet 关闭）
                    DispatchQueue.main.async {
                        showBirthdayPickerSheet = false
                    }
                }
            )
            .presentationDetents([.height(380)])
            .presentationBackground(Color.white)
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Voice (WS streaming update)

    private func dismissKeyboard() {
        dbg("dismissKeyboard() called. isNotesFocused(before)=\(isNotesFocused)")
        isNotesFocused = false
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
        dbg("dismissKeyboard() done. isNotesFocused(after)=\(isNotesFocused)")
    }

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
        dismissKeyboard()

        isAnimatingRecordingExit = false
        isRecording = true
        isCapturingAudio = true
        isCanceling = false
        isBlueArcExiting = false
        recordingTranscript = "正在连接..."
        lastASRText = ""
        lastFinalASRText = ""
        didSendAudioRecordDone = false
        lastVoiceServerEventAt = nil
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

                let rid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rid.isEmpty else {
                    await MainActor.run {
                        alertMessage = "语音编辑失败：后端未返回联系人 id，无法进行语音更新。"
                        stopVoiceAndDismissOverlayImmediately()
                    }
                    return
                }

                let session = try ContactVoiceUpdateService.makeSession(contactId: rid, keepLocalId: contact.id)
                session.start()
                await MainActor.run {
                    self.voiceSession = session
                    self.recordingTranscript = "正在聆听..."
                    self.lastVoiceServerEventAt = Date()
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
                do { try await session?.sendCancel() } catch {}
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
        // 人脉更新通常需要 LLM 分析 + 写库，可能比日程更慢；这里给更长时间，并支持“收到消息自动续命”。
        armVoiceDoneTimeout()
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
        lastVoiceServerEventAt = nil
        withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true }
    }

    /// 超时逻辑：松手后最多等待 40s；如果中途服务端仍在回消息（asr/processing），则续命。
    private func armVoiceDoneTimeout(maxWaitSeconds: Int = 40) {
        voiceDoneTimeoutTask?.cancel()
        voiceDoneTimeoutTask = Task { @MainActor in
            let start = Date()
            while true {
                try? await Task.sleep(nanoseconds: 700_000_000) // 0.7s
                guard isRecording || isAnimatingRecordingExit else { return }

                // 若服务端仍在发消息，按“最近一次消息时间”续命；否则按 start 计时。
                let anchor = lastVoiceServerEventAt ?? start
                let elapsed = Date().timeIntervalSince(anchor)
                if elapsed >= Double(maxWaitSeconds) {
                    alertMessage = "语音更新超时，请稍后重试。"
                    stopVoiceAndDismissOverlayImmediately()
                    return
                }
            }
        }
    }

    private func startVoiceStreamingTasks(session: ContactVoiceUpdateService.Session) {
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
    private func handleVoiceUpdateEvent(_ ev: ContactVoiceUpdateService.Event) {
        // 只要服务端回了消息，就续命（避免后端处理稍慢导致“固定 12s 必超时”）
        lastVoiceServerEventAt = Date()
        if didSendAudioRecordDone {
            // 松手后才需要等待 update_result；此时服务端的 asr/processing 属于“仍在处理”信号
            armVoiceDoneTimeout()
        }

        switch ev {
        case let .asrResult(text, isFinal):
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                lastASRText = t
                if isFinal { lastFinalASRText = t }
            }
            // 需求：人脉详情“长按语音编辑”时，音浪下方不展示实时转写，始终保持“正在聆听…”
            recordingTranscript = isCapturingAudio ? "正在聆听..." : "正在分析语音内容..."
        case let .processing(message):
            let m = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            recordingTranscript = m.isEmpty ? "正在分析语音内容..." : m
        case let .updateResult(contact: updated, message: msg):
            applyVoiceUpdatedContactCard(updated, message: msg)

            let m = (msg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            recordingTranscript = m.isEmpty ? "已更新" : m
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

    @MainActor
    private func applyVoiceUpdatedContactCard(_ updated: ContactCard, message: String?) {
        // 1) 回写工具箱本地联系人模型（以 update_result 为真相）
        func norm(_ s: String?) -> String? {
            let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        let rid = (updated.remoteId ?? contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rid.isEmpty { contact.remoteId = rid }

        contact.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.company = norm(updated.company)
        contact.identity = norm(updated.title)
        contact.phoneNumber = norm(updated.phone)
        contact.email = norm(updated.email)
        contact.industry = norm(updated.industry)
        contact.location = norm(updated.location)
        contact.gender = norm(updated.gender)
        contact.birthday = norm(updated.birthday)
        // 备注：优先 notes；impression 若后端有且 notes 为空，也可兜底显示在备注（保持与其它链路一致）
        let notes = norm(updated.notes)
        let impression = norm(updated.impression)
        contact.notes = notes ?? impression

        contact.lastModified = Date()
        try? modelContext.save()

        // 2) 立刻覆盖草稿（语音更新是显式操作）
        editedName = contact.name
        editedCompany = contact.company ?? ""
        editedIdentity = contact.identity ?? ""
        editedPhone = contact.phoneNumber ?? ""
        editedEmail = contact.email ?? ""
        editedIndustry = contact.industry ?? ""
        editedLocation = contact.location ?? ""
        editedBirthday = contact.birthday ?? ""
        editedBirthdayDate = parseBirthday(editedBirthday)
        editedGender = normalizedGenderValue(contact.gender ?? "")
        editedNotes = contact.notes ?? ""

        didInitDraft = true
        didApplyRemoteDetailOnce = true
        hasUserEdited = true

        // 3) 同步到聊天历史（旧卡废弃 + 新卡生成）
        let reason = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        appState.commitContactCardRevision(updated: updated, modelContext: modelContext, reasonText: reason)
    }
    
    // MARK: - 后端详情/删除
    
    @MainActor
    private func loadDetailIfNeeded() async {
        let rid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else {
            didApplyRemoteDetailOnce = true
            return
        }
        guard !isLoadingDetail else { return }

        // 1) 仅当缓存 fresh 才用来填充；过期缓存不直接应用，避免“第一次进来先看到旧值”
        if let cached = await ContactService.peekContactDetail(remoteId: rid) {
            if cached.isFresh {
                applyRemoteDetailCard(cached.value, rid: rid)
            }
#if DEBUG
            // ✅ Debug：即使命中缓存也强制静默刷新一次，方便你在控制台看到「后端原始日志」
            Task { await refreshRemoteDetailSilently(rid: rid) }
            return
#elseif targetEnvironment(simulator)
            // ✅ 模拟器：默认也强制静默刷新一次，避免你 scheme/config 不是 DEBUG 时看不到日志
            Task { await refreshRemoteDetailSilently(rid: rid) }
            return
#else
            // 过期：后台静默刷新，不打断编辑体验
            Task { await refreshRemoteDetailSilently(rid: rid) }
            return
#endif
        }
        
        // 2) 首次无缓存：才显示 loading
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        
        do {
            let card = try await ContactService.fetchContactDetail(remoteId: rid, keepLocalId: contact.id)
            applyRemoteDetailCard(card, rid: rid)
        } catch {
            // 静默失败：保留本地信息
        }
    }
    
    @MainActor
    private func refreshRemoteDetailSilently(rid: String) async {
        do {
            // 关键：静默刷新也要绕开详情缓存，否则会被 10min TTL 卡住，导致“卡片已更新但详情页仍旧不变”
            let card = try await ContactService.fetchContactDetail(remoteId: rid, keepLocalId: contact.id, forceRefresh: true)
            applyRemoteDetailCard(card, rid: rid)
        } catch {
            // 静默刷新失败不打扰用户
        }
    }
    
    @MainActor
    private func applyRemoteDetailCard(_ card: ContactCard, rid: String) {
        // ✅ 以“后端详情”为唯一真相：后端返回什么就写什么（空/缺字段即置 nil），不做本地兜底推断。
        func norm(_ s: String?) -> String? {
            let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        contact.remoteId = norm(card.remoteId) ?? rid
        contact.name = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.company = norm(card.company)
        contact.identity = norm(card.title)
        contact.phoneNumber = norm(card.phone)
        contact.email = norm(card.email)
        contact.industry = norm(card.industry)
        contact.location = norm(card.location)
        contact.gender = norm(card.gender)
        contact.birthday = norm(card.birthday)
        // 备注：同样以详情为准（不做拼接合并）
        contact.notes = norm(card.notes)
        contact.lastModified = Date()
        try? modelContext.save()
        didApplyRemoteDetailOnce = true
        // 只有用户还没开始编辑时，才用后端返回覆盖草稿
        syncDraftFromContactIfNeeded(force: false)
    }
    
    @MainActor
    private func submitDelete() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submittingAction = .delete
        defer { isSubmitting = false }
        
        await appState.softDeleteContactModel(contact, modelContext: modelContext)
        dismiss()
        submittingAction = nil
    }
    
    @MainActor
    private func submitSave() async {
        guard !isSubmitting else { return }
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            alertMessage = "姓名不能为空"
            return
        }

        // 未发生任何变更：不触发 loading/网络请求，直接退出即可
        guard hasDraftChanges else {
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
            // 以“后端成功”为准：先发请求，成功后再写入本地模型
            var payload: [String: Any] = ["name": name]

            let company = editedCompany.trimmingCharacters(in: .whitespacesAndNewlines)
            if !company.isEmpty { payload["company"] = company }
            let position = editedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
            if !position.isEmpty { payload["position"] = position }
            let phone = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !phone.isEmpty { payload["phone"] = phone }
            let email = editedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty { payload["email"] = email }
            let industry = editedIndustry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !industry.isEmpty { payload["industry"] = industry }
            let location = editedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            // 后端字段是 address（历史上也可能叫 location/region/city，但 update 以 address 为准）
            if !location.isEmpty { payload["address"] = location }
            let birthday = editedBirthday.trimmingCharacters(in: .whitespacesAndNewlines)
            if !birthday.isEmpty { payload["birthday"] = birthday }
            let gender = normalizedGenderValue(editedGender)
            if !gender.isEmpty { payload["gender"] = gender }
            let notes = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { payload["notes"] = notes }

            let currentRid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let opResult: ContactService.OperationResult
            if currentRid.isEmpty {
                opResult = try await ContactService.createContact(payload: payload, keepLocalId: contact.id)
            } else {
                opResult = try await ContactService.updateContact(remoteId: currentRid, payload: payload, keepLocalId: contact.id)
            }

            let remoteCard = opResult.card
            let effectiveRid = ((remoteCard?.remoteId ?? currentRid)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !effectiveRid.isEmpty else {
                throw NSError(domain: "MolyMemo.Contact", code: -2, userInfo: [NSLocalizedDescriptionKey: "后端未返回联系人ID，无法确保已同步到后端"])
            }

            // 若后端 update/create 没有返回 body，则强制拉一次详情，确保“以最新后端状态为准”
            let canonical: ContactCard
            if let remoteCard {
                canonical = remoteCard
            } else {
                // forceRefresh=true：避免拿到旧缓存
                canonical = try await ContactService.fetchContactDetail(remoteId: effectiveRid, keepLocalId: contact.id, forceRefresh: true)
            }

            // 写回本地模型（用后端字段；若后端缺字段，则用编辑态兜底）
            contact.remoteId = canonical.remoteId ?? effectiveRid
            contact.name = canonical.name
            contact.company = (canonical.company?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.company : (company.isEmpty ? nil : company)
            contact.identity = (canonical.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.title : (position.isEmpty ? nil : position)
            contact.phoneNumber = (canonical.phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.phone : (phone.isEmpty ? nil : phone)
            contact.email = (canonical.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.email : (email.isEmpty ? nil : email)
            contact.industry = (canonical.industry?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.industry : (industry.isEmpty ? nil : industry)
            contact.location = (canonical.location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.location : (location.isEmpty ? nil : location)
            contact.birthday = (canonical.birthday?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.birthday : (birthday.isEmpty ? nil : birthday)
            contact.gender = (canonical.gender?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? canonical.gender : (gender.isEmpty ? nil : gender)

            // 备注：只认后端 note/notes（canonical.notes）。若后端没回，才用本次编辑态兜底。
            let n = (canonical.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty {
                contact.notes = n
            } else {
                contact.notes = notes.isEmpty ? nil : notes
            }

            contact.lastModified = Date()
            try modelContext.save()

            // 统一：旧卡废弃 + 生成新卡（保留历史版本）
            // ✅ 仅展示后端给的文案；若后端没有给，则不再硬编码“已更新联系人”，只更新卡片本身。
            let reasonText = (opResult.displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            appState.commitContactCardRevision(updated: canonical, modelContext: modelContext, reasonText: reasonText)
            
            // 单向同步到系统通讯录：保存成功后，若有手机号且尚未绑定 identifier，则后台尝试同步/匹配
            triggerSystemContactSyncIfNeeded()
            dismiss()
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
        }
    }
    
    private func syncDraftFromContactIfNeeded(force: Bool) {
        if didInitDraft, !force, hasUserEdited { return }

        editedName = contact.name
        editedCompany = contact.company ?? ""
        editedIdentity = contact.identity ?? ""
        editedPhone = contact.phoneNumber ?? ""
        editedEmail = contact.email ?? ""
        editedIndustry = contact.industry ?? ""
        editedLocation = contact.location ?? ""
        editedBirthday = contact.birthday ?? ""
        editedBirthdayDate = parseBirthday(editedBirthday)
        editedGender = normalizedGenderValue(contact.gender ?? "")
        editedNotes = contact.notes ?? ""
        didInitDraft = true
        if force { hasUserEdited = false }
    }
    
    // MARK: - 性别下拉
    
    private var genderOptions: [SingleSelectOptionMenu.Option] {
        [
            .init(title: "男", value: "male"),
            .init(title: "女", value: "female")
        ]
    }
    
    private func normalizedGenderValue(_ raw: String) -> String {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch v {
        case "male", "m", "男": return "male"
        case "female", "f", "女": return "female"
        default: return ""
        }
    }
    
    private func genderDisplayText(_ raw: String) -> String {
        switch normalizedGenderValue(raw) {
        case "male": return "男"
        case "female": return "女"
        default: return "未设置"
        }
    }
    
    private func triggerSystemContactSyncIfNeeded() {
        let phone = (contact.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let linked = (contact.systemContactIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 规则：
        // - 已绑定 identifier：允许无手机号也去更新（例如修改公司/备注等）
        // - 未绑定 identifier：至少需要手机号才尝试匹配/创建（避免仅按名字误匹配）
        if linked.isEmpty, phone.isEmpty {
            dbg("syncSystemContact skip: no linkedId and no phone. name=\(contact.name)")
            return
        }
        
        dbg("syncSystemContact start: name=\(contact.name) phone=\(phone) linkedId=\(linked)")
        
        Task(priority: .utility) {
            let granted = await ContactsManager.shared.requestAccess()
            if !granted {
                await MainActor.run { dbg("syncSystemContact abort: permission denied") }
                return
            }
            
            do {
                // 详情页“保存”属于更新：以联系人为锚点更新，不允许在这里新建系统联系人，避免重复创建。
                let updatedId = try await ContactsManager.shared.updateSystemContact(contact: contact, source: "ContactDetailView.save")
                let id = (updatedId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if id.isEmpty {
                    await MainActor.run { dbg("syncSystemContact result: not found / not updated (id empty)") }
                    return
                }
                
                await MainActor.run {
                    dbg("syncSystemContact result: updated id=\(id) (linkedId before=\(linked))")
                    if linked != id {
                        contact.systemContactIdentifier = id
                        try? modelContext.save()
                        dbg("syncSystemContact wrote back systemContactIdentifier=\(id)")
                    }
                }
            } catch {
                await MainActor.run { dbg("syncSystemContact error: \(error.localizedDescription)") }
            }
        }
    }
}

// MARK: - 辅助组件

private struct BirthdayPickerSheet: View {
    @Binding var date: Date
    let onDateChange: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DatePicker(
                "",
                selection: $date,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .padding(.horizontal)
            .padding(.top, 10)
            .onChange(of: date) { _, newValue in
                onDateChange(newValue)
            }
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    var subtext: String? = nil
    
    private let iconColor = Color(hex: "CCCCCC")
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(primaryTextColor)
                
                if let subtext = subtext, !subtext.isEmpty {
                    Text(subtext)
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct LabelWithIcon: View {
    let icon: String
    let title: String
    
    private let iconColor = Color(hex: "CCCCCC")
    private let primaryTextColor = Color(hex: "333333")
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(primaryTextColor)
        }
    }
}

// MARK: - 可编辑行（轻量）：按日程详情的“直接编辑 + ✅ 保存”思路做最小对齐
private struct EditableInfoRow: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let subPlaceholder: String
    @Binding var subText: String
    let isSubmitting: Bool
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 6) {
                TextField(placeholder, text: $text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .disabled(isSubmitting)
                
                TextField(subPlaceholder, text: $subText)
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
                    .disabled(isSubmitting)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

private struct EditableSingleRow: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    let isSubmitting: Bool
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(primaryTextColor)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .disabled(isSubmitting)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
