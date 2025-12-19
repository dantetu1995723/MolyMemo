import SwiftUI

struct StickyBallAnimationView: View {
    var inputFrame: CGRect
    var toolboxFrame: CGRect
    @Binding var isAnimating: Bool
    var onComplete: () -> Void
    
    @State private var startTime = Date()
    
    // 动画时长常量
    private let turnBlueDuration: Double = 0.1
    private let mergeDuration: Double = 0.3
    private let holdDuration: Double = 0.05
    private let shrinkToBallDuration: Double = 0.5 // 稍微延长，配合曲线更丝滑
    
    @State private var introFinished = false
    @State private var didTriggerComplete = false
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                
                let safeInputFrame = inputFrame.width > 0 ? inputFrame : CGRect(x: 16, y: size.height - 100, width: size.width - 80, height: 44)
                let safeToolboxFrame = toolboxFrame.width > 0 ? toolboxFrame : CGRect(x: size.width - 60, y: size.height - 100, width: 44, height: 44)
                
                if elapsed < turnBlueDuration + mergeDuration {
                    // --- 阶段 1 & 2: 变蓝 + 粘滞融合 (清晰模式) ---
                    let progress = max(0, (elapsed - turnBlueDuration) / mergeDuration)
                    drawMerging(context: context, inputRect: safeInputFrame, toolboxRect: safeToolboxFrame, progress: progress)
                    
                } else {
                    // --- 阶段 3, 4 & 以后: 长条保持 + 内缩成球 + 持续循环 (元球滤镜模式) ---
                    context.addFilter(.alphaThreshold(min: 0.5, color: .blue))
                    context.drawLayer { ctx in
                        ctx.addFilter(.blur(radius: 12))
                        
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
        .ignoresSafeArea()
        .onAppear {
            startTime = Date()
        }
    }
    
    // 绘制流体球系统 (包含大球和旋转小球)
    private func drawFluidBallSystem(context: GraphicsContext, fullRect: CGRect, progress: CGFloat, screenSize: CGSize) {
        let bigRadius: CGFloat = 50 
        let targetY = fullRect.maxY - bigRadius
        let targetCenter = CGPoint(x: screenSize.width / 2, y: targetY)
        let startCenter = CGPoint(x: fullRect.midX, y: fullRect.midY)
        
        // 1. 计算大球当前形变
        let currentWidth = fullRect.width + (bigRadius * 2 - fullRect.width) * progress
        let currentHeight = fullRect.height + (bigRadius * 2 - fullRect.height) * progress
        let centerX = startCenter.x + (targetCenter.x - startCenter.x) * progress
        let centerY = startCenter.y + (targetCenter.y - startCenter.y) * progress
        
        let bigRect = CGRect(x: centerX - currentWidth / 2, y: centerY - currentHeight / 2, width: currentWidth, height: currentHeight)
        context.fill(Path(roundedRect: bigRect, cornerRadius: currentHeight / 2), with: .color(.blue))
        
        // 2. 绘制旋转小球
        // 永远基于绝对时间旋转，确保绝对平滑
        let absoluteTime = Date().timeIntervalSinceReferenceDate
        let rotationAngle = absoluteTime * (2 * .pi / 7.0) 
        
        // 小球随进度从中心向边缘扩散
        let smallRadius: CGFloat = 25 * progress 
        let orbitRadius: CGFloat = 28 * progress 
        
        let smallCenterX = centerX + cos(rotationAngle) * orbitRadius
        let smallCenterY = centerY + sin(rotationAngle) * orbitRadius
        
        let smallRect = CGRect(x: smallCenterX - smallRadius, y: smallCenterY - smallRadius, width: smallRadius * 2, height: smallRadius * 2)
        context.fill(Path(ellipseIn: smallRect), with: .color(.blue))
    }
    
    private func drawInitialShapes(context: GraphicsContext, inputRect: CGRect, toolboxRect: CGRect) {
        let inputPath = Path(roundedRect: inputRect, cornerRadius: 24)
        context.fill(inputPath, with: .color(.blue))
        
        let toolboxPath = Path(ellipseIn: toolboxRect)
        context.fill(toolboxPath, with: .color(.blue))
    }
    
    private func drawMerging(context: GraphicsContext, inputRect: CGRect, toolboxRect: CGRect, progress: CGFloat) {
        // 绘制两个主体
        drawInitialShapes(context: context, inputRect: inputRect, toolboxRect: toolboxRect)
        
        // 绘制粘滞桥梁
        let c1 = CGPoint(x: inputRect.maxX - 22, y: inputRect.midY)
        let r1: CGFloat = 22
        let c2 = CGPoint(x: toolboxRect.midX, y: toolboxRect.midY)
        let r2: CGFloat = 22
        
        var bridgePath = Path()
        let p1 = CGPoint(x: c1.x, y: c1.y - r1)
        let p2 = CGPoint(x: c2.x, y: c2.y - r2)
        let p3 = CGPoint(x: c2.x, y: c2.y + r2)
        let p4 = CGPoint(x: c1.x, y: c1.y + r1)
        
        // 粘滞程度：由凹变直
        let offset = (r1 * 0.9) * (1 - progress)
        
        bridgePath.move(to: p1)
        bridgePath.addQuadCurve(to: p2, control: CGPoint(x: (c1.x + c2.x) / 2, y: c1.y - r1 + offset))
        bridgePath.addLine(to: p3)
        bridgePath.addQuadCurve(to: p4, control: CGPoint(x: (c1.x + c2.x) / 2, y: c1.y + r1 - offset))
        bridgePath.closeSubpath()
        
        context.fill(bridgePath, with: .color(.blue))
    }
    
    private func drawFullBar(context: GraphicsContext, fullRect: CGRect) {
        let path = Path(roundedRect: fullRect, cornerRadius: 24)
        context.fill(path, with: .color(.blue))
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
