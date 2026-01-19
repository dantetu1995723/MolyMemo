import SwiftUI
import PhotosUI
import Combine
import AVFoundation

@MainActor
class ChatInputViewModel: ObservableObject {
    // MARK: - Input State
    @Published var inputText: String = ""
    @Published var selectedImage: UIImage? = nil
    @Published var selectedPhotoItem: PhotosPickerItem? = nil
    
    // MARK: - Recording State
    @Published var isRecording: Bool = false
    @Published var isAnimatingRecordingEntry: Bool = false
    @Published var isAnimatingRecordingExit: Bool = false
    @Published var isCanceling: Bool = false
    @Published var audioPower: CGFloat = 0.0
    @Published var recordingTranscript: String = ""
    @Published var inputFrame: CGRect = .zero
    @Published var toolboxFrame: CGRect = .zero
    
    // MARK: - UI State
    @Published var showMenu: Bool = false
    @Published var showSuggestions: Bool = false
    @Published var showCamera: Bool = false
    
    // MARK: - Agent State
    @Published var isAgentTyping: Bool = false
    
    // MARK: - Actions
    var onSend: ((String, UIImage?) -> Void)?
    var onSendImmediate: (() -> UUID?)?  // 立即发送占位消息，返回消息ID用于后续更新
    var onUpdateAndSend: ((UUID, String) -> Void)?  // 更新消息内容并触发AI对话（非语音 WS）
    var onUpdatePlaceholderText: ((UUID, String) -> Void)?  // 仅更新用户占位气泡（语音实时转写）
    var onRemovePlaceholder: ((UUID) -> Void)?  // 删除占位消息（用于转录失败或结果为空）
    /// 语音 WS：开始一条新的 AI 占位消息（返回 agent messageId），并进入“打字中”态
    var onBeginVoiceAgentMessage: (() -> UUID?)?
    /// 语音 WS：把后端 chunk（delta）回填到指定 agent message
    var onApplyVoiceAgentOutput: ((UUID, BackendChatStructuredOutput) -> Void)?
    /// 语音 WS：结束 agent message（完成/落库/退出打字中）
    var onEndVoiceAgentMessage: ((UUID) -> Void)?
    /// 语音 WS：流式错误（若 messageId=nil 表示尚未创建 agent 占位）
    var onVoiceAgentError: ((UUID?, String) -> Void)?
    /// 测试：把“原始录音”插入聊天（用户气泡，带本地可播放音频）。
    /// - 仅用于验证按住说话的音频是否正确采集；不影响现有转写/AI 链路。
    var onInsertHoldToTalkRawAudio: ((URL) -> Void)?
    var onBoxTap: (() -> Void)?
    var onStopGenerator: (() -> Void)?
    
    // MARK: - Internal
    private let holdToTalkRecorder = HoldToTalkPCMRecorder()
    private var holdToTalkVoiceSession: ChatVoiceInputService.Session?
    private var holdToTalkGeneration: Int = 0
    private var holdToTalkASRTask: Task<Void, Never>?
    private var holdToTalkRecognizingWaveTask: Task<Void, Never>?
    private var holdToTalkSendLoopTask: Task<Void, Never>?
    private var holdToTalkReceiveLoopTask: Task<Void, Never>?
    /// 预收音启动任务：用于“快速取消/结束”时阻止异步插入占位气泡
    private var holdToTalkStartupTask: Task<Void, Never>?
    private var holdToTalkPlaceholderMessageId: UUID?
    private var holdToTalkAgentMessageId: UUID?
    private var holdToTalkLatestASRText: String = ""
    private var holdToTalkLatestASRIsFinal: Bool = false
    /// PCM 发送缓冲：避免 WS 刚建立时 send() 失败导致前面音频丢失（漏字）
    private var holdToTalkPCMBacklog: PCMBacklog?
    /// 松手后进入“识别中”阶段：忽略 recorder stop() 导致的音量归零，避免音浪瞬间静止产生卡顿感
    private var isHoldToTalkRecognizing: Bool = false
    private var cancellables = Set<AnyCancellable>()
    /// 按住说话：按下瞬间就开始“预收音/预转写”，但不立刻展示 overlay（避免轻点聚焦时闪一下 UI）
    private var isPreCapturingHoldToTalk: Bool = false
    /// 录音结束后待回填到输入框的转写文本（用于：输入框尚未出现/尚在退场动画时延迟写回）
    private var pendingDictationTextForInput: String?
    /// 停止录音后等待 final 结果：在 overlay 退场完成时再决定是否回填（避免 stop 当下读取到 partial 导致漏字）
    private var shouldBackfillTranscriptOnOverlayDismiss: Bool = false
    /// hold-to-talk 过程中持续更新的“最近一次识别文本”（用于 stop 后发送）
    private var holdToTalkLatestText: String = ""
    /// 测试：汇总本次按住说话的完整 PCM（16k/16bit/mono）。
    /// - 由于 sendLoop 会 drain PCM 并清空 recorder 缓冲，所以需要额外累积一份。
    /// - 仅用于本地落盘成 wav 并展示；不会影响 WS 的发送数据。
    private var holdToTalkFullPCM: Data = Data()
    
