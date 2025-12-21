import SwiftUI

struct StickyBallAnimationView: View {
    var inputFrame: CGRect
    var toolboxFrame: CGRect
    @Binding var isAnimating: Bool
    var isCanceling: Bool = false
    var audioPower: CGFloat = 0.0  // 0 = 静音，>0 = 说话中
    var onComplete: () -> Void
    
    @State private var startTime = Date()
    @State private var smoothPower: CGFloat = 0.0  // 平滑过渡的音频值
    
    // 动画时长常量
    private let turnBlueDuration: Double = 0.1
    private let mergeDuration: Double = 0.3
    private let holdDuration: Double = 0.05
    private let shrinkToBallDuration: Double = 0.5 // 稍微延长，配合曲线更丝滑
    
    @State private var introFinished = false
    @State private var didTriggerComplete = false
    
    private var currentColor: Color {
        isCanceling ? Color(hex: "FF453A") : Color(hex: "007AFF")
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                
                let safeInputFrame = inputFrame.width > 0 ? inputFrame : CGRect(x: 16, y: size.height - 100, width: size.width - 80, height: 44)
                let safeToolboxFrame = toolboxFrame.width > 0 ? toolboxFrame : CGRect(x: size.width - 60, y: size.height - 100, width: 44, height: 44)
                
                if elapsed < turnBlueDuration {
                    // --- 阶段 1: 仅变色 (清晰模式) ---
                    drawInitialShapes(context: context, inputRect: safeInputFrame, toolboxRect: safeToolboxFrame)
                } else {
                    // --- 阶段 2, 3, 4 & 以后: 融合 + 长条保持 + 内缩成球 (元球滤镜模式) ---
                    // 收紧阈值 (0.5 -> 0.65)，让边缘更清爽，不肉感
                    context.addFilter(.alphaThreshold(min: 0.65, color: currentColor))
                    context.drawLayer { ctx in
                        // 融合阶段使用更小的模糊 (6pt)，确保衔接处不产生多余的"肥油"
                        let isMerging = elapsed < turnBlueDuration + mergeDuration
                        ctx.addFilter(.blur(radius: isMerging ? 6 : 12))
                        
                        if isMerging {
                            // 阶段 2: 粘滞融合 (现在带滤镜，更水润)
                            let progress = max(0, (elapsed - turnBlueDuration) / mergeDuration)
                            drawMerging(context: ctx, inputRect: safeInputFrame, toolboxRect: safeToolboxFrame, progress: progress)
                        } else {
                            let fullRect = getFullRect(inputRect: safeInputFrame, toolboxRect: safeToolboxFrame)
                            
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
                                if rawProgress >= 1.0 && !didTriggerComplete {
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
            }
            .onChange(of: audioPower) { _, newValue in
                // 平滑过渡音频值
                withAnimation(.linear(duration: 0.08)) {
                    smoothPower = newValue
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startTime = Date()
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
        if smoothPower > 0.05 {
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
        let pulse = sin(time * 3.0) * 3.0 * smoothPower
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
            let orbitRadius = (config.orbitBase + smoothPower * 15 + sin(time * 3.0 + config.phase) * 5) * progress
            
            // 动态球半径：随音频变化
            let ballRadius = (config.radiusBase + smoothPower * 8 + sin(time * 4.0 + config.phase) * 3) * progress
            
            let sx = centerX + cos(dynamicAngle) * orbitRadius
            let sy = centerY + sin(dynamicAngle) * orbitRadius
            
            let sRect = CGRect(x: sx - ballRadius, y: sy - ballRadius, 
                              width: ballRadius * 2, height: ballRadius * 2)
            context.fill(Path(ellipseIn: sRect), with: .color(currentColor))
        }
    }
    
    private func drawInitialShapes(context: GraphicsContext, inputRect: CGRect, toolboxRect: CGRect) {
        let inputPath = Path(roundedRect: inputRect, cornerRadius: inputRect.height / 2)
        context.fill(inputPath, with: .color(currentColor))
        
        let toolboxPath = Path(ellipseIn: toolboxRect)
        context.fill(toolboxPath, with: .color(currentColor))
    }
    
    private func drawMerging(context: GraphicsContext, inputRect: CGRect, toolboxRect: CGRect, progress: CGFloat) {
        // 1. 绘制两个主体
        drawInitialShapes(context: context, inputRect: inputRect, toolboxRect: toolboxRect)
        
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
        return CGRect(
            x: inputRect.minX,
            y: inputRect.minY,
            width: toolboxRect.maxX - inputRect.minX,
            height: inputRect.height
        )
    }
}
