import SwiftUI
import UIKit
import Photos

struct GeometryGetter: ViewModifier {
    @Binding var rect: CGRect
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.onAppear {
                    self.rect = proxy.frame(in: .global)
                }
                .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                    self.rect = newFrame
                }
            }
        )
    }
}

extension View {
    func getRect(_ rect: Binding<CGRect>) -> some View {
        self.modifier(GeometryGetter(rect: rect))
    }
}

// MARK: - ===== 圆圆UI设计系统 =====

// 主题色定义 - 统一灰白色调
struct YuanyuanTheme {
    // 主色调 - 系统灰色
    static let primaryGray = Color(white: 0.45)  // 中性灰
    static let lightGray = Color(white: 0.65)    // 浅灰
    static let darkGray = Color(white: 0.25)     // 深灰
    
    // 渐变组合 - 灰色渐变
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [lightGray, primaryGray],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // 背景色 - 浅灰白
    static let warmBackground = Color(white: 0.96)
    
    // 统一主题色 - 单一灰色
    static let themeColor = Color(white: 0.55)
    
    // 根据索引获取颜色（保持API兼容，但返回统一灰色）
    static func color(at index: Int) -> Color {
        themeColor
    }
}

// MARK: - 模块渐变背景 - 灰白渐变
struct ModuleBackgroundView: View {
    var themeColor: Color = YuanyuanTheme.warmBackground
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .white, location: 0.0),
                .init(color: Color(white: 0.95), location: 0.3),
                .init(color: Color(white: 0.92), location: 0.6),
                .init(color: Color(white: 0.96), location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - 统一底部弹窗容器
struct ModuleSheetContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 统一模块头部
struct ModuleHeaderView: View {
    let title: String
    let dismiss: DismissAction
    var subtitle: String? = nil
    var rightButton: AnyView? = nil
    var themeColor: Color = YuanyuanTheme.warmBackground
    
    // 标题颜色 - 深灰色
    private var titleColor: Color {
        Color(white: 0.25)
    }
    
    var body: some View {
        ZStack {
            // 居中标题区域（对齐首页样式）
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundColor(titleColor)
                    .frame(height: 36)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(titleColor.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            
            // 右侧按钮（可选）
            HStack {
                Spacer()
                if let rightButton = rightButton {
                    rightButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - 液态玻璃卡片
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20
    
    init(padding: CGFloat = 16, cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // 基础填充
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.85), location: 0.0),
                                    .init(color: Color.white.opacity(0.65), location: 0.5),
                                    .init(color: Color.white.opacity(0.75), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // 表面光泽
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.4), location: 0.0),
                                    .init(color: Color.white.opacity(0.15), location: 0.2),
                                    .init(color: Color.clear, location: 0.5)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // 晶体边框
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.9), location: 0.0),
                                    .init(color: Color.white.opacity(0.3), location: 0.5),
                                    .init(color: Color.white.opacity(0.6), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.white.opacity(0.6), radius: 8, x: 0, y: -2)
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

// MARK: - 玻璃按钮背景 - 轻盈高亮白色
struct GlassButtonBackground: View {
    var isHighlight: Bool = false
    
    var body: some View {
        ZStack {
            // 主体液态玻璃
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.95), location: 0.0),
                            .init(color: Color.white.opacity(0.85), location: 0.5),
                            .init(color: Color.white.opacity(0.90), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 高光层
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.6), location: 0.0),
                            .init(color: Color.white.opacity(0.2), location: 0.3),
                            .init(color: Color.clear, location: 0.7)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 晶体边框
            Circle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(1.0), location: 0.0),
                            .init(color: Color.white.opacity(0.5), location: 0.5),
                            .init(color: Color.white.opacity(0.8), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: Color.white.opacity(0.8), radius: 8, x: 0, y: -3)
        .shadow(color: Color.white.opacity(0.4), radius: 4, x: -2, y: -2)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 液态玻璃胶囊按钮背景 - 轻盈高亮白色
struct LiquidGlassCapsuleBackground: View {
    var body: some View {
        ZStack {
            // 主体液态玻璃
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.92), location: 0.0),
                            .init(color: Color.white.opacity(0.78), location: 0.5),
                            .init(color: Color.white.opacity(0.85), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 高光层
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.7), location: 0.0),
                            .init(color: Color.white.opacity(0.3), location: 0.25),
                            .init(color: Color.clear, location: 0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // 晶体边框
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(1.0), location: 0.0),
                            .init(color: Color.white.opacity(0.5), location: 0.5),
                            .init(color: Color.white.opacity(0.8), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: Color.white.opacity(0.7), radius: 6, x: 0, y: -2)
        .shadow(color: Color.white.opacity(0.3), radius: 3, x: -1, y: -1)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}

// MARK: - 统一底部添加按钮 - 轻盈高亮白色
struct ModuleAddButton: View {
    let title: String
    let action: () -> Void
    var icon: String = "plus.circle.fill"
    
    var body: some View {
        Button(action: {
            HapticFeedback.medium()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.black.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    // 主体液态玻璃
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.95), location: 0.0),
                                    .init(color: Color.white.opacity(0.82), location: 0.5),
                                    .init(color: Color.white.opacity(0.88), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // 高光层
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.7), location: 0.0),
                                    .init(color: Color.white.opacity(0.3), location: 0.3),
                                    .init(color: Color.clear, location: 0.6)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // 晶体边框
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(1.0), location: 0.0),
                                    .init(color: Color.white.opacity(0.5), location: 0.5),
                                    .init(color: Color.white.opacity(0.8), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.0
                        )
                }
            )
            .shadow(color: Color.white.opacity(0.9), radius: 12, x: 0, y: -4)
            .shadow(color: Color.white.opacity(0.5), radius: 6, x: -2, y: -2)
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 34)
    }
}

