import SwiftUI

/// 通用的「左滑删除」容器：适用于 ScrollView + LazyVStack 场景（不依赖 List 的 swipeActions）
/// - 行为：
///   - 左滑露出删除背景
///   - 左滑足够深：直接触发删除
///   - 已露出时点击：收起
///   - 未露出时点击：触发 onTap（通常用于打开详情）
struct SwipeToDeleteCard<Content: View>: View {
    let onTap: () -> Void
    let onDelete: () -> Void
    var isLoading: Bool = false // 新增加载状态
    private let content: () -> Content
    
    @State private var offsetX: CGFloat = 0
    @State private var isRevealed = false
    @State private var isSwiping = false
    
    // 动画控制
    @State private var isPulseAnimating = false
    
    private let maxRevealOffset: CGFloat = 110.0
    private let revealThreshold: CGFloat = 70.0
    
    init(
        isLoading: Bool = false,
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.onTap = onTap
        self.onDelete = onDelete
        self.content = content
    }
    
    private var revealProgress: CGFloat {
        min(1.0, max(0.0, -offsetX / maxRevealOffset))
    }
    
    private func handleTap() {
        if isLoading { return }
        if isRevealed {
            closeSwipe()
        } else {
            onTap()
        }
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // 只有滑动时才显示删除背景
            if offsetX < 0 && !isLoading {
                deleteBackground
                    .opacity(Double(revealProgress))
            }
            
            content()
                .contentShape(Rectangle())
                .offset(x: offsetX)
                .overlay(loadingOverlay) // 叠加加载效果
        }
        // 注意：这里不能依赖 SwiftUI 的 onTapGesture，因为我们使用了 UIKit overlay 来捕获横向滑动；
        // overlay 会成为最上层的 hit-test 目标，导致 SwiftUI tap 偶发/经常收不到触摸。
        // 因此把“点击”也交给同一个 UIKit overlay 处理（见 HorizontalPanCaptureView 的 onTap）。
        .contentShape(Rectangle())
        // 使用 UIKit 的 UIPanGestureRecognizer，仅在“横向”时才会 begin，避免与 ScrollView 的纵向滚动互相抢手势
        .overlay {
            HorizontalPanCaptureView(
                isEnabled: !isLoading,
                onTap: {
                    handleTap()
                },
                onChanged: { dx, _ in
                    if !isSwiping {
                        isSwiping = true
                        HapticFeedback.light()
                    }
                    
                    let baseOffset = isRevealed ? -maxRevealOffset : 0
                    var newOffset = baseOffset + dx
                    
                    if newOffset > 0 {
                        newOffset = newOffset / 5
                    }
                    
                    if newOffset < -maxRevealOffset {
                        let extra = newOffset + maxRevealOffset
                        newOffset = -maxRevealOffset + extra / 2.5
                    }
                    
                    offsetX = newOffset
                },
                onEnded: { dx, _, _, _ in
                    guard isSwiping else { return }
                    defer { isSwiping = false }
                    
                    let baseOffset = isRevealed ? -maxRevealOffset : 0
                    let finalOffset = baseOffset + dx
                    
                    // 深度滑动删除阈值
                    let deleteThreshold = -maxRevealOffset * 1.6
                    
                    if finalOffset < deleteThreshold {
                        HapticFeedback.medium()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offsetX = -1000 // 划出屏幕
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDelete()
                            // 删除后重置状态，以便复用
                            offsetX = 0
                            isRevealed = false
                        }
                    } else if -finalOffset > revealThreshold {
                        HapticFeedback.light()
                        revealSwipe()
                    } else {
                        closeSwipe()
                    }
                }
            )
            .allowsHitTesting(!isLoading)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: offsetX)
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .onChange(of: isLoading) { _, newValue in
            if newValue {
                closeSwipe() // 开始加载时自动收回滑动
            }
        }
    }
    
    // 精致的加载层
    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)
                
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.red)
                        .scaleEffect(0.9)
                    
                    Text("正在删除...")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.red.opacity(0.8))
                }
                .opacity(isPulseAnimating ? 0.5 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulseAnimating = true
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
    
    private var deleteBackground: some View {
        ZStack(alignment: .trailing) {
            // 玻璃拟态底色
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            
            // 渐变层
            LinearGradient(
                colors: [
                    Color.red.opacity(0.1),
                    Color.red.opacity(0.7),
                    Color.red.opacity(0.9)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            
            // 动态图标和文字
            HStack(spacing: 12) {
                Spacer()
                
                if revealProgress > 0.6 {
                    Text("松手删除")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                
                Image(systemName: "trash.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(0.8 + 0.4 * revealProgress)
                    .rotationEffect(.degrees(Double(offsetX) / 10.0))
                    .padding(.trailing, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .shadow(color: Color.red.opacity(0.15 * Double(revealProgress)), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
        )
    }

    // 说明：左滑删除不再使用 SwiftUI DragGesture（它会和 ScrollView 纵向滚动间歇性抢手势），
    // 改用 HorizontalPanCaptureView（UIKit），仅当明确横向拖拽才会 begin。
    
    private func revealSwipe() {
        offsetX = -maxRevealOffset
        isRevealed = true
    }
    
    private func closeSwipe() {
        offsetX = 0
        isRevealed = false
    }
}

// MARK: - UIKit horizontal pan (only begins when horizontal-dominant)
private struct HorizontalPanCaptureView: UIViewRepresentable {
    var isEnabled: Bool
    var onTap: () -> Void
    var onChanged: (CGFloat, CGFloat) -> Void // dx, dy
    var onEnded: (CGFloat, CGFloat, CGFloat, CGFloat) -> Void // dx, dy, vx, vy
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false // 不要吞掉点击
        v.addGestureRecognizer(pan)

        // Tap：用于触发“打开详情/收起滑动”。因为 pan overlay 会覆盖在最上层，所以 tap 也必须在这里处理。
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        // 横滑时不要触发 tap
        tap.require(toFail: pan)
        v.addGestureRecognizer(tap)
        
        return v
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        // enable/disable recognizer
        uiView.gestureRecognizers?.forEach { $0.isEnabled = isEnabled }
    }
    
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalPanCaptureView
        
        init(parent: HorizontalPanCaptureView) {
            self.parent = parent
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let v = pan.velocity(in: view)
            // 明确横向才开始：避免上下滚动时误触发
            return abs(v.x) > abs(v.y) + 40
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // 允许与 ScrollView 的手势并存（纵向滚动时我们根本不会 begin；横向时 ScrollView 也不会有效滚动）
            true
        }
        
        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let t = pan.translation(in: view)
            let v = pan.velocity(in: view)
            
            switch pan.state {
            case .began, .changed:
                parent.onChanged(t.x, t.y)
            case .ended, .cancelled, .failed:
                parent.onEnded(t.x, t.y, v.x, v.y)
            default:
                break
            }
        }

        @objc func handleTap(_ tap: UITapGestureRecognizer) {
            guard parent.isEnabled else { return }
            if tap.state == .ended {
                parent.onTap()
            }
        }
    }
}
