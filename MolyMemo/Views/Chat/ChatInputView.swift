import SwiftUI
import PhotosUI
import UIKit

// MARK: - Layout Preference
/// ChatInputView 的“整体高度”（包含建议条/输入框/附件面板），用于让 ChatView 动态给聊天列表做底部避让。
struct ChatInputTotalHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ChatInputView: View {
    @ObservedObject var viewModel: ChatInputViewModel
    var namespace: Namespace.ID
    
    @FocusState private var isFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    
    // 输入框高度：随内容增长到上限后内部滚动（不更换组件）
    @State private var inputTextHeight: CGFloat = 52
    @State private var inputTextWidth: CGFloat = 0
    
    // 手势状态
    @State private var isPressing = false
    @State private var pressBeganAt: Date?
    @State private var didMoveDuringPress = false
    /// 按住说话：按下立刻预收音，稍后再展示 overlay（避免轻点聚焦闪 UI）
    @State private var pendingHoldToTalkTask: Task<Void, Never>?
    
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
                    ToolboxButton(onTap: {
                        DebugProbe.log("ToolboxButton tapped")
                        viewModel.onBoxTap?()
                    })
                        .opacity(viewModel.isRecording ? 0 : 1)
                        .onDisappear {
                            // 隐藏时清空 frame，避免录音动画误认存在外部按钮
                            viewModel.toolboxFrame = .zero
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        // 输入框聚焦时不需要 toolbox frame（录音动画也不会触发），
                                        // 避免键盘动画期间 global frame 高频变化导致 UI 自激刷新。
                                        guard !isFocused else { return }
                                        let f = normalizeFrame(geo.frame(in: .global), scale: displayScale)
                                        DispatchQueue.main.async {
                                            if viewModel.toolboxFrame != f {
                                                viewModel.toolboxFrame = f
                                            }
                                        }
                                    }
                                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                        // 同上：聚焦时停止上报，且做像素取整 + 变更才写入，避免高频状态更新卡死主线程。
                                        guard !isFocused else { return }
                                        let f = normalizeFrame(newFrame, scale: displayScale)
                                        DispatchQueue.main.async {
                                            if viewModel.toolboxFrame != f {
                                                viewModel.toolboxFrame = f
                                            }
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
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ChatInputTotalHeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: viewModel.showMenu)
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: viewModel.showSuggestions)
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: viewModel.selectedImage)
        .animation(.easeInOut(duration: 0.12), value: viewModel.isRecording)
        .onAppear {
            // 预热触感引擎，避免首次/前几次长按“安静”
            HapticFeedback.warmUp()
        }
        .onChange(of: viewModel.isAgentTyping) { _, isTyping in
            DebugProbe.log("ChatInputView.isAgentTyping -> \(isTyping)")
            // AI 输入时：除“中止”外全部禁用，主动收起键盘/菜单/建议，并打断长按录音手势
            guard isTyping else { return }
            isPressing = false
            pressBeganAt = nil
            didMoveDuringPress = false
            if isFocused { isFocused = false }
            if viewModel.showMenu {
                withAnimation { viewModel.showMenu = false }
            }
            if viewModel.showSuggestions {
                withAnimation { viewModel.showSuggestions = false }
            }
        }
        // Bind Focus State
        .onChange(of: isFocused) { _, focused in
            DebugProbe.log("ChatInputView.isFocused -> \(focused)")
            if focused {
                // 关键兜底：聚焦输入框时，必须立刻终止“按住说话”的 tracking/预收音，
                // 否则可能因为 hitTesting 关闭导致手势 ended 不可靠，进而出现麦克风占用（灵动岛橙点）。
                forceEndHoldToTalk()
                withAnimation { viewModel.showMenu = false }
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
                        // 打开菜单前先收起键盘（根治：避免通过 VM 回写焦点导致循环）
                        if isFocused { isFocused = false }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                
                // 当输入框未聚焦且为空时：
                // - 用“覆盖在 TextField 上方”的手势面板承接“按住说话/轻点聚焦”
                // - 禁用 TextField 本体 hitTesting，避免系统文字长按放大镜干扰
                //
                // 注意：不能把手势挂在 TextField.background 上再对 TextField allowsHitTesting(false)，
                // 否则背景也会一起失效（导致点击聚焦/长按录音都失灵）。
                // 手势面板需要在两种状态可命中：
                // 1) 未录音且满足 holdToTalkEnabled：用于“轻点聚焦 / 按住录音”
                // 2) 已进入录音：用于“松手结束 / 上划取消”
                let gestureOverlayEnabled =
                    (!isLocked) && (holdToTalkEnabled || viewModel.isRecording)
                
                ZStack {
                    TextField("发送消息或按住说话", text: $viewModel.inputText, axis: .vertical)
                        .font(.system(size: 16))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .frame(height: inputTextHeight)
                        .lineLimit(3, reservesSpace: false) // 限制最大3行，超过后滚动
                        .onChange(of: viewModel.inputText) { oldValue, newValue in
                            // 多行 TextField 默认会把回车当换行；这里把“尾部回车”转成“发送”。
                            // 只处理尾部 \n，避免误伤粘贴的多行文本/中间换行。
                            guard !viewModel.isAgentTyping else { return }
                            guard newValue.hasSuffix("\n") else { return }
                            
                            var cleaned = newValue
                            while cleaned.hasSuffix("\n") { cleaned.removeLast() }
                            
                            if cleaned != newValue {
                                viewModel.inputText = cleaned
                            }
                            
                            // 发送前收起键盘，保持与发送按钮一致，避免焦点抖动/布局循环
                            if isFocused { isFocused = false }
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            
                            // 有图或有字才发送（避免空回车误触）
                            if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedImage != nil {
                                viewModel.sendMessage()
                            }
                            
                            // 发送后输入框会被清空，这里顺带刷新高度到初始值
                            updateInputHeightIfNeeded()
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        updateInputWidthIfNeeded(geo.size.width)
                                    }
                                    .onChange(of: geo.size.width) { _, newWidth in
                                        updateInputWidthIfNeeded(newWidth)
                                    }
                            }
                        )
                        .onAppear {
                            updateInputHeightIfNeeded()
                        }
                        .onChange(of: inputTextWidth) { _, _ in
                            updateInputHeightIfNeeded()
                        }
                        .onChange(of: viewModel.inputText) { _, _ in
                            updateInputHeightIfNeeded()
                        }
                        .focused($isFocused)
                        .allowsHitTesting(!gestureOverlayEnabled)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.6 : 1)
                    
                    // 手势面板：只在 holdToTalkEnabled 时开启
                    // 关键：命中区域必须严格等同于输入框本体，避免“输入框下面”误触触发录音
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.clear)
                        .frame(height: inputTextHeight)
                        .contentShape(RoundedRectangle(cornerRadius: 24))
                        .allowsHitTesting(gestureOverlayEnabled)
                        // 轻点：进入输入（聚焦）
                        // 用 highPriorityGesture 确保不会触发上层 ScrollView 的 dismiss tap
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                guard holdToTalkEnabled, !viewModel.isRecording else { return }
                                DebugProbe.log("HoldToTalk overlay tap -> focus")
                                // 兜底：即便 drag ended 未触发，也要先收回预收音/状态，再聚焦
                                forceEndHoldToTalk()
                                isFocused = true
                            }
                        )
                        // 根治：用“按下即进入 tracking”的 DragGesture(minDistance:0) 来实现更灵敏的按住说话。
                        // - 按下后 0.18s 仍未松手 → 进入录音
                        // - 0.18s 内松手且无明显移动 → 视为轻点聚焦
                        // - 录音中拖动上划 → 取消提示；松手 → stop/cancel
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // 第一次 onChanged 视为按下
                                    if !isPressing {
                                        // 开始 tracking
                                        handleHoldToTalkPressingChanged(true)

                                        // 取消旧任务，启动新的“长按才触发录音”的任务
                                        pendingHoldToTalkTask?.cancel()
                                        pendingHoldToTalkTask = Task { @MainActor in
                                            // 两段式：
                                            // - 0.12s：仍在按住才开始“预收音”（避免轻点聚焦就点亮麦克风）
                                            // - 0.20s：仍在按住才真正进入录音态并展示 overlay
                                            try? await Task.sleep(nanoseconds: 120_000_000) // 0.12s
                                            guard !Task.isCancelled else { return }
                                            guard isPressing, !didMoveDuringPress else { return }
                                            guard !viewModel.isRecording else { return }
                                            guard !viewModel.isAgentTyping else { return }
                                            guard !isFocused else { return }
                                            guard viewModel.inputText.isEmpty, viewModel.selectedImage == nil else { return }
                                            viewModel.beginHoldToTalkPreCaptureIfNeeded()

                                            try? await Task.sleep(nanoseconds: 80_000_000) // +0.08s => 0.20s
                                            guard !Task.isCancelled else { return }
                                            guard isPressing, !didMoveDuringPress else {
                                                // 轻点/抬手导致未进入录音：如果已经预收音了，确保收回
                                                viewModel.stopHoldToTalkPreCaptureIfNeeded()
                                                return
                                            }
                                            guard !viewModel.isRecording else { return }
                                            guard !viewModel.isAgentTyping else { return }
                                            guard !isFocused else { return }
                                            guard viewModel.inputText.isEmpty, viewModel.selectedImage == nil else { return }

                                            DebugProbe.log("HoldToTalk long-press -> start recording")
                                            viewModel.startHoldToTalkRecordingFromLongPress()
                                        }
                                    }
                                    
                                    // 移动阈值：10pt 以上才算“发生明显移动”
                                    let dragPoint = CGPoint(x: value.translation.width, y: value.translation.height)
                                    if abs(dragPoint.x) > 10 || abs(dragPoint.y) > 10 {
                                        handleHoldToTalkDragChanged(value)
                                    }
                                }
                                .onEnded { value in
                                    pendingHoldToTalkTask?.cancel()
                                    pendingHoldToTalkTask = nil
                                    
                                    // 结束按压（会在内部决定：stop/cancel 还是 quick tap focus）
                                    handleHoldToTalkPressingChanged(false)
                                    
                                    // 兜底：结束时把移动状态清掉
                                    if !isPressing {
                                        didMoveDuringPress = false
                                    }
                                    
                                    _ = value // suppress unused warning in some toolchains
                                }
                        )
                }
                // 关键：输入区域与手势面板同高，避免命中区域和视觉不一致
                .frame(height: inputTextHeight)
                
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
                    Button(action: {
                        // 发送前收起键盘，避免焦点状态来回抖动
                        if isFocused { isFocused = false }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        viewModel.sendMessage()
                    }) {
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
        .modifier(InputContainerFrameReporter(viewModel: viewModel, isFocused: isFocused, scale: displayScale))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .inset(by: 0.5)
                .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 1)
        )
        
        // 始终返回同一个 base（保持视图树稳定，避免焦点丢失/抖动）
        base
    }
    
    // MARK: - Gesture Logic
    
    private func handleHoldToTalkPressingChanged(_ isDown: Bool) {
        guard !viewModel.isAgentTyping else { return }
        
        if isDown {
            isPressing = true
            pressBeganAt = Date()
            didMoveDuringPress = false
            // 触感：按下给一个很轻的确认，不阻塞 UI（真正进入录音态会再给一次更明显的确认）
            HapticFeedback.selection()
            // 注意：不要在按下瞬间就启用麦克风，否则“轻点聚焦”也会点亮系统橙点。
            // 预收音改为在长按阈值附近（见 pendingHoldToTalkTask）再启动。
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

        // 没有展示 overlay 的情况：停止预收音（不发送）
        viewModel.stopHoldToTalkPreCaptureIfNeeded()
        
        // 非录音：把“轻点中间区域”当作 focus 输入框（但滑动/明显移动不算轻点）
        if !didMoveDuringPress,
           !isFocused,
           viewModel.inputText.isEmpty,
           viewModel.selectedImage == nil
        {
            let isQuickTap = beganAt.map { Date().timeIntervalSince($0) < 0.25 } ?? true
            if isQuickTap {
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
        
        // 触感已在按下瞬间给过，这里保持安静，避免双重震动
        // 已经在按下时预收音了，这里只需要展示 overlay
        viewModel.revealHoldToTalkOverlayIfPossible()
    }
    
    private func handleHoldToTalkDragChanged(_ value: DragGesture.Value) {
        guard !viewModel.isAgentTyping else { return }
        
        // 只要按压中发生了明显移动，就不再把它当成“轻点 focus”
        if isPressing && !viewModel.isRecording {
            didMoveDuringPress = true
            // 如果还没展示 overlay，就立刻停止预收音，避免“用户在滑动/滚动”时意外被收音
            pendingHoldToTalkTask?.cancel()
            pendingHoldToTalkTask = nil
            viewModel.stopHoldToTalkPreCaptureIfNeeded()
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
        } else {
            // 如果还在预收音阶段，也需要停止
            viewModel.stopHoldToTalkPreCaptureIfNeeded()
        }
    }
}

// MARK: - Input height helpers

extension ChatInputView {
    private func updateInputWidthIfNeeded(_ newWidth: CGFloat) {
        let w = max(newWidth, 0)
        // 避免键盘动画/浮点抖动导致的高频刷新
        guard abs(inputTextWidth - w) > 1 else { return }
        inputTextWidth = w
    }
    
    private func updateInputHeightIfNeeded() {
        // 设计基准：一行高度 52；最多约 3 行
        let minH: CGFloat = 52
        let font = UIFont.systemFont(ofSize: 16)
        let verticalPadding: CGFloat = 12 + 12
        
        // 宽度未知时直接回落到最小高度，避免“首帧就抬高”
        guard inputTextWidth > 1 else {
            if inputTextHeight != minH { inputTextHeight = minH }
            return
        }
        
        // TextField 外层有 horizontal padding 8*2，这里按同样数值扣掉用于测量文字换行宽度
        let usableWidth = max(inputTextWidth - 16, 0)
        let rawText = viewModel.inputText.isEmpty ? "占位" : viewModel.inputText
        let text = rawText as NSString
        let rect = text.boundingRect(
            with: CGSize(width: usableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        
        // 文本高度 + padding 后得到“理想高度”，再限制到 3 行范围
        let ideal = ceil(rect.height) + verticalPadding
        let maxH = minH + (font.lineHeight * 2.0) // 约 3 行：多 2 个行高
        let clamped = min(max(ideal, minH), maxH)
        
        // 小幅动画让高度变化更自然（不包裹整个输入清空，避免按钮 transition 不同步）
        if abs(inputTextHeight - clamped) > 0.5 {
            withAnimation(.easeInOut(duration: 0.12)) {
                inputTextHeight = clamped
            }
        }
    }
}

// MARK: - Helpers

/// 把输入框 frame 上报给 VM（避免把这段逻辑散落在主 view 里导致类型推断变慢）
private struct InputContainerFrameReporter: ViewModifier {
    @ObservedObject var viewModel: ChatInputViewModel
    var isFocused: Bool
    var scale: CGFloat
    
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(hex: "F7F8FA"))
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                // 输入框聚焦时 frame 会跟随键盘动画不断抖动；
                                // 录音动画只在“未聚焦”长按触发，所以这里聚焦时停止上报。
                                guard !isFocused else {
                                    DebugProbe.throttled("ChatInputView.inputFrame.ignored", interval: 0.8) {
                                        DebugProbe.log("ChatInputView.inputFrame ignored (isFocused=true)")
                                    }
                                    return
                                }
                                let f = normalizeFrame(geo.frame(in: .global), scale: scale)
                                DispatchQueue.main.async {
                                    if viewModel.inputFrame != f {
                                        viewModel.inputFrame = f
                                        DebugProbe.throttled("ChatInputView.inputFrame.update", interval: 0.2) {
                                            DebugProbe.log("ChatInputView.inputFrame -> \(f)")
                                        }
                                    }
                                }
                            }
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                // 同上：聚焦时停止上报，并做像素取整 + 变更才写入，避免高频状态更新。
                                guard !isFocused else {
                                    DebugProbe.throttled("ChatInputView.inputFrame.ignored", interval: 0.8) {
                                        DebugProbe.log("ChatInputView.inputFrame ignored (isFocused=true)")
                                    }
                                    return
                                }
                                let f = normalizeFrame(newFrame, scale: scale)
                                DispatchQueue.main.async {
                                    if viewModel.inputFrame != f {
                                        viewModel.inputFrame = f
                                        DebugProbe.throttled("ChatInputView.inputFrame.update", interval: 0.2) {
                                            DebugProbe.log("ChatInputView.inputFrame -> \(f)")
                                        }
                                    }
                                }
                            }
                    }
                )
        )
    }
}

// MARK: - Frame Helpers

/// 把 frame 按屏幕像素取整，减少键盘动画/浮点误差导致的“微抖动”更新风暴。
private func normalizeFrame(_ rect: CGRect, scale: CGFloat) -> CGRect {
    let s = max(scale, 1)
    func r(_ v: CGFloat) -> CGFloat { (v * s).rounded() / s }
    return CGRect(x: r(rect.origin.x), y: r(rect.origin.y), width: r(rect.size.width), height: r(rect.size.height))
}

// MARK: - Debug

#if DEBUG
@MainActor
private enum DebugProbe {
    private static var lastPrintAt: [String: Date] = [:]
    
    static func log(_ message: String) {
    }
    
    static func throttled(_ key: String, interval: TimeInterval, _ block: () -> Void) {
        let now = Date()
        if let last = lastPrintAt[key], now.timeIntervalSince(last) < interval {
            return
        }
        lastPrintAt[key] = now
        block()
    }
}
#else
private enum DebugProbe {
    static func log(_ message: String) {}
    static func throttled(_ key: String, interval: TimeInterval, _ block: () -> Void) {}
}
#endif
