import SwiftUI
import UIKit
import Photos

// ===== 灰色气泡加载动画 =====
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