    // MARK: - Computed Properties
    
    /// 是否有内容（文字或图片）
    var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
    }
    
    // MARK: - Methods
    
    init() {
        // 用真实收音 level 驱动 UI（来自麦克风 PCM 采集）
        holdToTalkRecorder.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self else { return }
                // 识别中阶段：不让 stop() 的 0 覆盖当前波动，避免 UI “一下子停住”
                guard !self.isHoldToTalkRecognizing else { return }
                self.audioPower = CGFloat(level)
            }
            .store(in: &cancellables)
    }
    
    func sendMessage() {
        // AI 输入过程中：输入区除“中止”外全部禁用
        guard !isAgentTyping else { return }
        guard hasContent else { return }

        // 只用 hasContent(=trim 判空) 决定能否发送；真正发送内容保持“原始文本”，不做 trim/替换。
        let rawTextToSend = inputText
        onSend?(rawTextToSend, selectedImage)
        
        // Reset State
        // 注意：发送动作通常会触发键盘退场（失焦）以及外层布局变化。
        // 这里不要用 withAnimation 包裹“清空输入/移除按钮”，避免出现按钮 transition
        // 与键盘/布局动画不同步导致的“脱层、原地消失”观感。
        inputText = ""
        selectedImage = nil
        selectedPhotoItem = nil
        showSuggestions = false
    }
    
    /// 发送建议指令（不清空输入框，但图片会一起发送）
    func sendSuggestion(_ suggestion: String) {
        // AI 输入过程中：输入区除“中止”外全部禁用
        guard !isAgentTyping else { return }
        // 指令等同于用户发出去的文字：
        // - 指令 +（若存在）当前图片一起发出去
        // - 输入框里已打的字保留
        // - 发完后清掉图片，让输入区回到纯文字输入状态
        let imageToSend = selectedImage
        onSend?(suggestion, imageToSend)
        
        // 清掉图片，但保留 inputText（用户存量打字）
        withAnimation {
            selectedImage = nil
            selectedPhotoItem = nil
            // 发完指令后，按钮不应继续存在（即使输入框里还有存量文字）
            showSuggestions = false
        }
    }
    
    func handlePhotoSelection(_ item: PhotosPickerItem?) {
        // AI 输入过程中：输入区除“中止”外全部禁用
        guard !isAgentTyping else { return }
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.selectedImage = image
                        self.showMenu = false // Hide menu after selection
                        self.checkForSuggestions() // Mock suggestion trigger
                    }
                }
            }
        }
    }
    
    func removeImage() {
        // 允许移除图片也会改变 UI，但 AI 输入时 UI 已锁定且菜单/选择入口已禁用；
        // 这里不再额外 guard，避免出现“状态卡死”无法清理的情况。
        withAnimation {
            selectedImage = nil
            selectedPhotoItem = nil
            showSuggestions = false // Hide suggestions when image is removed
        }
    }
    
    func toggleMenu() {
        // AI 输入过程中：输入区除“中止”外全部禁用
        guard !isAgentTyping else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
            showMenu.toggle()
        }
    }
    
    /// 模拟触发建议（例如输入了某些关键词或添加了图片）
    func checkForSuggestions() {
        if hasContent {
            withAnimation {
                showSuggestions = true
            }
        } else {
            withAnimation {
                showSuggestions = false
            }
        }
    }
    
    // MARK: - Recording Logic
    
    func startRecording() {
        // AI 输入过程中：输入区除"中止"外全部禁用
        guard !isAgentTyping else { return }

        // 统一走“预收音 -> 展示 overlay”，减少重复逻辑
        beginHoldToTalkPreCaptureIfNeeded()
        revealHoldToTalkOverlayIfPossible()
    }
    
    func stopRecording() {
        // 已经在退场过程中，避免重复触发（重复 stop 可能导致发送两次）
        guard !isAnimatingRecordingExit else { return }

        // 结束预收音状态（无论是否已展示 overlay）
        isPreCapturingHoldToTalk = false
        let shouldSend = !isCanceling
        let genAtStop = holdToTalkGeneration
        holdToTalkASRTask?.cancel()
        holdToTalkASRTask = nil
        holdToTalkRecognizingWaveTask?.cancel()
        holdToTalkRecognizingWaveTask = nil
        holdToTalkSendLoopTask?.cancel()
        holdToTalkSendLoopTask = nil
        holdToTalkStartupTask?.cancel()
        holdToTalkStartupTask = nil

        // 取消：立即 stop + 退场（不进入识别态）
        guard shouldSend else {
            // 取消需要告知后端并释放麦克风
            let placeholderId = holdToTalkPlaceholderMessageId
            holdToTalkPlaceholderMessageId = nil
            holdToTalkAgentMessageId = nil
            holdToTalkLatestText = ""
            holdToTalkLatestASRText = ""
            holdToTalkLatestASRIsFinal = false
            recordingTranscript = ""
            isHoldToTalkRecognizing = false
            holdToTalkReceiveLoopTask?.cancel()
            holdToTalkReceiveLoopTask = nil
            Task.detached { [weak self] in
                guard let self else { return }
                if let s = await MainActor.run(body: { self.holdToTalkVoiceSession }) {
                    try? await s.sendCancel()
                    await s.close()
                }
                _ = await MainActor.run { self.holdToTalkRecorder.stop(discard: true) }
                await MainActor.run { self.holdToTalkVoiceSession = nil }
            }
            if let placeholderId {
                onRemovePlaceholder?(placeholderId)
            }
            beginHoldToTalkExit()
            return
        }

        // ✅ 松手发送：不再插入“识别中...”气泡。
        // - 用户气泡：由 asr_result/asr_complete 实时更新占位消息内容
        // - AI 气泡：由 `/api/v1/chat/voice` 的 assistant chunk 按普通 chat 结构化回填
        recordingTranscript = ""
        beginHoldToTalkExit()

        holdToTalkASRTask = Task { [weak self] in
            guard let self else { return }
            // 让 SwiftUI 先完成一帧退场/布局，再进行 stop（AudioSession 归还/收尾可能会卡顿）
            await Task.yield()
            guard !Task.isCancelled else { return }
            // 如果期间又开始了新一轮按住说话，就不要影响新一轮
            guard self.holdToTalkGeneration == genAtStop else { return }
            await self.finishBackendHoldToTalkAndSendAudioDone(genAtStop: genAtStop)
        }
    }

    /// 新的判定逻辑：长按成立后才进入录音（先展示 overlay，再启动录音引擎，避免“进去前卡顿”）
    func startHoldToTalkRecordingFromLongPress() {
        guard !isAgentTyping else { return }
        guard !isRecording else { return }

        // 接管上一轮识别中状态（如果存在）
        isHoldToTalkRecognizing = false
        stopHoldToTalkRecognizingWave()

        // 兼容：某些手势链路可能“长按成立”才触发，而没有先走 press-down 预收音；
        // 这里确保本地语音识别已启动，否则会出现“进入录音 UI 但收不到音/没转写”的问题。
        beginHoldToTalkPreCaptureIfNeeded()
        revealHoldToTalkOverlayIfPossible()
    }

    /// 开始“识别中”的假音浪（松手后保持波动更丝滑）
    private func startHoldToTalkRecognizingWave() {
        holdToTalkRecognizingWaveTask?.cancel()
        // 立即抬到阈值之上，避免 VoiceWaveformView 切到静态条导致的“顿一下”
        audioPower = max(audioPower, 0.22)
        holdToTalkRecognizingWaveTask = Task { @MainActor in
            var t: Double = 0
            while !Task.isCancelled {
                // 保持 > 0.01，确保 VoiceWaveformView 走 TimelineView 动画分支
                let base: CGFloat = 0.22
                let a1: CGFloat = 0.10
                let a2: CGFloat = 0.06
                let v = base + a1 * CGFloat(sin(t * 2.2)) + a2 * CGFloat(sin(t * 5.7 + 1.3))
                self.audioPower = max(0.08, min(v, 0.55))
                t += 0.06
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30fps
            }
        }
    }

    private func stopHoldToTalkRecognizingWave() {
        holdToTalkRecognizingWaveTask?.cancel()
        holdToTalkRecognizingWaveTask = nil
    }

    /// 快速退场：输入框立即恢复，overlay 自己淡出并回调 finish
    private func beginHoldToTalkExit() {
        // 关键：先把“退场标记”置起来，避免出现 isRecording=false & isAnimatingRecordingExit=false 的短暂窗口
        // 否则 SwiftUI 可能把 overlay 从树里移除再插回，导致 overlay 的 onChange(isExiting) 不触发，从而卡住。
        isPreCapturingHoldToTalk = false
        withAnimation(.easeInOut(duration: 0.12)) {
            isAnimatingRecordingExit = true
        }
        // 让输入框立刻回来（更丝滑）
        isRecording = false
        // 兜底：任何退出都结束“识别中锁定”
        isHoldToTalkRecognizing = false
    }
    
    /// 由 overlay 的逆向动画结束回调触发：真正收起 overlay 并恢复输入框
    func finishRecordingOverlayDismissal() {
        withAnimation(.easeInOut(duration: 0.1)) {
            // isRecording 已在 beginHoldToTalkExit 里提前置 false，用于“输入框立即回归”
            isAnimatingRecordingEntry = false
            isAnimatingRecordingExit = false
            isCanceling = false
            audioPower = 0
        }
        // 发送动作由 AUC flash 回调驱动；这里仅负责收 UI
    }
    
    func cancelRecording() {
        withAnimation {
            isCanceling = true
        }
        print("[HoldToTalk] 🙅 cancel (will stop after 0.3s)")
        // Delay stop to show cancel animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
             self.stopRecording()
        }
    }

    /// 停止“语音 WS 的 AI 回复流”（用于：用户点了“中止”按钮）。
    /// - 备注：普通 chat 的中止由 AppState.stopGeneration() 处理；这里补齐 voice WS 的取消。
    func stopVoiceAssistantIfNeeded() {
        Task.detached { [weak self] in
            guard let self else { return }
            if let s = await MainActor.run(body: { self.holdToTalkVoiceSession }) {
                try? await s.sendCancel()
            }
            await self.closeHoldToTalkSession()
        }
    }

    // MARK: - Hold-to-talk pre-capture (press-down immediately, reveal overlay slightly later)

    /// 按下瞬间调用：立刻开始收音/转写，但不展示 overlay（防止轻点聚焦时 UI 闪烁）。
    func beginHoldToTalkPreCaptureIfNeeded() {
        // AI 输入过程中：输入区除"中止"外全部禁用
        guard !isAgentTyping else { return }
        guard !isRecording else { return } // 已在录音 overlay 中，无需重复
        guard !isPreCapturingHoldToTalk else { return }

        // 如果上一轮还处于“识别中”，这里需要接管 UI：恢复真实音量驱动并停掉假音浪
        isHoldToTalkRecognizing = false
        stopHoldToTalkRecognizingWave()

        isPreCapturingHoldToTalk = true
        isCanceling = false
        recordingTranscript = ""
        audioPower = 0.0
        holdToTalkLatestText = ""
        holdToTalkLatestASRText = ""
        holdToTalkLatestASRIsFinal = false
        holdToTalkAgentMessageId = nil

        holdToTalkGeneration &+= 1
        let gen = holdToTalkGeneration
        holdToTalkASRTask?.cancel()
        holdToTalkASRTask = nil
        holdToTalkSendLoopTask?.cancel()
        holdToTalkSendLoopTask = nil
        holdToTalkReceiveLoopTask?.cancel()
        holdToTalkReceiveLoopTask = nil
        holdToTalkStartupTask?.cancel()
        holdToTalkStartupTask = nil
        holdToTalkVoiceSession = nil
        holdToTalkPlaceholderMessageId = nil
        holdToTalkPCMBacklog = PCMBacklog()
        holdToTalkFullPCM = Data()

        print("[HoldToTalk] press down -> start pre-capture (gen=\(gen))")

        // ✅ 改为后端语音流式识别：本地仅负责采集 PCM，转写由后端返回 asr_result/asr_complete
        holdToTalkStartupTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 1) 建立 WS
                let session = try ChatVoiceInputService.makeSession(contactId: nil)
                // 用户可能已经快速松手/取消：这时不要再继续，也不要插入占位气泡
                let stillValidAfterConnect = await MainActor.run {
                    self.holdToTalkGeneration == gen && self.isPreCapturingHoldToTalk && !self.isAgentTyping
                }
                guard stillValidAfterConnect, !Task.isCancelled else {
                    await session.close()
                    return
                }
                self.holdToTalkVoiceSession = session
                session.start()

                // 2) 开始录 PCM（包含麦克风权限请求与 AudioSession 配置）
                try await self.holdToTalkRecorder.start()
                let stillValidAfterRecorder = await MainActor.run {
                    self.holdToTalkGeneration == gen && self.isPreCapturingHoldToTalk && !self.isAgentTyping
                }
                guard stillValidAfterRecorder, !Task.isCancelled else {
                    await session.close()
                    _ = self.holdToTalkRecorder.stop(discard: true)
                    return
                }

                // 3) 仅在“仍处于预收音态”时插入占位气泡，避免滑动取消后残留“识别中...”
                self.holdToTalkPlaceholderMessageId = self.onSendImmediate?()

                // 4) 启动发送循环：持续 drain PCM bytes -> WS binary
                let backlog = await MainActor.run { self.holdToTalkPCMBacklog }
                self.holdToTalkSendLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    while !Task.isCancelled {
                        // 若这一轮已被替代，停止
                        let stillValid = await MainActor.run { self.holdToTalkGeneration == gen && self.isPreCapturingHoldToTalk }
                        if !stillValid { break }

                        // 1) 从录音器取出新增 PCM，先写入 backlog（无论 WS 是否已就绪）
                        let drained = await MainActor.run { self.holdToTalkRecorder.drainPCMBytes() }
                        if !drained.isEmpty {
                            await MainActor.run { self.appendHoldToTalkFullPCM(drained) }
                        }
                        if let backlog, !drained.isEmpty {
                            await backlog.append(drained)
                        }

                        // 2) 尝试从 backlog flush 到 WS；失败不丢数据，留到下一轮重试
                        guard let backlog else {
                            try? await Task.sleep(nanoseconds: 30_000_000)
                            continue
                        }
                        guard let s = await MainActor.run(body: { self.holdToTalkVoiceSession }) else {
                            try? await Task.sleep(nanoseconds: 30_000_000)
                            continue
                        }

                        // 每轮最多发一小批，避免长循环阻塞其它任务
                        var sentBytesThisTick = 0
                        while sentBytesThisTick < 24_576 { // ~24KB / tick
                            guard let next = await backlog.peek(maxBytes: 4096), !next.isEmpty else { break }
                            do {
                                try await s.sendPCMChunk(next)
                                await backlog.dropFirst(next.count)
                                sentBytesThisTick += next.count
                            } catch {
                                // WS 还没 ready/暂时失败：不 drop，留给下次
                                break
                            }
                        }

                        try? await Task.sleep(nanoseconds: 30_000_000) // ~33fps，更快推送减少“录音态切换后延迟”
                    }
                }

                // 5) 启动接收循环：实时接收 asr_result，并打印（“后台打印用户流式说话转的文字结果”）
                self.holdToTalkReceiveLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    while !Task.isCancelled {
                        let stillValid = await MainActor.run { self.holdToTalkGeneration == gen }
                        if !stillValid { break }
                        guard let s = await MainActor.run(body: { self.holdToTalkVoiceSession }) else { break }
                        do {
                            let ev = try await s.receiveEvent()
                            await MainActor.run {
                                // 若这一轮已被替代，丢弃
                                guard self.holdToTalkGeneration == gen else { return }
                                switch ev {
                                case let .asrResult(text, isFinal):
                                    self.holdToTalkLatestASRText = text
                                    self.holdToTalkLatestASRIsFinal = isFinal
                                    self.holdToTalkLatestText = text
                                    // ✅ 用户气泡实时转写：直接更新占位消息内容（不插“识别中...”）
                                    if let mid = self.holdToTalkPlaceholderMessageId {
                                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            self.onUpdatePlaceholderText?(mid, text)
                                        }
                                    }
                                case let .asrComplete(text, _):
                                    self.holdToTalkLatestASRText = text
                                    self.holdToTalkLatestASRIsFinal = true
                                    self.holdToTalkLatestText = text
                                    if let mid = self.holdToTalkPlaceholderMessageId {
                                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.isEmpty {
                                            self.onRemovePlaceholder?(mid)
                                            self.holdToTalkPlaceholderMessageId = nil
                                        } else {
                                            self.onUpdatePlaceholderText?(mid, text)
                                        }
                                    }
                                case let .taskId(tid):
                                    // ✅ 与普通 chat 一致：task_id 也会回填到 agent message.notes
                                    let chunk: [String: Any] = ["type": "task_id", "task_id": tid]
                                    let out = BackendChatService.parseChunkDelta(chunk)
                                    if !out.isEmpty {
                                        if self.holdToTalkAgentMessageId == nil {
                                            self.holdToTalkAgentMessageId = self.onBeginVoiceAgentMessage?()
                                        }
                                        if let aid = self.holdToTalkAgentMessageId {
                                            self.onApplyVoiceAgentOutput?(aid, out)
                                        }
                                    }
                                case let .other(payload):
                                    // ✅ 语音接口返回与普通 chat 一致：assistant 的 markdown/tool/card 都走同一套结构化回填
                                    let role = (payload["role"] as? String)?.lowercased() ?? ""
                                    let type = (payload["type"] as? String)?.lowercased() ?? ""
                                    let looksLikeAssistantChunk = (
                                        role == "assistant" || role == "agent"
                                        || (role.isEmpty && (type == "markdown" || type == "tool" || type == "card" || type == "task_id"))
                                    )
                                    guard looksLikeAssistantChunk else { break }
                                    let out = BackendChatService.parseChunkDelta(payload)
                                    guard !out.isEmpty else { break }
                                    if self.holdToTalkAgentMessageId == nil {
                                        self.holdToTalkAgentMessageId = self.onBeginVoiceAgentMessage?()
                                    }
                                    if let aid = self.holdToTalkAgentMessageId {
                                        self.onApplyVoiceAgentOutput?(aid, out)
                                    }
                                case .done:
                                    if let aid = self.holdToTalkAgentMessageId {
                                        self.onEndVoiceAgentMessage?(aid)
                                    }
                                    // done 后释放 WS/麦克风资源
                                    Task.detached { [weak self] in
                                        await self?.closeHoldToTalkSession()
                                    }
                                case .cancelled, .stopped:
                                    if let aid = self.holdToTalkAgentMessageId {
                                        self.onEndVoiceAgentMessage?(aid)
                                    }
                                    Task.detached { [weak self] in
                                        await self?.closeHoldToTalkSession()
                                    }
                                case let .error(_, message):
                                    self.onVoiceAgentError?(self.holdToTalkAgentMessageId, message)
                                    Task.detached { [weak self] in
                                        await self?.closeHoldToTalkSession()
                                    }
                                }
                            }
                        } catch {
                            // WS 断开/解析异常：结束接收循环
                            break
                        }
                    }
                }
                await MainActor.run {
                    // 启动成功后清空引用，避免下一轮误 cancel 旧任务
                    if self.holdToTalkGeneration == gen {
                        self.holdToTalkStartupTask = nil
                    }
                }
            } catch {
                // 启动失败：释放资源并清理占位消息
                let placeholderId = self.holdToTalkPlaceholderMessageId
                self.holdToTalkPlaceholderMessageId = nil
                self.holdToTalkVoiceSession = nil
                _ = self.holdToTalkRecorder.stop(discard: true)
                if let placeholderId {
                    self.onRemovePlaceholder?(placeholderId)
                }
            }
        }
    }

    /// 长按被判定/需要展示 UI 时调用：把 overlay 拉起来，但不会重启收音。
    func revealHoldToTalkOverlayIfPossible() {
        guard !isAgentTyping else { return }
        guard isPreCapturingHoldToTalk else { return }
        guard !isRecording else { return }

        // 注意：不建议在 withAnimation 中修改 isRecording，
        // 否则某些布局计算可能会在动画中途发生变化。
        isAnimatingRecordingEntry = true
        isAnimatingRecordingExit = false
        isRecording = true
        isCanceling = false
        // recordingTranscript 维持当前值（可能已经有部分转写）

        // 触感：仅在“真正进入录音态”时给一次确认（按下瞬间已有一次触感，这里更轻一点）
        HapticFeedback.impact(style: .medium, intensity: 0.7)
    }

    /// 轻点/滑动打断时调用：停止预收音且不展示 overlay、不发送任何文字。
    func stopHoldToTalkPreCaptureIfNeeded() {
        guard isPreCapturingHoldToTalk else { return }
        isPreCapturingHoldToTalk = false
        holdToTalkASRTask?.cancel()
        holdToTalkASRTask = nil
        holdToTalkSendLoopTask?.cancel()
        holdToTalkSendLoopTask = nil
        holdToTalkStartupTask?.cancel()
        holdToTalkStartupTask = nil

        let placeholderId = holdToTalkPlaceholderMessageId
        holdToTalkPlaceholderMessageId = nil

        holdToTalkLatestText = ""
        holdToTalkLatestASRText = ""
        holdToTalkLatestASRIsFinal = false
        holdToTalkAgentMessageId = nil
        recordingTranscript = ""
        audioPower = 0.0
        isCanceling = false

        holdToTalkReceiveLoopTask?.cancel()
        holdToTalkReceiveLoopTask = nil
        holdToTalkPCMBacklog = nil
        holdToTalkFullPCM = Data()

        Task.detached { [weak self] in
            guard let self else { return }
            if let s = await MainActor.run(body: { self.holdToTalkVoiceSession }) {
                try? await s.sendCancel()
                await s.close()
            }
            _ = await MainActor.run { self.holdToTalkRecorder.stop(discard: true) }
            await MainActor.run { self.holdToTalkVoiceSession = nil }
        }

        if let placeholderId {
            onRemovePlaceholder?(placeholderId)
        }

        print("[HoldToTalk] pre-capture stopped (no overlay)")
    }
    
    func updateDragLocation(_ location: CGPoint, in bounds: CGRect) {
        // 简单的向上拖动取消判定
        // 如果手指向上移动超过一定距离（例如输入框上方 50pt）
        if location.y < -50 {
            if !isCanceling {
                withAnimation { isCanceling = true }
            }
        } else {
            if isCanceling {
                withAnimation { isCanceling = false }
            }
        }
    }

    // MARK: - Dictation backfill

    /// 把录音转写结果写回输入框：
    /// - 若输入框已有文字：追加（不做手动拼空格/trim，保持原始文本）
    /// - 若输入框为空：直接写入
    private func applyPendingDictationTextToInputIfNeeded() {
        guard let text = pendingDictationTextForInput,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        pendingDictationTextForInput = nil

        if inputText.isEmpty {
            inputText = text
        } else {
            inputText = inputText + text
        }
    }
}