// MARK: - Tab选择器样式 - 灰色调
struct ModuleTabButton: View {
    let title: String
    let value: String
    let isSelected: Bool
    let action: () -> Void
    var themeColor: Color = YuanyuanTheme.warmBackground  // 保持API兼容
    
    // 指示器颜色 - 深灰色
    private var indicatorColor: Color {
        Color(white: 0.35)
    }
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(.black.opacity(isSelected ? 0.85 : 0.5))
                    
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(isSelected ? 0.85 : 0.5))
                }
                .frame(maxWidth: .infinity)
                
                // 底部指示器 - 使用主题色的深色版本
                Capsule()
                    .fill(
                        isSelected 
                            ? LinearGradient(
                                colors: [indicatorColor, indicatorColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 3)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 筛选胶囊按钮 - 轻盈高亮白色
struct FilterCapsuleButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundColor(.black.opacity(isSelected ? 0.75 : 0.5))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        // 主体液态玻璃
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(isSelected ? 0.95 : 0.85), location: 0.0),
                                        .init(color: Color.white.opacity(isSelected ? 0.82 : 0.68), location: 0.5),
                                        .init(color: Color.white.opacity(isSelected ? 0.88 : 0.75), location: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // 高光层
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(isSelected ? 0.7 : 0.5), location: 0.0),
                                        .init(color: Color.white.opacity(isSelected ? 0.3 : 0.2), location: 0.3),
                                        .init(color: Color.clear, location: 0.6)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // 晶体边框
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(1.0), location: 0.0),
                                        .init(color: Color.white.opacity(0.5), location: 0.5),
                                        .init(color: Color.white.opacity(0.8), location: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSelected ? 2.0 : 1.5
                            )
                    }
                )
                .shadow(color: Color.white.opacity(isSelected ? 0.8 : 0.6), radius: 6, x: 0, y: -2)
                .shadow(color: Color.white.opacity(isSelected ? 0.4 : 0.2), radius: 3, x: -1, y: -1)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 状态标签
struct StatusBadgeView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color)
                    .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
            )
    }
}

