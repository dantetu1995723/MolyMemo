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
                .simultaneousGesture(isLoading ? nil : dragGesture) // 加载中禁用手势
                .onTapGesture {
                    if isLoading { return }
                    if isRevealed {
                        closeSwipe()
                    } else {
                        onTap()
                    }
                }
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                if !isSwiping {
                    if abs(value.translation.width) > abs(value.translation.height) {
                        isSwiping = true
                        HapticFeedback.light()
                    } else {
                        return
                    }
                }
                
                let baseOffset = isRevealed ? -maxRevealOffset : 0
                var newOffset = baseOffset + value.translation.width
                
                if newOffset > 0 {
                    newOffset = newOffset / 5
                }
                
                if newOffset < -maxRevealOffset {
                    let extra = newOffset + maxRevealOffset
                    newOffset = -maxRevealOffset + extra / 2.5
                }
                
                offsetX = newOffset
            }
            .onEnded { value in
                guard isSwiping else { return }
                defer { isSwiping = false }
                
                let baseOffset = isRevealed ? -maxRevealOffset : 0
                let finalOffset = baseOffset + value.translation.width
                
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
    }
    
    private func revealSwipe() {
        offsetX = -maxRevealOffset
        isRevealed = true
    }
    
    private func closeSwipe() {
        offsetX = 0
        isRevealed = false
    }
}