// MARK: - Backend hold-to-talk finalize

private extension ChatInputViewModel {
    /// 松手后：停止本地录音，并告知后端音频发送完毕。
    /// 注意：不会关闭 WS（AI 回复仍会继续从该 WS 返回）。
    func finishBackendHoldToTalkAndSendAudioDone(genAtStop: Int) async {
        // 1) 停止本地 PCM 采集，把尾巴 drain 出来（避免最后一截丢字）
        let remainingPCM = holdToTalkRecorder.stop(discard: false)
        if !remainingPCM.isEmpty {
            appendHoldToTalkFullPCM(remainingPCM)
        }

        // 若这一轮已被替代，直接退出（避免影响新一轮）
        guard holdToTalkGeneration == genAtStop else { return }

        // 1.5) 测试：把完整 PCM 落盘为 wav，并插入一条“用户音频气泡”
        emitHoldToTalkRawAudioBubbleIfNeeded(genAtStop: genAtStop)

        // 2) 发送剩余 PCM + audio_record_done（携带客户端侧最后一次 asr_result 兜底）
        guard let session = holdToTalkVoiceSession else { return }
        do {
            // 把最后一段也塞进 backlog，再统一 flush（避免 sendLoop 取消时丢在“已 drain 未发”的中间态）
            if let backlog = holdToTalkPCMBacklog {
                await backlog.append(remainingPCM)
                try await flushPCMBacklog(backlog, session: session, maxChunkBytes: 4096)
            } else {
                // 一次性发超大 data 可能导致 WS 分片/内存压力，这里做小分块
                try await sendPCMInChunks(remainingPCM, session: session, chunkSize: 4096)
            }
            try await session.sendAudioRecordDone(asrText: holdToTalkLatestASRText, isFinal: holdToTalkLatestASRIsFinal)
        } catch {
            // ignore：后续由服务端 asr_complete/assistant chunk 兜底
        }
    }