// MARK: - ===== 灰色气泡加载动画 =====
struct LoadingDotsView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .opacity(loadingOpacityForDot(index))
            }
        }
        .onAppear {
            startLoadingAnimation()
        }
    }

    // 计算每个点的透明度
    private func loadingOpacityForDot(_ index: Int) -> Double {
        let phase = (animationPhase + index) % 3
        return phase == 0 ? 1.0 : 0.3
    }

    // 启动加载动画
    private func startLoadingAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// ===== 图片包装器，支持 Identifiable =====
struct IdentifiableImage: Identifiable {
    let id: UUID
    let image: UIImage
    
    init(image: UIImage) {
        self.id = UUID()
        self.image = image
    }
}

// ===== 图片画廊包装器，支持多张图片滑动浏览 =====
struct ImageGallery: Identifiable {
    let id: UUID
    let images: [UIImage]
    let initialIndex: Int
    
    init(images: [UIImage], initialIndex: Int = 0) {
        self.id = UUID()
        self.images = images
        self.initialIndex = max(0, min(initialIndex, images.count - 1))
    }
}

// ===== 聊天图片 Hero 预览状态（从缩略图放大）=====
struct ImageHeroPreviewState: Identifiable, Equatable {
    let id: UUID
    let image: UIImage
    /// 缩略图在全局坐标中的位置（用于开场/退场动画）
    let sourceRect: CGRect
    
    init(image: UIImage, sourceRect: CGRect) {
        self.id = UUID()
        self.image = image
        self.sourceRect = sourceRect
    }
    
    static func == (lhs: ImageHeroPreviewState, rhs: ImageHeroPreviewState) -> Bool {
        lhs.id == rhs.id
    }
}

// ===== Hero 预览浮层：从 sourceRect 放大到全屏，再进入可交互模式 =====
struct HeroImageOverlay: View {
    let image: UIImage
    let sourceRect: CGRect
    let onDismiss: () -> Void
    
    // 用 scale/offset 动画代替 frame 动画，GPU 加速更流畅
    @State private var animProgress: CGFloat = 0.0  // 0=缩略图位置, 1=全屏
    @State private var backgroundOpacity: Double = 0.0
    @State private var showInteractive: Bool = false
    @State private var isDismissing: Bool = false
    
    var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            
            // 计算缩略图和全屏的参数
            let thumbCenter = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
            let screenCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
            let scaleX = sourceRect.width / screenSize.width
            let scaleY = sourceRect.height / screenSize.height
            let thumbScale = max(scaleX, scaleY)  // 保持宽高比
            
            // 插值计算当前 scale 和 offset
            let currentScale = thumbScale + (1.0 - thumbScale) * animProgress
            let currentOffsetX = (thumbCenter.x - screenCenter.x) * (1.0 - animProgress)
            let currentOffsetY = (thumbCenter.y - screenCenter.y) * (1.0 - animProgress)
            
            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()
                
                // 交互层（动画完成后显示）
                if showInteractive && !isDismissing {
                    FullScreenImageView(
                        image: image,
                        onTapDismiss: { beginHeroDismiss() },
                        onSwipeDismiss: { beginFadeDismiss() }
                    )
                    .transition(.opacity)
                }
                
                // 动画层：用 transform 动画更流畅
                if !showInteractive || isDismissing {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: screenSize.width, height: screenSize.height)
                        .clipped()
                        .scaleEffect(currentScale)
                        .offset(x: currentOffsetX, y: currentOffsetY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: screenSize.width, height: screenSize.height)
            .ignoresSafeArea()
            .onAppear {
                // 初始状态：缩略图位置
                animProgress = 0.0
                backgroundOpacity = 0.0
                showInteractive = false
                isDismissing = false
                
                // 快速流畅的展开动画
                withAnimation(.easeOut(duration: 0.25)) {
                    animProgress = 1.0
                    backgroundOpacity = 1.0
                }
                
                // 动画结束后切到交互层，避免手势影响“几何动画”
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    showInteractive = true
                }
            }
        }
    }
    
    /// 点击退出：执行缩回缩略图的 Hero 动画
    private func beginHeroDismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        showInteractive = false
        
        withAnimation(.easeIn(duration: 0.22)) {
            animProgress = 0.0
            backgroundOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onDismiss()
        }
    }
    
    /// 滑动退出：直接淡出
    private func beginFadeDismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        
        withAnimation(.easeOut(duration: 0.18)) {
            backgroundOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            onDismiss()
        }
    }
}

