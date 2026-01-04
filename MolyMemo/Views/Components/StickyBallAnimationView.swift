import SwiftUI
import UIKit

struct StickyBallAnimationView: View {
    var inputFrame: CGRect
    var toolboxFrame: CGRect
    @Binding var isAnimating: Bool
    var isCanceling: Bool = false
    /// true：球 -> 输入框（逆向动画）
    var isReversing: Bool = false
    var audioPower: CGFloat = 0.0  // 0 = 静音，>0 = 说话中（已在外部平滑处理）
    var onComplete: () -> Void
    var onReverseComplete: (() -> Void)? = nil
    
    @State private var startTime = Date()
    
    // 动画时长常量
    // 说明：这里同时影响"输入框->球"和"球->输入框"的速度
    /// 输入框“从中间向两边铺蓝”的过渡时长（更柔和的变色过程）
    // 更快的“输入框 -> 球”节奏：按住后更快完成收缩成球
    private let turnBlueDuration: Double = 0.12
    private let mergeDuration: Double = 0.10
    private let holdDuration: Double = 0.01
    private let shrinkToBallDuration: Double = 0.18
    
    @State private var introFinished = false
    @State private var didTriggerComplete = false
    @State private var didTriggerReverseComplete = false
    
    private var currentColor: Color {
        isCanceling ? Color(hex: "FF453A") : Color(hex: "007AFF")
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            // 录音变球在真机 120Hz 下容易在“融合阶段”掉帧：
            // - blur + alphaThreshold 会对一个很大的像素区域做滤镜
            // - 缩成球后区域变小，因此后续阶段不明显
            // 这里做两层减负：
            // 1) Canvas 异步渲染（减少主线程阻塞）
            // 2) 对滤镜阶段做 clip，只在输入框+toolbox 的包围盒附近处理像素
            Canvas(rendersAsynchronously: true) { context, size in
                let totalDuration = (turnBlueDuration + mergeDuration + holdDuration + shrinkToBallDuration)
                let rawElapsed = timeline.date.timeIntervalSince(startTime)
                // 逆向：把“时间”映射回正向的时间轴，这样可以复用同一套绘制逻辑
                let elapsed = isReversing ? max(0, totalDuration - rawElapsed) : rawElapsed
                
                let safeInputFrame = inputFrame.width > 0 ? inputFrame : CGRect(x: 16, y: size.height - 100, width: size.width - 80, height: 44)
                let hasToolbox = toolboxFrame.width > 1 && toolboxFrame.height > 1
                let safeToolboxFrame = hasToolbox ? toolboxFrame : .zero
                
                if elapsed < turnBlueDuration {
                    // --- 阶段 1: “中间蓝、两边白渐变”过渡，蓝色由中间向两侧铺开（清晰模式） ---
                    let p = max(0, min(1, elapsed / turnBlueDuration))
                    drawInitialShapes(context: context, inputRect: safeInputFrame, toolboxRect: safeToolboxFrame, colorSpreadProgress: p)
                } else {
                    // --- 阶段 2, 3, 4 & 以后: 融合 + 长条保持 + 内缩成球 (元球滤镜模式) ---
                    // 收紧阈值 (0.5 -> 0.65)，让边缘更清爽，不肉感
                    context.addFilter(.alphaThreshold(min: 0.65, color: currentColor))
                    context.drawLayer { ctx in
                        let isMerging = elapsed < turnBlueDuration + mergeDuration
                        // 融合阶段使用更小的模糊 (6pt)，确保衔接处不产生多余的"肥油"
                        let blurRadius: CGFloat = (isMerging && hasToolbox) ? 6 : 12
                        ctx.addFilter(.blur(radius: blurRadius))
                        
                        // 关键性能优化：
                        // 在融合阶段，inputRect + toolboxRect 覆盖屏幕下方一大块区域，
                        // blur/threshold 会对“整层”做像素处理，120Hz 下更容易掉帧。
                        // 这里将绘制（以及滤镜处理）限制在包围盒附近，显著减少像素工作量。
                        let baseRect = getFullRect(inputRect: safeInputFrame, toolboxRect: safeToolboxFrame)
                        let pad = max(32, blurRadius * 4) // blur 采样需要更大的边界，避免被裁切出硬边
                        let clipRect = baseRect.insetBy(dx: -pad, dy: -pad)
                        ctx.clip(to: Path(clipRect))
                        
                        if isMerging {
                            // 阶段 2: 粘滞融合 (现在带滤镜，更水润)
                            let progress = max(0, (elapsed - turnBlueDuration) / mergeDuration)
                            drawMerging(context: ctx, inputRect: safeInputFrame, toolboxRect: safeToolboxFrame, progress: progress)
                        } else {
                            let fullRect = baseRect
                            
                            if elapsed < turnBlueDuration + mergeDuration + holdDuration {
                                // 阶段 3: 保持长条
                                drawFullBar(context: ctx, fullRect: fullRect)
                            } else {
                                // 阶段 4 及以后: 内缩 + 持续旋转
                                let shrinkElapsed = elapsed - (turnBlueDuration + mergeDuration + holdDuration)
                                let rawProgress = min(1.0, shrinkElapsed / shrinkToBallDuration)
                                // 使用 EaseOutQuart 曲线，让收缩更有弹性感
                                let curveProgress = 1.0 - pow(1.0 - rawProgress, 4.0)
                                
                                drawFluidBallSystem(context: ctx, fullRect: fullRect, progress: curveProgress, screenSize: size)
                                
                                // 动画结束回调（仅触发一次，用于显示文字框）
                                if !isReversing, rawProgress >= 1.0, !didTriggerComplete {
                                    DispatchQueue.main.async {
                                        if !didTriggerComplete {
                                            didTriggerComplete = true
                                            onComplete()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 逆向动画结束回调（仅触发一次，用于收起 overlay）
                if isReversing, rawElapsed >= totalDuration, !didTriggerReverseComplete {
                    DispatchQueue.main.async {
                        if !didTriggerReverseComplete {
                            didTriggerReverseComplete = true
                            onReverseComplete?()
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startTime = Date()
        }
        .onChange(of: isReversing) { _, _ in
            // 切换方向时重置时间轴，保证从“当前态”顺滑开跑
            startTime = Date()
            didTriggerComplete = false
            didTriggerReverseComplete = false
        }
    }
    
    // 绘制流体球系统
    private func drawFluidBallSystem(context: GraphicsContext, fullRect: CGRect, progress: CGFloat, screenSize: CGSize) {
        let bigRadius: CGFloat = 50 
        let targetY = fullRect.maxY - bigRadius
        let targetCenter = CGPoint(x: screenSize.width / 2, y: targetY)
        let startCenter = CGPoint(x: fullRect.midX, y: fullRect.midY)
        
        let centerX = startCenter.x + (targetCenter.x - startCenter.x) * progress
        let centerY = startCenter.y + (targetCenter.y - startCenter.y) * progress
        
        let absoluteTime = Date().timeIntervalSinceReferenceDate
        
        // 根据是否有声音选择不同的绘制模式
        if audioPower > 0.05 {
            // === 说话模式：多球不规则扩散（如截图所示）===
            drawSpeakingBlob(context: context, centerX: centerX, centerY: centerY, 
                           bigRadius: bigRadius, progress: progress, time: absoluteTime)
        } else {
            // === 静音模式：原有的单球 + 旋转小球 ===
            drawIdleBall(context: context, fullRect: fullRect, centerX: centerX, centerY: centerY,
                        bigRadius: bigRadius, progress: progress, time: absoluteTime)
        }
    }
    
    // 静音状态：主球 + 单个旋转小球
    private func drawIdleBall(context: GraphicsContext, fullRect: CGRect, centerX: CGFloat, centerY: CGFloat,
                              bigRadius: CGFloat, progress: CGFloat, time: TimeInterval) {
        // 主球形变
        let currentWidth = fullRect.width + (bigRadius * 2 - fullRect.width) * progress
        let currentHeight = fullRect.height + (bigRadius * 2 - fullRect.height) * progress
        
        let bigRect = CGRect(x: centerX - currentWidth / 2, y: centerY - currentHeight / 2, 
                            width: currentWidth, height: currentHeight)
        context.fill(Path(roundedRect: bigRect, cornerRadius: currentHeight / 2), with: .color(currentColor))
        
        // 旋转小球
        let rotationAngle = time * (2 * .pi / 7.0)
        let smallRadius: CGFloat = 25 * progress
        let orbitRadius: CGFloat = 28 * progress
        
        let smallCenterX = centerX + cos(rotationAngle) * orbitRadius
        let smallCenterY = centerY + sin(rotationAngle) * orbitRadius
        
        let smallRect = CGRect(x: smallCenterX - smallRadius, y: smallCenterY - smallRadius, 
                              width: smallRadius * 2, height: smallRadius * 2)
        context.fill(Path(ellipseIn: smallRect), with: .color(currentColor))
    }
    
    // 说话状态：多球不规则扩散形态（复刻截图效果）
    private func drawSpeakingBlob(context: GraphicsContext, centerX: CGFloat, centerY: CGFloat,
                                  bigRadius: CGFloat, progress: CGFloat, time: TimeInterval) {
        // 主球：带轻微脉冲
        let pulse = sin(time * 3.0) * 3.0 * audioPower
        let mainRadius = (bigRadius + pulse) * progress
        
        let mainRect = CGRect(x: centerX - mainRadius, y: centerY - mainRadius,
                             width: mainRadius * 2, height: mainRadius * 2)
        context.fill(Path(ellipseIn: mainRect), with: .color(currentColor))
        
        // 多个卫星球，形成不规则的 blob 形态
        let satelliteConfigs: [(baseAngle: Double, orbitBase: CGFloat, radiusBase: CGFloat, speed: Double, phase: Double)] = [
            (0.0,      35, 28, 0.8,  0.0),    // 右
            (0.5,      32, 24, 1.1,  0.7),    // 右上
            (1.0,      30, 22, 0.9,  1.4),    // 上
            (1.6,      34, 26, 1.0,  2.1),    // 左上
            (2.2,      36, 30, 0.7,  2.8),    // 左
            (2.8,      28, 20, 1.2,  3.5),    // 左下
            (3.5,      33, 25, 0.85, 4.2),    // 下
            (4.2,      31, 23, 1.05, 4.9),    // 右下
        ]
        
        for config in satelliteConfigs {
            // 动态角度：基础角度 + 缓慢旋转 + 随音频摆动
            let dynamicAngle = config.baseAngle + time * config.speed * 0.3 + sin(time * 2.5 + config.phase) * 0.15
            
            // 动态轨道半径：随音频扩张
            let orbitRadius = (config.orbitBase + audioPower * 15 + sin(time * 3.0 + config.phase) * 5) * progress
            
            // 动态球半径：随音频变化
            let ballRadius = (config.radiusBase + audioPower * 8 + sin(time * 4.0 + config.phase) * 3) * progress
            
            let sx = centerX + cos(dynamicAngle) * orbitRadius
            let sy = centerY + sin(dynamicAngle) * orbitRadius
            
            let sRect = CGRect(x: sx - ballRadius, y: sy - ballRadius, 
                              width: ballRadius * 2, height: ballRadius * 2)
            context.fill(Path(ellipseIn: sRect), with: .color(currentColor))
        }
    }
    
    private func drawInitialShapes(
        context: GraphicsContext,
        inputRect: CGRect,
        toolboxRect: CGRect,
        colorSpreadProgress: CGFloat
    ) {
        // 阶段 1 的“中间蓝、两边白渐变”应当以「输入框 + 工具箱」的整体宽度为坐标系，
        // 否则两者各自一套渐变，融合/相连那一帧会出现渐变断层。
        let overallRect = getFullRect(inputRect: inputRect, toolboxRect: toolboxRect)
        let unifiedShading = initialColorSpreadShading(in: overallRect, progress: colorSpreadProgress)
        let inputPath = Path(roundedRect: inputRect, cornerRadius: inputRect.height / 2)
        context.fill(inputPath, with: unifiedShading)
        
        if toolboxRect.width > 0 {
            let toolboxPath = Path(ellipseIn: toolboxRect)
            context.fill(toolboxPath, with: unifiedShading)
        }
    }
    
    private func drawMerging(context: GraphicsContext, inputRect: CGRect, toolboxRect: CGRect, progress: CGFloat) {
        // 1. 绘制主体
        // 融合阶段已进入 alphaThreshold 着色模式，这里保持纯色即可
        drawInitialShapes(context: context, inputRect: inputRect, toolboxRect: toolboxRect, colorSpreadProgress: 1.0)
        
        // 如果没有外部 toolbox，不需要绘制连接桥
        guard toolboxRect.width > 0 else { return }
        
        // 2. 绘制极细的内凹连接（物理上大幅缩减，靠滤镜还原丝滑感）
        let c1 = CGPoint(x: inputRect.maxX - 22, y: inputRect.midY)
        let c2 = CGPoint(x: toolboxRect.midX, y: toolboxRect.midY)
        let dist = c2.x - c1.x
        
        // 物理半径从 16 开始，随进度增长，始终小于 22，杜绝肿胀
        let rCurrent: CGFloat = 16 + (4 * progress)
        let pullIn = (1.0 - progress) // 融合初期拉力最强
        
        var bridgePath = Path()
        
        // 上边缘：深度内凹控制点
        let p1 = CGPoint(x: c1.x, y: c1.y - rCurrent)
        let p2 = CGPoint(x: c2.x, y: c2.y - rCurrent)
        let cp1 = CGPoint(x: c1.x + dist * 0.35, y: c1.y - rCurrent + (15 * pullIn))
        let cp2 = CGPoint(x: c1.x + dist * 0.65, y: c1.y - rCurrent + (15 * pullIn))
        
        // 下边缘
        let p3 = CGPoint(x: c2.x, y: c2.y + rCurrent)
        let p4 = CGPoint(x: c1.x, y: c1.y + rCurrent)
        let cp3 = CGPoint(x: c1.x + dist * 0.65, y: c1.y + rCurrent - (15 * pullIn))
        let cp4 = CGPoint(x: c1.x + dist * 0.35, y: c1.y + rCurrent - (15 * pullIn))
        
        bridgePath.move(to: p1)
        bridgePath.addCurve(to: p2, control1: cp1, control2: cp2)
        bridgePath.addLine(to: p3)
        bridgePath.addCurve(to: p4, control1: cp3, control2: cp4)
        bridgePath.closeSubpath()
        
        context.fill(bridgePath, with: .color(currentColor))
    }
    
    private func drawFullBar(context: GraphicsContext, fullRect: CGRect) {
        let path = Path(roundedRect: fullRect, cornerRadius: 24)
        context.fill(path, with: .color(currentColor))
    }
    
    private func getFullRect(inputRect: CGRect, toolboxRect: CGRect) -> CGRect {
        guard toolboxRect.width > 0 else { return inputRect }
        return CGRect(
            x: inputRect.minX,
            y: inputRect.minY,
            width: toolboxRect.maxX - inputRect.minX,
            height: inputRect.height
        )
    }

    // MARK: - Color Spread Shading (阶段 1)

    /// 阶段 1：实现“中间蓝、两边白渐变”，并让蓝色从中间向两侧铺开到全蓝。
    /// - progress: 0 -> 中间蓝/两边白渐变；1 -> 全蓝
    private func initialColorSpreadShading(in rect: CGRect, progress: CGFloat) -> GraphicsContext.Shading {
        // 取消态保持纯红，不做白边渐变（避免“取消”语义被稀释）
        guard !isCanceling else {
            return .color(currentColor)
        }
        
        let p = max(0, min(1, progress))
        if p >= 0.999 { return .color(currentColor) }
        
        // 边缘“白色”随进度逐步过渡到蓝色；同时白边宽度逐步收缩（蓝色从中间向两侧铺开）
        // 目标：两边白尽可能大、蓝芯尽可能小，并且从渐变到全蓝的过程更明显。
        //
        // - maxEdgeWidth 越接近 0.5：初始白边越宽（蓝芯越细）
        // - shrinkCurvePow < 1：前期收缩更慢，过渡更“可见”
        let maxEdgeWidth: CGFloat = 0.485
        let shrinkCurvePow: CGFloat = 0.55
        let edgeWidth = min(0.49, max(0.001, maxEdgeWidth * pow(1 - p, shrinkCurvePow)))
        
        // 白色保持更久：用缓入曲线，让边缘从“白”到“蓝”变得更慢、更有层次
        let edgeToBlueT = pow(p, 2.2)
        let edgeColor = Color(mixUIColor(.white, systemBlueLike, t: edgeToBlueT))

        // 中心蓝色更浅：阶段 1 先用“淡蓝芯”，再随进度逐步加深到标准蓝
        // - 初始 t=0.50：掺 50% 白（更浅）
        // - 结束 t->1.0：回到标准蓝（与后续阶段一致）
        let centerToBlueT = 0.50 + 0.50 * pow(p, 1.8)
        let centerColor = Color(mixUIColor(.white, systemBlueLike, t: centerToBlueT))
        
        let gradient = Gradient(stops: [
            .init(color: edgeColor, location: 0.0),
            .init(color: centerColor, location: edgeWidth),
            .init(color: centerColor, location: 1.0 - edgeWidth),
            .init(color: edgeColor, location: 1.0),
        ])
        
        return .linearGradient(
            gradient,
            startPoint: CGPoint(x: rect.minX, y: rect.midY),
            endPoint: CGPoint(x: rect.maxX, y: rect.midY)
        )
    }

    private var systemBlueLike: UIColor {
        // 与 Color(hex:"007AFF") 保持一致的蓝（更稳定，避免不同系统版本 Color->UIColor 的色域差异）
        UIColor(red: 0, green: 122.0 / 255.0, blue: 1.0, alpha: 1.0)
    }

    private func mixUIColor(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
        let tt = max(0, min(1, t))
        var ar: CGFloat = 1, ag: CGFloat = 1, ab: CGFloat = 1, aa: CGFloat = 1
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 1
        _ = a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        _ = b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * tt,
            green: ag + (bg - ag) * tt,
            blue: ab + (bb - ab) * tt,
            alpha: aa + (ba - aa) * tt
        )
    }
}