    /// 关闭语音 WS 并清理资源（幂等）
    func closeHoldToTalkSession() async {
        // 先抓取引用，避免并发重复 close
        let session = holdToTalkVoiceSession
        holdToTalkVoiceSession = nil

        holdToTalkSendLoopTask?.cancel()
        holdToTalkSendLoopTask = nil
        holdToTalkReceiveLoopTask?.cancel()
        holdToTalkReceiveLoopTask = nil
        holdToTalkStartupTask?.cancel()
        holdToTalkStartupTask = nil
        holdToTalkASRTask?.cancel()
        holdToTalkASRTask = nil

        holdToTalkPCMBacklog = nil
        holdToTalkPlaceholderMessageId = nil
        holdToTalkAgentMessageId = nil
        holdToTalkLatestText = ""
        holdToTalkLatestASRText = ""
        holdToTalkLatestASRIsFinal = false
        recordingTranscript = ""
        isHoldToTalkRecognizing = false
        isPreCapturingHoldToTalk = false

        // 确保麦克风释放（stop() 具备幂等特性）
        _ = holdToTalkRecorder.stop(discard: true)

        if let session {
            await session.close()
        }
    }

    func sendPCMInChunks(_ data: Data, session: ChatVoiceInputService.Session, chunkSize: Int) async throws {
        guard !data.isEmpty else { return }
        let size = max(256, chunkSize)
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            let sub = data.subdata(in: offset..<end)
            try await session.sendPCMChunk(sub)
            offset = end
        }
    }

    func flushPCMBacklog(_ backlog: PCMBacklog, session: ChatVoiceInputService.Session, maxChunkBytes: Int) async throws {
        let chunkSize = max(256, maxChunkBytes)
        while true {
            guard let next = await backlog.peek(maxBytes: chunkSize), !next.isEmpty else { break }
            try await session.sendPCMChunk(next)
            await backlog.dropFirst(next.count)
        }
    }

    func appendHoldToTalkFullPCM(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        holdToTalkFullPCM.append(bytes)
        // 兜底上限：约 4 分钟（32KB/s -> 7.5MB），足够测试且避免极端情况下内存无限增长
        let cap = 8 * 1024 * 1024
        if holdToTalkFullPCM.count > cap {
            holdToTalkFullPCM = Data(holdToTalkFullPCM.suffix(cap))
        }
    }

    func emitHoldToTalkRawAudioBubbleIfNeeded(genAtStop: Int) {
        // 仅在有数据、且仍是同一轮时触发
        guard holdToTalkGeneration == genAtStop else { return }
        guard !holdToTalkFullPCM.isEmpty else { return }

        // 快照 + 清空（避免下一轮串数据）
        let pcmSnapshot = holdToTalkFullPCM
        holdToTalkFullPCM = Data()

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let wav = WAV16PCMWriter.makeWAV(pcm16leMono: pcmSnapshot, sampleRate: 16_000)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("holdtotalk-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                try wav.write(to: url, options: [.atomic])
                await MainActor.run {
                    self.onInsertHoldToTalkRawAudio?(url)
                }
            } catch {
                // 测试功能：写失败就忽略，不影响原链路
            }
        }
    }
}