// ===== 全屏图片预览（单张） =====
struct FullScreenImageView: View {
    let image: UIImage
    var namespace: Namespace.ID? = nil
    var matchId: String? = nil
    /// 点击退出（会触发 Hero 缩回动画）
    let onTapDismiss: () -> Void
    /// 滑动退出（直接淡出，不做缩回）
    let onSwipeDismiss: () -> Void
    
    /// 兼容旧调用者：同时指定 tap/swipe 回调为同一个
    init(image: UIImage, namespace: Namespace.ID? = nil, matchId: String? = nil, onDismiss: @escaping () -> Void) {
        self.image = image
        self.namespace = namespace
        self.matchId = matchId
        self.onTapDismiss = onDismiss
        self.onSwipeDismiss = onDismiss
    }
    
    /// 新调用者：分别指定 tap/swipe 回调
    init(image: UIImage, onTapDismiss: @escaping () -> Void, onSwipeDismiss: @escaping () -> Void) {
        self.image = image
        self.namespace = nil
        self.matchId = nil
        self.onTapDismiss = onTapDismiss
        self.onSwipeDismiss = onSwipeDismiss
    }
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 0.0 // 默认透明，动画进入时变 1.0
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(opacity)
            
            GeometryReader { proxy in
                let img = Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                
                if let ns = namespace, let mid = matchId {
                    img
                        .matchedGeometryEffect(id: mid, in: ns, isSource: false)
                        .scaleEffect(scale)
                        .offset(dragOffset)
                        .clipped()
                } else {
                    img
                        .scaleEffect(scale)
                        .offset(dragOffset)
                        .clipped()
                }
            }
            .ignoresSafeArea()
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1.0 {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    lastScale = 1.0
                                }
                            } else if scale > 3.0 {
                                withAnimation(.spring()) {
                                    scale = 3.0
                                    lastScale = 3.0
                                }
                            }
                        },
                    DragGesture()
                        .onChanged { value in
                            if scale <= 1.0 {
                                dragOffset = value.translation
                                let dragDistance = abs(value.translation.height)
                                opacity = max(0.3, 1.0 - dragDistance / 300.0)
                            }
                        }
                        .onEnded { value in
                            if abs(value.translation.height) > 80 && scale <= 1.0 {
                                // 达到关闭阈值：调用滑动退出（不做缩回动画）
                                HapticFeedback.light()
                                onSwipeDismiss()
                            } else {
                                // 未达到阈值：快速复位
                                withAnimation(.easeOut(duration: 0.18)) {
                                    dragOffset = .zero
                                    opacity = 1.0
                                }
                            }
                        }
                )
            )
        }
        // ✅ 关键：强制预览层撑满父容器，否则在外层 ZStack(alignment: .bottom) 下会出现“贴底/不居中”的视觉偏差
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 1.0
            }
        }
        .onTapGesture {
            if scale <= 1.0 && dragOffset == .zero {
                HapticFeedback.light()
                onTapDismiss()
            }
        }
    }
}

// ===== 全屏图片画廊（支持左右滑动） =====
struct FullScreenImageGallery: View {
    let images: [UIImage]
    let initialIndex: Int
    let onDismiss: () -> Void
    
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 1.0
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""
    
