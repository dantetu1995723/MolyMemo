import SwiftUI

struct StickyBallAnimationView: View {
    var inputFrame: CGRect
    var toolboxFrame: CGRect
    @Binding var isAnimating: Bool
    var onComplete: () -> Void
    
    @State private var startTime = Date()
    
    // 动画时长常量
    private let turnBlueDuration: Double = 0.1
    private let mergeDuration: Double = 0.4
    private let holdDuration: Double = 0.05
    private let shrinkDuration: Double = 0.5
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                
                // 处理无效坐标的兜底逻辑
                let safeInputFrame = inputFrame.width > 0 ? inputFrame : CGRect(x: 16, y: size.height - 100, width: size.width - 80, height: 44)
                let safeToolboxFrame = toolboxFrame.width > 0 ? toolboxFrame : CGRect(x: size.width - 60, y: size.height - 100, width: 44, height: 44)
                
                if elapsed < turnBlueDuration {
                    // 阶段 1: 变蓝
                    drawInitialShapes(context: context, inputRect: safeInputFrame, toolboxRect: safeToolboxFrame)
                } else if elapsed < turnBlueDuration + mergeDuration {
                    // 阶段 2: 粘滞融合
                    let progress = (elapsed - turnBlueDuration) / mergeDuration
                    drawMerging(context: context, inputRect: safeInputFrame, toolboxRect: safeToolboxFrame, progress: progress)
                } else if elapsed < turnBlueDuration + mergeDuration + holdDuration {
                    // 阶段 3: 融合后的长条保持
                    let fullRect = getFullRect(inputRect: safeInputFrame, toolboxRect: safeToolboxFrame)
                    drawFullBar(context: context, fullRect: fullRect)
                } else if elapsed < turnBlueDuration + mergeDuration + holdDuration + shrinkDuration {
                    // 阶段 4: 缩回成球
                    let progress = (elapsed - turnBlueDuration - mergeDuration - holdDuration) / shrinkDuration
                    let fullRect = getFullRect(inputRect: safeInputFrame, toolboxRect: safeToolboxFrame)
                    drawShrinking(context: context, fullRect: fullRect, progress: progress, screenSize: size)
                } else {
                    // 动画结束
                    DispatchQueue.main.async {
                        if isAnimating {
                            isAnimating = false
                            onComplete()
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
    
    private func drawShrinking(context: GraphicsContext, fullRect: CGRect, progress: CGFloat, screenSize: CGSize) {
        // 目标球：80x80, 底部居中
        let targetRadius: CGFloat = 40
        // 这里的 Y 轴计算要和 VoiceRecordingOverlay 保持一致
        // VoiceRecordingOverlay 中，球在 VStack 底部，padding 60
        let targetY = screenSize.height - 60 - targetRadius - 20 // 20 是安全区调整
        let targetCenter = CGPoint(x: screenSize.width / 2, y: targetY)
        
        let startCenter = CGPoint(x: fullRect.midX, y: fullRect.midY)
        
        // 宽高插值
        let currentWidth = fullRect.width + (targetRadius * 2 - fullRect.width) * progress
        let currentHeight = fullRect.height + (targetRadius * 2 - fullRect.height) * progress
        
        // 中心点插值
        let centerX = startCenter.x + (targetCenter.x - startCenter.x) * progress
        let centerY = startCenter.y + (targetCenter.y - startCenter.y) * progress
        
        let drawRect = CGRect(
            x: centerX - currentWidth / 2,
            y: centerY - currentHeight / 2,
            width: currentWidth,
            height: currentHeight
        )
        
        let path = Path(roundedRect: drawRect, cornerRadius: max(currentHeight / 2, 24))
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
