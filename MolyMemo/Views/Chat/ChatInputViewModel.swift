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
    var onUpdateAndSend: ((UUID, String) -> Void)?  // 更新消息内容并触发AI对话
    var onRemovePlaceholder: ((UUID) -> Void)?  // 删除占位消息（用于转录失败或结果为空）
    var onBoxTap: (() -> Void)?
    var onStopGenerator: (() -> Void)?
    
    // MARK: - Internal
    private let holdToTalkSpeechRecognizer = SpeechRecognizer()
    private var holdToTalkGeneration: Int = 0
    private var holdToTalkASRTask: Task<Void, Never>?
    private var holdToTalkRecognizingWaveTask: Task<Void, Never>?
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
    
    // MARK: - Computed Properties
    
    /// 是否有内容（文字或图片）
    var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
    }
    
    // MARK: - Methods
    
    init() {
        holdToTalkSpeechRecognizer.requestAuthorization()

        // 用真实收音 level 驱动 UI（来自 SFSpeechRecognizer 的输入 buffer）
        holdToTalkSpeechRecognizer.$audioLevel
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

        // 取消：立即 stop + 退场（不进入识别态）
        guard shouldSend else {
            holdToTalkSpeechRecognizer.stopRecording()
            holdToTalkLatestText = ""
            recordingTranscript = ""
            isHoldToTalkRecognizing = false
            beginHoldToTalkExit()
            return
        }

        // 关键：先把 UI 立刻切到“识别中”，并开始波动；录音 stop / 编码 / 上传放到下一帧去做
        isHoldToTalkRecognizing = true
        recordingTranscript = "识别中..."
        startHoldToTalkRecognizingWave()

        holdToTalkASRTask = Task { [weak self] in
            guard let self else { return }
            // 让 SwiftUI 先把“识别中…”渲染出来，再做 stop（AudioSession 归还/识别收尾可能会卡顿）
            await Task.yield()
            // 停止本地语音识别并等待 final，尽量避免漏字
            let text = await self.holdToTalkSpeechRecognizer.stopRecordingAndWaitForFinalText(timeoutSeconds: 1.2)
            guard !Task.isCancelled else { return }

            // 如果期间又开始了新一轮按住说话，就不要把旧结果发出去
            guard self.holdToTalkGeneration == genAtStop else {
                // 新一轮录音会接管 UI；这里仅清理本轮识别锁
                self.isHoldToTalkRecognizing = false
                self.stopHoldToTalkRecognizingWave()
                return
            }

            // 只用 trim 判空；发送内容保持“原始文本”
            let rawText = text
            let isEffectivelyEmpty = rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !isEffectivelyEmpty {
                self.recordingTranscript = ""
                self.stopHoldToTalkRecognizingWave()
                self.isHoldToTalkRecognizing = false
                self.beginHoldToTalkExit()
                // 让 UI 先完成一帧退场/布局，再发消息，避免“卡顿一下”
                Task { @MainActor in
                    await Task.yield()
                    self.onSend?(rawText, nil)
                }
            } else {
                self.recordingTranscript = ""
                self.stopHoldToTalkRecognizingWave()
                self.isHoldToTalkRecognizing = false
                self.beginHoldToTalkExit()
            }
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
        recordingTranscript = "" // overlay 当前不展示 transcript，但留着调试
        audioPower = 0.0
        holdToTalkLatestText = ""

        holdToTalkGeneration &+= 1
        let gen = holdToTalkGeneration
        holdToTalkASRTask?.cancel()
        holdToTalkASRTask = nil

        print("[HoldToTalk] press down -> start pre-capture (gen=\(gen))")
        // 直接启动 iOS 本地语音识别（内部已用独立队列处理 AudioSession/Engine）
        holdToTalkSpeechRecognizer.startRecording { [weak self] text in
            guard let self else { return }
            // 若这一轮已被新一轮替代，丢弃回调
            guard self.holdToTalkGeneration == gen else { return }
            self.holdToTalkLatestText = text
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
        holdToTalkSpeechRecognizer.stopRecording()
        holdToTalkLatestText = ""
        recordingTranscript = ""
        audioPower = 0.0
        isCanceling = false
        print("[HoldToTalk] pre-capture stopped (no overlay) -> deleted file")
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
