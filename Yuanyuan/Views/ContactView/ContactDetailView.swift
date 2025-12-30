import SwiftUI
import SwiftData

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Bindable var contact: Contact
    
    @State private var selectedTab = 0 // 0: 基础信息, 1: 时间线
    @State private var showDeleteMenu = false
    @State private var isLoadingDetail: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submittingAction: SubmittingAction? = nil
    @State private var alertMessage: String? = nil
    
    // 与「日程详情」一致：用 edited 草稿承载编辑态，✅ 提交保存后再写回 contact
    @State private var editedName: String = ""
    @State private var editedCompany: String = ""
    @State private var editedIdentity: String = ""
    @State private var editedPhone: String = ""
    @State private var editedEmail: String = ""
    @State private var editedNotes: String = ""
    @State private var didInitDraft: Bool = false
    @State private var hasUserEdited: Bool = false

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
            || norm(editedNotes) != norm(contact.notes)
    }
    
    // 颜色定义
    private let bgColor = Color(red: 0.97, green: 0.97, blue: 0.97)
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    private let iconColor = Color(hex: "CCCCCC")
    
    private enum SubmittingAction {
        case save
        case delete
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
                    
                    Text("人脉详情")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(primaryTextColor)
                    
                    if showDeleteMenu {
                        TopDeletePillButton(title: "删除人脉") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDeleteMenu = false }
                            HapticFeedback.medium()
                            Task { await submitDelete() }
                        }
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
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 姓名
                        TextField("姓名", text: $editedName)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(primaryTextColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .padding(.horizontal, 64)
                            .padding(.top, 10)
                            .disabled(isSubmitting)
                        
                        // 分段选择器
                        HStack(spacing: 0) {
                            TabButton(title: "基础信息", isSelected: selectedTab == 0) {
                                withAnimation(.spring(response: 0.3)) { selectedTab = 0 }
                            }
                            
                            TabButton(title: "时间线", isSelected: selectedTab == 1) {
                                withAnimation(.spring(response: 0.3)) { selectedTab = 1 }
                            }
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Capsule())
                        .padding(.horizontal, 40)
                        
                        if selectedTab == 0 {
                            // 基础信息内容
                            VStack(spacing: 20) {
                                // 公司和职位
                                EditableInfoRow(
                                    icon: "building.2",
                                    placeholder: "公司",
                                    text: $editedCompany,
                                    subPlaceholder: "职位",
                                    subText: $editedIdentity,
                                    isSubmitting: isSubmitting,
                                    primaryTextColor: primaryTextColor,
                                    secondaryTextColor: secondaryTextColor,
                                    iconColor: iconColor
                                )
                                
                                // 行业
                                InfoRow(icon: "bag", text: contact.industry ?? "未填写行业")
                                
                                // 地区
                                InfoRow(icon: "mappin.and.ellipse", text: contact.location ?? "未填写地区")
                                
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                
                                // 电话
                                HStack(spacing: 0) {
                                    EditableSingleRow(
                                        icon: "phone",
                                        placeholder: "手机号",
                                        text: $editedPhone,
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
                                    text: $editedEmail,
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
                                HStack(spacing: 0) {
                                    LabelWithIcon(icon: "calendar", title: "生日")
                                    Spacer()
                                    Text(contact.birthday ?? "未设置")
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                        .padding(.trailing, 20)
                                }
                                .padding(.leading, 20)
                                
                                // 性别
                                HStack(spacing: 0) {
                                    LabelWithIcon(icon: "person.fill", title: "性别")
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text(contact.gender ?? "未知")
                                            .font(.system(size: 16))
                                            .foregroundColor(primaryTextColor)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(iconColor)
                                    }
                                    .padding(.trailing, 20)
                                }
                                .padding(.leading, 20)
                                
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                
                                // 备注/详细描述
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 18))
                                        .foregroundColor(iconColor)
                                        .frame(width: 24, alignment: .leading)
                                    
                                    TextField("添加备注", text: $editedNotes, axis: .vertical)
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                        .lineLimit(4...10)
                                        .lineSpacing(6)
                                        .disabled(isSubmitting)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }
                        } else {
                            // 时间线内容
                            VStack {
                                Text("暂无时间线记录")
                                    .foregroundColor(secondaryTextColor)
                                    .padding(.top, 40)
                            }
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
        .coordinateSpace(name: "ContactDetailViewSpace")
        .background(bgColor)
        .onAppear { speechRecognizer.requestAuthorization() }
        .onReceive(speechRecognizer.$audioLevel) { self.audioPower = mapAudioLevelToPower($0) }
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
        // ⚠️ 不能用全屏 overlay 盖住一切，否则会把顶部“删除人脉”胶囊的点击也拦截掉，造成“点了没反应”的体感。
        .overlay {
            if showDeleteMenu {
                VStack(spacing: 0) {
                    // 预留顶部区域给 header + 删除胶囊（避免遮罩吞掉按钮点击）
                    Color.clear
                        .frame(height: 140)
                        .allowsHitTesting(false)
                    
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { showDeleteMenu = false } }
                }
                .ignoresSafeArea()
            }
        }
        // 任何编辑即标记
        .onChange(of: editedName) { _, _ in hasUserEdited = true }
        .onChange(of: editedCompany) { _, _ in hasUserEdited = true }
        .onChange(of: editedIdentity) { _, _ in hasUserEdited = true }
        .onChange(of: editedPhone) { _, _ in hasUserEdited = true }
        .onChange(of: editedEmail) { _, _ in hasUserEdited = true }
        .onChange(of: editedNotes) { _, _ in hasUserEdited = true }
    }
    
    // Voice logic
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
    
    private func parseVoiceCommand(voiceText: String) {
        Task {
            // TODO: 调用相关的语音解析逻辑更新联系人信息
            // 这里可以复用类似 TodoVoiceParser 的逻辑，或者为联系人单独写一个
            HapticFeedback.success()
        }
    }
    
    // MARK: - 后端详情/删除
    
    @MainActor
    private func loadDetailIfNeeded() async {
        let rid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }
        guard !isLoadingDetail else { return }

        // 1) 先用缓存填充（进入详情页不展示 loading 浮层，详情异步补齐即可）
        if let cached = await ContactService.peekContactDetail(remoteId: rid) {
            applyRemoteDetailCard(cached.value, rid: rid)
#if DEBUG
            // ✅ Debug：即使命中缓存也强制静默刷新一次，方便你在控制台看到「后端原始日志」
            Task { await refreshRemoteDetailSilently(rid: rid) }
            return
#elseif targetEnvironment(simulator)
            // ✅ 模拟器：默认也强制静默刷新一次，避免你 scheme/config 不是 DEBUG 时看不到日志
            Task { await refreshRemoteDetailSilently(rid: rid) }
            return
#else
            if cached.isFresh { return }
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
        // 用后端信息覆盖/补齐本地字段（只更新有意义的字段，避免把本地自维护信息清空）
        contact.remoteId = card.remoteId ?? rid
        if !card.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contact.name = card.name
        }
        if let v = card.company?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            contact.company = v
        }
        if let v = card.title?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            contact.identity = v
        }
        if let v = card.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            contact.phoneNumber = v
        }
        if let v = card.email?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            contact.email = v
        }
        // 备注：只使用后端 note/notes 字段（ContactCard.notes）回填，避免把 impression 混进备注
        let remoteNotes = (card.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteNotes.isEmpty {
            let current = (contact.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                contact.notes = remoteNotes
            } else if !current.contains(remoteNotes) {
                contact.notes = current + "\n\n" + remoteNotes
            }
        }
        contact.lastModified = Date()
        try? modelContext.save()
        // 只有用户还没开始编辑时，才用后端返回覆盖草稿
        syncDraftFromContactIfNeeded(force: false)
    }
    
    @MainActor
    private func submitDelete() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submittingAction = .delete
        defer { isSubmitting = false }
        
        do {
            try await DeleteActions.deleteContact(contact, modelContext: modelContext)
            dismiss()
        } catch {
            alertMessage = "删除失败：\(error.localizedDescription)"
        }
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
            let notes = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { payload["notes"] = notes }

            let currentRid = (contact.remoteId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteCard: ContactCard?
            if currentRid.isEmpty {
                remoteCard = try await ContactService.createContact(payload: payload, keepLocalId: contact.id)
            } else {
                remoteCard = try await ContactService.updateContact(remoteId: currentRid, payload: payload, keepLocalId: contact.id)
            }

            let effectiveRid = ((remoteCard?.remoteId ?? currentRid)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !effectiveRid.isEmpty else {
                throw NSError(domain: "Yuanyuan.Contact", code: -2, userInfo: [NSLocalizedDescriptionKey: "后端未返回联系人ID，无法确保已同步到后端"])
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

            // 备注：只认后端 note/notes（canonical.notes）。若后端没回，才用本次编辑态兜底。
            let n = (canonical.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty {
                contact.notes = n
            } else {
                contact.notes = notes.isEmpty ? nil : notes
            }

            contact.lastModified = Date()
            try modelContext.save()

            // 同步刷新聊天里的卡片展示（以 canonical 为准）
            appState.applyUpdatedContactCardToChatMessages(canonical)
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
        editedNotes = contact.notes ?? ""
        didInitDraft = true
        if force { hasUserEdited = false }
    }
}

// MARK: - 辅助组件

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? Color(hex: "333333") : Color(hex: "999999"))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.white : Color.clear)
                .clipShape(Capsule())
                .shadow(color: isSelected ? Color.black.opacity(0.05) : Color.clear, radius: 4, x: 0, y: 2)
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