    init(images: [UIImage], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.images = images
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(opacity)
            
            if !images.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        SingleImageView(
                            image: image,
                            scale: $scale,
                            lastScale: $lastScale,
                            dragOffset: $dragOffset,
                            opacity: $opacity,
                            onDismiss: onDismiss
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onAppear {
                    // 立即设置初始页面
                    currentIndex = initialIndex
                }
                .onChange(of: currentIndex) { _, newIndex in
                    // 切换图片时重置缩放和拖拽状态
                    if scale > 1.0 {
                        withAnimation(.spring()) {
                            scale = 1.0
                            lastScale = 1.0
                        }
                    }
                    dragOffset = .zero
                    opacity = 1.0
                }
                
                // 底部工具栏（页码指示器 + 保存按钮）
                VStack {
                    Spacer()
                    
                    // 页码指示器
                    if images.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<images.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    
                    // 保存按钮（Liquid glass效果）- 灰白色调
                    Button(action: {
                        saveCurrentImage()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("保存到相册")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
                        .shadow(color: .black.opacity(0.8), radius: 0, x: -1, y: -1)
                        .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: -1)
                        .shadow(color: .black.opacity(0.8), radius: 0, x: -1, y: 1)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            ZStack {
                                // 毛玻璃材质
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                
                                // 灰色渐变叠加层
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(white: 0.4).opacity(0.7),
                                                Color(white: 0.3).opacity(0.5)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                // 高光效果
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.2)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .alert("提示", isPresented: $showSaveAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(saveAlertMessage)
        }
    }
    
    // 保存当前图片到相册
    private func saveCurrentImage() {
        guard currentIndex < images.count else { return }
        let imageToSave = images[currentIndex]
        
        HapticFeedback.light()
        
        // 检查相册访问权限
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    // 保存图片
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: imageToSave)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                HapticFeedback.success()
                                saveAlertMessage = "图片已保存到相册"
                            } else {
                                HapticFeedback.error()
                                saveAlertMessage = "保存失败：\(error?.localizedDescription ?? "未知错误")"
                            }
                            showSaveAlert = true
                        }
                    }
                case .denied, .restricted:
                    HapticFeedback.error()
                    saveAlertMessage = "请在设置中允许访问相册"
                    showSaveAlert = true
                default:
                    break
                }
            }
        }
    }
}

// ===== 单张图片视图（用于画廊） =====
private struct SingleImageView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var dragOffset: CGSize
    @Binding var opacity: Double
    let onDismiss: () -> Void
    
    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill() // ✅ 默认铺满屏幕，去掉左右黑边
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(dragOffset)
                .clipped()
        }
        .ignoresSafeArea()
        .gesture(
                // 同时支持缩放和拖拽
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1.0 {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    lastScale = 1.0
                                }
                            } else if scale > 3.0 {
                                withAnimation(.spring()) {
                                    scale = 3.0
                                    lastScale = 3.0
                                }
                            }
                        },
                    DragGesture()
                        .onChanged { value in
                            // 只有在未缩放时才允许拖拽关闭
                            if scale <= 1.0 {
                                let verticalDistance = abs(value.translation.height)
                                let horizontalDistance = abs(value.translation.width)
                                
                                // 如果是垂直拖拽，则关闭预览
                                if verticalDistance > horizontalDistance && verticalDistance > 10 {
                                    dragOffset = value.translation
                                    // 根据拖拽距离调整透明度
                                    opacity = max(0.3, 1.0 - verticalDistance / 300.0)
                                }
                            }
                        }
                        .onEnded { value in
                            // 如果向下拖拽超过100点，则关闭
                            if value.translation.height > 100 && scale <= 1.0 {
                                HapticFeedback.light()
                                onDismiss()
                            } else {
                                // 否则恢复原状
                                withAnimation(.spring()) {
                                    dragOffset = .zero
                                    opacity = 1.0
                                }
                            }
                        }
                )
            )
            .onTapGesture {
                if scale <= 1.0 && dragOffset == .zero {
                    HapticFeedback.light()
                    onDismiss()
                }
            }
    }
}




