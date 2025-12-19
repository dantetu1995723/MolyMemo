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
    @Published var isCanceling: Bool = false
    @Published var audioPower: CGFloat = 0.0
    @Published var recordingTranscript: String = ""
    @Published var inputFrame: CGRect = .zero
    @Published var toolboxFrame: CGRect = .zero
    
    // MARK: - UI State
    @Published var showMenu: Bool = false
    @Published var isInputFocused: Bool = false
    @Published var showSuggestions: Bool = false
    @Published var showCamera: Bool = false
    
    // MARK: - Agent State
    @Published var isAgentTyping: Bool = false
    
    // MARK: - Actions
    var onSend: ((String, UIImage?) -> Void)?
    var onBoxTap: (() -> Void)?
    var onStopGenerator: (() -> Void)?
    
    // MARK: - Internal
    private var audioRecorder: AVAudioRecorder?
    private var powerTimer: Timer?
    
    // MARK: - Demo waveform simulation (明确区分“收音/未收音”)
    private var isSimulatingSpeech: Bool = false
    private var simulatedStateUntil: Date = .distantPast
    
    // MARK: - Computed Properties
    
    /// 是否有内容（文字或图片）
    var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
    }
    
    /// 是否应该显示发送按钮
    var shouldShowSendButton: Bool {
        hasContent || isInputFocused
    }
    
    // MARK: - Methods
    
    func sendMessage() {
        // AI 输入过程中：输入区除“中止”外全部禁用
        guard !isAgentTyping else { return }
        guard hasContent else { return }
        
        let textToSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSend?(textToSend, selectedImage)
        
        // Reset State
        withAnimation {
            inputText = ""
            selectedImage = nil
            selectedPhotoItem = nil
            showSuggestions = false
        }
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
            if showMenu {
                isInputFocused = false // Dismiss keyboard when menu opens
            }
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
        // AI 输入过程中：输入区除“中止”外全部禁用
        guard !isAgentTyping else { return }
        
        // 记录当前位置
        // 注意：不建议在 withAnimation 中修改 isRecording，
        // 否则某些布局计算可能会在动画中途发生变化。
        isAnimatingRecordingEntry = true
        isRecording = true 
        isCanceling = false
        recordingTranscript = "正在聆听..."
        audioPower = 0.0 // 初始静止（未收音）
        
        // Demo：用“段落式”的说话/静音切换，确保 UI 有明确的静止区间
        isSimulatingSpeech = false
        simulatedStateUntil = Date().addingTimeInterval(Double.random(in: 0.4...1.2))
        
        powerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let now = Date()
                
                if now >= self.simulatedStateUntil {
                    // 在“说话”和“静音”之间切换，并给下一段随机时长
                    self.isSimulatingSpeech.toggle()
                    if self.isSimulatingSpeech {
                        self.simulatedStateUntil = now.addingTimeInterval(Double.random(in: 0.7...2.0))
                    } else {
                        self.simulatedStateUntil = now.addingTimeInterval(Double.random(in: 0.8...2.4))
                    }
                }
                
                if self.isSimulatingSpeech {
                    // 说话：更大的振幅范围
                    self.audioPower = CGFloat.random(in: 0.18...0.85)
                } else {
                    // 静音：彻底归零（对应“未收音/无有效声音”）
                    self.audioPower = 0
                }
            }
        }
    }
    
    func stopRecording() {
        withAnimation {
            isRecording = false
            isAnimatingRecordingEntry = false
            powerTimer?.invalidate()
            powerTimer = nil
            audioPower = 0
        }
        
        guard !isCanceling else { return }
        
        // 没有接收到声音 / 没有识别结果：不发送任何默认文字
        let text = recordingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "正在聆听..." else { return }
        onSend?(text, nil)
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
}
