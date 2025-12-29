import SwiftUI
import PhotosUI

struct ChatInputView: View {
    @ObservedObject var viewModel: ChatInputViewModel
    var namespace: Namespace.ID
    
    @FocusState private var isFocused: Bool
    
    // 手势状态
    @State private var isPressing = false
    @State private var pressStartTime: Date?
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
            pressStartTime = nil
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
    }
    
    // 输入框容器组件
    @ViewBuilder
    private var inputContainer: some View {
        let isLocked = viewModel.isAgentTyping
        
        VStack(alignment: .leading, spacing: 0) {
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
        .background(
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
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .inset(by: 0.5)
                .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 1)
        )
        // 手势处理
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
    }
    
    // MARK: - Gesture Logic
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        // AI 正在输入时：整体锁定，禁止长按录音
        guard !viewModel.isAgentTyping else { return }
        
        // 排除按钮区域，避免干扰按钮点击
        let startX = value.startLocation.x
        // 加号按钮区域 (左侧约 52px)
        if startX < 52 { return }
        // 右侧按钮区域（Stop 或 Send）
        // 这里同样不要用 hasContent，避免发送后状态变化导致误判
        let inputWidth = viewModel.inputFrame.width
        if inputWidth > 0, startX > (inputWidth - 52) { return }
        
        // 记录一次用户触摸（用于允许随后的聚焦）
        if !isPressing {
            lastUserInteractionAt = Date()
        }
        
        // 检测是否是新点击
        if !isPressing {
            isPressing = true
            pressStartTime = Date()
            
            // 延迟触发录音，避免普通点击触发录音
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if isPressing, let startTime = pressStartTime, Date().timeIntervalSince(startTime) >= 0.3 {
                    // 触发录音
                    if !viewModel.isRecording {
                        HapticFeedback.medium()
                        viewModel.startRecording()
                    }
                }
            }
        }
        
        // 如果正在录音，更新拖拽位置以检测取消
        if viewModel.isRecording {
            let dragPoint = CGPoint(x: value.translation.width, y: value.translation.height)
            viewModel.updateDragLocation(dragPoint, in: .zero)
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        // AI 正在输入时：整体锁定，结束手势即可
        guard !viewModel.isAgentTyping else {
            isPressing = false
            pressStartTime = nil
            return
        }
        
        // 排除按钮区域
        let startX = value.startLocation.x
        // 注意：这里不要用 hasContent 来判断右侧按钮区域。
        // 因为“发送”会立刻清空 inputText，导致 hasContent 在手势 ended 时变为 false，
        // 从而误把“点发送按钮”当成“点空白区域”，进而把输入框又 focus 回来。
        let inputWidth = viewModel.inputFrame.width
        let isInRightButtonArea = (inputWidth > 0) ? (startX > (inputWidth - 52)) : false
        if startX < 52 || isInRightButtonArea {
            isPressing = false
            pressStartTime = nil
            return
        }

        isPressing = false
        pressStartTime = nil
        
        if viewModel.isRecording {
            if viewModel.isCanceling {
                viewModel.cancelRecording()
            } else {
                viewModel.stopRecording()
            }
        } else {
            // 如果只是轻点中间区域，且没有聚焦，则聚焦输入框
            if !isFocused && viewModel.inputText.isEmpty && viewModel.selectedImage == nil {
                lastUserInteractionAt = Date()
                isFocused = true
            }
        }
    }
}
