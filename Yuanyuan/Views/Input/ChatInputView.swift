import SwiftUI
import PhotosUI

struct ChatInputView: View {
    @ObservedObject var viewModel: ChatInputViewModel
    var namespace: Namespace.ID
    
    @FocusState private var isFocused: Bool
    
    // 手势状态
    @State private var isPressing = false
    @State private var pressStartTime: Date?
    
    var body: some View {
        VStack(spacing: 12) {
            // 1. Suggestions (Floating) - Only when NO image is selected
            if viewModel.showSuggestions && viewModel.selectedImage == nil {
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
                .frame(minHeight: 44)
                
                // Right: Always Toolbox Button (Only when NOT typing and NO image)
                if !viewModel.isRecording && viewModel.inputText.isEmpty && viewModel.selectedImage == nil {
                    ToolboxButton(onTap: { viewModel.onBoxTap?() })
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, 16)
            
            // 3. Action Menu
            if viewModel.showMenu {
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
        // Bind Focus State
        .onChange(of: isFocused) { _, focused in
            viewModel.isInputFocused = focused
            if focused {
                withAnimation { viewModel.showMenu = false }
            }
        }
        .onChange(of: viewModel.isInputFocused) { _, focused in
            isFocused = focused
        }
        // Handle Photo Selection
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
            viewModel.handlePhotoSelection(newItem)
        }
    }
    
    // 输入框容器组件
    private var inputContainer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 选中的图片展示区 (图中标注间距 12)
            if let image = viewModel.selectedImage {
                VStack(alignment: .leading, spacing: 12) {
                    AttachmentPreview(image: image, onDelete: viewModel.removeImage)
                        .padding(.top, 12)
                    
                    // 建议栏
                    if viewModel.showSuggestions {
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
                    .padding(.leading, 8)
                    .padding(.bottom, 6)
                } else {
                    // 有图片时，左侧留出间距 (图中标注 12)
                    Spacer().frame(width: 12)
                }
                
                TextField("发送消息或按住说话", text: $viewModel.inputText, axis: .vertical)
                    .font(.system(size: 16))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .lineLimit(3, reservesSpace: false) // 限制最大3行，超过后滚动
                    .focused($isFocused)
                
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
                    .padding(.bottom, 6)
                    .transition(.scale.combined(with: .opacity))
                } else if !viewModel.inputText.isEmpty || viewModel.selectedImage != nil {
                    Button(action: viewModel.sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.blue))
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
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
        // 排除按钮区域，避免干扰按钮点击
        let startX = value.startLocation.x
        // 加号按钮区域 (左侧约 44px)
        if startX < 44 { return }
        // 发送按钮区域 (右侧约 44px)
        if !viewModel.inputText.isEmpty && startX > (viewModel.inputFrame.width - 44) { return }
        
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
        // 排除按钮区域
        let startX = value.startLocation.x
        if startX < 44 || (!viewModel.inputText.isEmpty && startX > (viewModel.inputFrame.width - 44)) {
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
                isFocused = true
            }
        }
    }
}
