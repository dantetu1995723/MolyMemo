import SwiftUI
import UIKit
import Photos

// MARK: - ===== 圆圆UI设计系统 =====

// 主题色定义
struct YuanyuanTheme {
    // 黄绿主色调
    static let primaryLight = Color(red: 0.85, green: 1.0, blue: 0.25)
    static let primaryDark = Color(red: 0.78, green: 0.98, blue: 0.2)
    
    // 渐变组合
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primaryLight, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // 暖色背景色（首页默认）
    static let warmBackground = Color(red: 1, green: 0.89, blue: 0.79)
    
    // 全局调色板（与首页同步）- 高饱和度版本，与白色光球形成对比
    static let colorOptions: [Color] = [
        Color(hue: 0.58, saturation: 0.12, brightness: 0.75),    // 雾蓝灰（默认）- 低调高级
        Color(hue: 0.98, saturation: 0.60, brightness: 0.95),   // 粉红 - 现代活力（原珊瑚粉）
        Color(hue: 0.06, saturation: 0.58, brightness: 0.96),   // 活力橙 - 现代鲜明（原杏橙）
        Color(hue: 0.22, saturation: 0.45, brightness: 0.88),   // 青柠绿 - 清新自然
        Color(hue: 0.52, saturation: 0.42, brightness: 0.90),   // 天青蓝 - 清澈透亮
        Color(hue: 0.60, saturation: 0.48, brightness: 0.88),   // 钴蓝 - 沉稳深邃
        Color(hue: 0.78, saturation: 0.38, brightness: 0.88),   // 薰衣草紫 - 优雅梦幻
        Color(hue: 0.04, saturation: 0.52, brightness: 0.97)    // 暖橙 - 现代温暖（原暖杏）
    ]
    
    // 根据索引获取颜色
    static func color(at index: Int) -> Color {
        colorOptions[index % colorOptions.count]
    }
}

// MARK: - 模块渐变背景
struct ModuleBackgroundView: View {
    var themeColor: Color = YuanyuanTheme.warmBackground
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .white, location: 0.0),
                .init(color: themeColor.opacity(0.35), location: 0.45),
                .init(color: .white, location: 1.0)
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
    
    // 计算深色标题颜色
    private var titleColor: Color {
        let uiColor = UIColor(themeColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.3, 1.0), brightness: brightness * 0.55, opacity: alpha)
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

// MARK: - Tab选择器样式 - 跟随主题色调
struct ModuleTabButton: View {
    let title: String
    let value: String
    let isSelected: Bool
    let action: () -> Void
    var themeColor: Color = YuanyuanTheme.warmBackground  // 可选主题色参数
    
    // 计算深色版本
    private var indicatorColor: Color {
        let uiColor = UIColor(themeColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.4, 1.0), brightness: brightness * 0.6, opacity: alpha)
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

// ===== 全屏图片预览（单张） =====
struct FullScreenImageView: View {
    let image: UIImage
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(opacity)
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(dragOffset)
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
                                // 只有在未缩放或缩放为1时才允许拖拽关闭
                                if scale <= 1.0 {
                                    dragOffset = value.translation
                                    // 根据拖拽距离调整透明度
                                    let dragDistance = abs(value.translation.height)
                                    opacity = max(0.3, 1.0 - dragDistance / 300.0)
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
        }
        .onTapGesture {
            // 单击关闭（如果未缩放且未拖拽）
            if scale <= 1.0 && dragOffset == .zero {
                HapticFeedback.light()
                onDismiss()
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
                    
                    // 保存按钮（Liquid glass效果）
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
                                
                                // 黄绿色渐变叠加层（与app整体风格一致）
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.7),
                                                Color(red: 0.78, green: 0.98, blue: 0.2).opacity(0.5)
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
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(dragOffset)
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




