import SwiftUI
import PhotosUI

struct ChatInputView: View {
    @ObservedObject var viewModel: ChatInputViewModel
    var namespace: Namespace.ID
    
    @FocusState private var isFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    
    // 手势状态
    @State private var isPressing = false
    @State private var pressBeganAt: Date?
    @State private var didMoveDuringPress = false
    // 仅允许“用户触摸触发”的聚焦：用于拦截 SwiftUI/系统在状态切换时的自动 focus
    @State private var lastUserInteractionAt: Date?
    
    var body: some View {
        let isLocked = viewModel.isAgentTyping
        
        VStack(spacing: 12) {
            // 1. Suggestions (Floating) - Only when NO image is selected
            if viewModel.showSuggestions && viewModel.selectedImage == nil && !isLocked {
                SuggestionBar(onSuggestionTap: { suggestion in
                    viewModel.sendSuggestion(suggestion)
                })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // 2. Input Bar (Input field + Toolbox button)
            HStack(alignment: .bottom, spacing: 10) {
                // Left: Input Field Container (Contains + and Send Button)
                ZStack(alignment: .bottom) {
                    inputContainer
                        .opacity(viewModel.isRecording ? 0 : 1)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                
                // Right: Toolbox Button
                if !isLocked && viewModel.inputText.isEmpty && viewModel.selectedImage == nil {
                    ToolboxButton(onTap: { viewModel.onBoxTap?() })
                        .opacity(viewModel.isRecording ? 0 : 1)
                        .onDisappear {
                            // 隐藏时清空 frame，避免录音动画误认存在外部按钮
                            viewModel.toolboxFrame = .zero
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        DispatchQueue.main.async {
                                            viewModel.toolboxFrame = geo.frame(in: .global)
                                        }
                                    }
                                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                        DispatchQueue.main.async {
                                            viewModel.toolboxFrame = newFrame
                                        }
                                    }
                            }
                        )
                        .disabled(isLocked || viewModel.isRecording)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, 16)
            
            // 3. Action Menu
            if viewModel.showMenu && !isLocked {
                ActionMenu(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, 12)
        .background(Color(hex: "F7F8FA"))
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: viewModel.showMenu)
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: viewModel.showSuggestions)
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: viewModel.selectedImage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
        .onChange(of: viewModel.isAgentTyping) { _, isTyping in
            // AI 输入时：除“中止”外全部禁用，主动收起键盘/菜单/建议，并打断长按录音手势
            guard isTyping else { return }
            isPressing = false
            pressBeganAt = nil
            didMoveDuringPress = false
            if isFocused { isFocused = false }
            if viewModel.isInputFocused { viewModel.isInputFocused = false }
            if viewModel.showMenu {
                withAnimation { viewModel.showMenu = false }
            }
            if viewModel.showSuggestions {
                withAnimation { viewModel.showSuggestions = false }
            }
        }
        // Bind Focus State
        .onChange(of: isFocused) { _, focused in
            // 全手动 focus：如果没有“最近的用户触摸”，则拒绝自动聚焦
            if focused {
                let now = Date()
                let isUserInitiated = lastUserInteractionAt.map { now.timeIntervalSince($0) < 0.35 } ?? false
                if !isUserInitiated {
                    // 用 async 避免在同一轮更新里和 SwiftUI 争抢焦点产生抖动
                    DispatchQueue.main.async {
                        self.isFocused = false
                        self.viewModel.isInputFocused = false
                    }
                    return
                }
            }
            viewModel.isInputFocused = focused
            if focused {
                withAnimation { viewModel.showMenu = false }
            }
        }
        // 只允许“程序控制失焦”；聚焦必须由用户触发（见上方拦截逻辑）
        .onChange(of: viewModel.isInputFocused) { _, focused in
            if !focused, isFocused {
                isFocused = false
            }
        }
        // Handle Photo Selection
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
            viewModel.handlePhotoSelection(newItem)
        }
        .onChange(of: scenePhase) { _, phase in
            // 系统上滑回桌面/切后台时，手势的 ended 有时不会可靠回调；
            // 这里兜底结束“按住说话”的状态，防止延迟触发误开录音。
            if phase != .active {
                forceEndHoldToTalk()
            }
        }
    }
    
    // 输入框容器组件
    @ViewBuilder
    private var inputContainer: some View {
        let isLocked = viewModel.isAgentTyping
        
        // 只在“输入框未聚焦且为空”的状态启用按住说话，避免和正常滚动/系统返回桌面手势冲突。
        // 关键：录音开始后不要把手势移除，否则 SwiftUI 会取消正在进行的 long-press，
        // 触发 pressing(false) 从而立刻 stopRecording，造成“蓝色球闪一下又退回”的问题。
        let holdToTalkEnabled =
            !isLocked &&
            !isFocused &&
            viewModel.inputText.isEmpty &&
            viewModel.selectedImage == nil
        
        let base = VStack(alignment: .leading, spacing: 0) {
            // 选中的图片展示区 (图中标注间距 12)
            if let image = viewModel.selectedImage {
                VStack(alignment: .leading, spacing: 12) {
                    AttachmentPreview(image: image, onDelete: viewModel.removeImage)
                        .allowsHitTesting(!isLocked)
                        .opacity(isLocked ? 0.6 : 1)
                        .padding(.top, 12)
                    
                    // 建议栏
                    if viewModel.showSuggestions && !isLocked {
                        SuggestionBar(onSuggestionTap: { suggestion in
                            viewModel.sendSuggestion(suggestion)
                        })
                    }
                    
                    // 分割线 (图中细线)
                    Divider()
                        .background(Color.black.opacity(0.05))
                }
                .padding(.horizontal, 12) // 图中标注左右 12
            }
            
            // 文本输入区域
            HStack(alignment: .bottom, spacing: 0) {
                // 左侧加号：仅在没有图片时显示
                if viewModel.selectedImage == nil {
                    Button(action: {
                        viewModel.toggleMenu()
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(Color(hex: "666666"))
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(viewModel.showMenu ? 45 : 0))
                    }
                    .disabled(isLocked)
                    .opacity(isLocked ? 0.4 : 1)
                    .padding(.leading, 8)
                    .padding(.bottom, 10)
                } else {
                    // 有图片时，左侧留出间距 (图中标注 12)
                    Spacer().frame(width: 12)
                }
                
                // 关键：当输入框未聚焦且为空时，我们用外层手势承接“长按录音”，
                // 禁止 TextField 自己接收触摸，避免系统的文字长按放大镜（你看到的水滴玻璃球）。
                let interceptTextFieldTouches =
                    !isFocused &&
                    viewModel.inputText.isEmpty &&
                    viewModel.selectedImage == nil &&
                    !viewModel.isRecording &&
                    !isLocked
                
                TextField("发送消息或按住说话", text: $viewModel.inputText, axis: .vertical)
                    .font(.system(size: 16))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                    .lineLimit(3, reservesSpace: false) // 限制最大3行，超过后滚动
                    .focused($isFocused)
                    .allowsHitTesting(!interceptTextFieldTouches)
                    .disabled(isLocked)
                    .opacity(isLocked ? 0.6 : 1)
                
                // Inside right: Action Button (Stop OR Send)
                if viewModel.isAgentTyping {
                    Button(action: {
                        HapticFeedback.light()
                        viewModel.onStopGenerator?()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 24, height: 24)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(.white)
                                .frame(width: 8, height: 8)
                        }
                        .frame(width: 32, height: 32)
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 10)
                } else if !viewModel.inputText.isEmpty || viewModel.selectedImage != nil {
                    Button(action: viewModel.sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.blue))
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .modifier(InputContainerFrameReporter(viewModel: viewModel))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .inset(by: 0.5)
                .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 1)
        )
        
        if holdToTalkEnabled {
            base
                // 真正的长按：最大移动距离限制可以有效避免“上滑回桌面/关掉界面”时误触发录音
                .onLongPressGesture(
                    minimumDuration: 0.3,
                    maximumDistance: 12,
                    pressing: { isDown in
                        handleHoldToTalkPressingChanged(isDown)
                    },
                    perform: {
                        handleHoldToTalkLongPressRecognized()
                    }
                )
                // 仅用于：
                // - 识别“按住过程中发生了明显移动”，避免把滑动当成轻点去 focus
                // - 录音时用于“上划取消”的实时判定
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            handleHoldToTalkDragChanged(value)
                        }
                        .onEnded { _ in
                            if !isPressing {
                                didMoveDuringPress = false
                            }
                        }
                )
        } else {
            base
        }
    }
    
    // MARK: - Gesture Logic
    
    private func handleHoldToTalkPressingChanged(_ isDown: Bool) {
        guard !viewModel.isAgentTyping else { return }
        
        if isDown {
            // 记录一次用户触摸（用于允许随后的聚焦）
            lastUserInteractionAt = Date()
            isPressing = true
            pressBeganAt = Date()
            didMoveDuringPress = false
            return
        }
        
        // 手指抬起：结束按压
        isPressing = false
        let beganAt = pressBeganAt
        pressBeganAt = nil
        
        if viewModel.isRecording {
            // 录音结束：根据是否处于“取消”状态决定 stop / cancel
            if viewModel.isCanceling {
                viewModel.cancelRecording()
            } else {
                viewModel.stopRecording()
            }
            return
        }
        
        // 非录音：把“轻点中间区域”当作 focus 输入框（但滑动/明显移动不算轻点）
        if !didMoveDuringPress,
           !isFocused,
           viewModel.inputText.isEmpty,
           viewModel.selectedImage == nil
        {
            let isQuickTap = beganAt.map { Date().timeIntervalSince($0) < 0.25 } ?? true
            if isQuickTap {
                lastUserInteractionAt = Date()
                isFocused = true
            }
        }
        
        didMoveDuringPress = false
    }
    
    private func handleHoldToTalkLongPressRecognized() {
        guard !viewModel.isAgentTyping else { return }
        guard !isFocused else { return }
        guard viewModel.inputText.isEmpty, viewModel.selectedImage == nil else { return }
        guard !viewModel.isRecording else { return }
        
        HapticFeedback.medium()
        viewModel.startRecording()
    }
    
    private func handleHoldToTalkDragChanged(_ value: DragGesture.Value) {
        guard !viewModel.isAgentTyping else { return }
        
        // 只要按压中发生了明显移动，就不再把它当成“轻点 focus”
        if isPressing && !viewModel.isRecording {
            didMoveDuringPress = true
        }
        
        // 如果正在录音，更新拖拽位置以检测取消
        if viewModel.isRecording {
            let dragPoint = CGPoint(x: value.translation.width, y: value.translation.height)
            viewModel.updateDragLocation(dragPoint, in: .zero)
        }
    }
    
    private func forceEndHoldToTalk() {
        isPressing = false
        pressBeganAt = nil
        didMoveDuringPress = false
        
        // 进入后台/非活跃：停止录音但不要发送
        if viewModel.isRecording {
            viewModel.isCanceling = true
            viewModel.stopRecording()
        }
    }
}

// MARK: - Helpers

/// 把输入框 frame 上报给 VM（避免把这段逻辑散落在主 view 里导致类型推断变慢）
private struct InputContainerFrameReporter: ViewModifier {
    @ObservedObject var viewModel: ChatInputViewModel
    
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(hex: "F7F8FA"))
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                DispatchQueue.main.async {
                                    viewModel.inputFrame = geo.frame(in: .global)
                                }
                            }
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                DispatchQueue.main.async {
                                    viewModel.inputFrame = newFrame
                                }
                            }
                    }
                )
        )
    }
}
