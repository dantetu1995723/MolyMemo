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
    @Published var isCanceling: Bool = false
    @Published var audioPower: CGFloat = 0.0
    @Published var recordingTranscript: String = ""
    @Published var inputFrame: CGRect = .zero
    
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
        withAnimation {
            selectedImage = nil
            selectedPhotoItem = nil
            showSuggestions = false // Hide suggestions when image is removed
        }
    }
    
    func toggleMenu() {
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
        // 简单模拟录音开始
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isRecording = true
            isCanceling = false
            recordingTranscript = "正在聆听..." // Placeholder
        }
        
        // 模拟声波跳动
        powerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.audioPower = CGFloat.random(in: 0.1...0.8)
            }
        }
    }
    
    func stopRecording() {
        withAnimation {
            isRecording = false
            powerTimer?.invalidate()
            powerTimer = nil
            audioPower = 0
        }
        
        if !isCanceling {
            // 模拟发送录音（这里转换为文字发送）
            let mockText = "我上周说明天要和谁约饭来着？请你帮我查一下"
            // 实际上应该发送音频或转换后的文字
            // 这里为了演示，延迟一下模拟STT完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onSend?(mockText, nil)
            }
        }
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