// MARK: - WAV writer (16-bit PCM, little-endian, mono)

private enum WAV16PCMWriter {
    static func makeWAV(pcm16leMono: Data, sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm16leMono.count)
        let riffChunkSize = UInt32(36) + dataSize

        var out = Data()
        out.reserveCapacity(44 + pcm16leMono.count)

        // RIFF header
        out.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        out.appendLE(riffChunkSize)
        out.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt subchunk
        out.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        out.appendLE(UInt32(16)) // PCM fmt chunk size
        out.appendLE(UInt16(1)) // audio format = 1 (PCM)
        out.appendLE(numChannels)
        out.appendLE(UInt32(sampleRate))
        out.appendLE(byteRate)
        out.appendLE(blockAlign)
        out.appendLE(bitsPerSample)

        // data subchunk
        out.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        out.appendLE(dataSize)
        out.append(pcm16leMono)
        return out
    }
}

private extension Data {
    mutating func appendLE(_ v: UInt16) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ v: UInt32) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
}

// MARK: - PCM backlog actor

/// 线程安全的 PCM 待发送缓冲，解决 WS 初期 send() 失败导致的“前面漏字”。
private actor PCMBacklog {
    private var data = Data()

    func append(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        data.append(bytes)
        // 兜底上限：避免极端网络差导致内存无限增长（约 10 秒 32KB/s -> 320KB）
        let cap = 512 * 1024
        if data.count > cap {
            // 保留最新部分（更贴近用户当前说话），同时防止 OOM
            // 注意：Data 经过 slice/suffix 后 startIndex 可能不是 0；
            // 这里强制生成“新的 Data”，避免后续用 Range(Int) 取子数据触发越界 trap。
            data = Data(data.suffix(cap))
        }
    }

    /// 取出头部一段（不移除）；若为空返回 nil。
    func peek(maxBytes: Int) -> Data? {
        guard !data.isEmpty else { return nil }
        let n = max(0, maxBytes)
        if n <= 0 { return nil }
        let end = min(n, data.count)
        // Data.startIndex 不一定是 0（尤其是 slice 后），必须用 Index 计算范围
        let endIndex = data.index(data.startIndex, offsetBy: end)
        return data.subdata(in: data.startIndex..<endIndex)
    }

    func dropFirst(_ count: Int) {
        guard count > 0, !data.isEmpty else { return }
        let n = min(count, data.count)
        data.removeFirst(n)
    }
}
