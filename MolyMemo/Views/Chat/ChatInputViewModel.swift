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
    var onBoxTap: (() -> Void)?
    var onStopGenerator: (() -> Void)?
    
    // MARK: - Internal
    private let speechRecognizer = SpeechRecognizer()
    private var cancellables = Set<AnyCancellable>()
    /// 按住说话：按下瞬间就开始“预收音/预转写”，但不立刻展示 overlay（避免轻点聚焦时闪一下 UI）
    private var isPreCapturingHoldToTalk: Bool = false
    /// 录音结束后待回填到输入框的转写文本（用于：输入框尚未出现/尚在退场动画时延迟写回）
    private var pendingDictationTextForInput: String?
    
    // MARK: - Computed Properties
    
    /// 是否有内容（文字或图片）
    var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
    }
    
    // MARK: - Methods
    
    init() {
        // 用真实收音 level 驱动 UI（不做 demo 模拟）
        speechRecognizer.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioPower = CGFloat(level)
            }
            .store(in: &cancellables)
    }
    
    func sendMessage() {
        // AI 输入过程中：输入区除“中止”外全部禁用
        guard !isAgentTyping else { return }
        guard hasContent else { return }
        
        let textToSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSend?(textToSend, selectedImage)
        
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
        
        speechRecognizer.stopRecording()
        
        // 先走“球 -> 输入框”的逆向动画，结束后再真正收起 overlay
        withAnimation(.easeInOut(duration: 0.16)) {
            isAnimatingRecordingExit = true
            audioPower = 0
        }
        
        guard !isCanceling else { return }
        
        // 没有接收到声音 / 没有识别结果：不写回任何默认文字
        let text = recordingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "正在聆听..." else { return }
        // 不自动发送：先缓存，等输入框出现（overlay 退场结束）后再写回到 inputText
        pendingDictationTextForInput = text
    }
    
    /// 由 overlay 的逆向动画结束回调触发：真正收起 overlay 并恢复输入框
    func finishRecordingOverlayDismissal() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isRecording = false
            isAnimatingRecordingEntry = false
            isAnimatingRecordingExit = false
            isCanceling = false
            audioPower = 0
        }
        applyPendingDictationTextToInputIfNeeded()
    }
    
    func cancelRecording() {
        withAnimation {
            isCanceling = true
        }
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

        isPreCapturingHoldToTalk = true
        isCanceling = false
        recordingTranscript = "" // 先留空，overlay 出现时会显示“正在聆听...”
        audioPower = 0.0

        // 请求权限（只会在未授权/未决定时弹窗）
        speechRecognizer.requestAuthorization()

        // 开始真实收音 + 转写（partial results）
        speechRecognizer.startRecording { [weak self] text in
            guard let self = self else { return }
            // 只有在“预收音”或“已展示 overlay”阶段才接收回调，避免 stop 后又回写 UI
            guard self.isPreCapturingHoldToTalk || self.isRecording else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.recordingTranscript = trimmed
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
    }

    /// 轻点/滑动打断时调用：停止预收音且不展示 overlay、不发送任何文字。
    func stopHoldToTalkPreCaptureIfNeeded() {
        guard isPreCapturingHoldToTalk else { return }
        isPreCapturingHoldToTalk = false
        speechRecognizer.stopRecording()
        recordingTranscript = ""
        audioPower = 0.0
        isCanceling = false
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
    /// - 若输入框已有文字：追加（用空格分隔，避免覆盖用户已输入内容）
    /// - 若输入框为空：直接写入
    private func applyPendingDictationTextToInputIfNeeded() {
        guard let text = pendingDictationTextForInput?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return }
        pendingDictationTextForInput = nil

        let existing = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            inputText = text
        } else {
            inputText = existing + " " + text
        }
    }
}
