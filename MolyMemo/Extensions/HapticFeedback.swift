import UIKit

// MARK: - 触感反馈管理
enum HapticFeedback {
    // 复用 generator，避免每次 new 导致“冷启动前几次不响”
    // 关键：对外 API 保持同步可调用；内部确保在主线程使用 UIKit generator，避免并发/编译隔离问题。
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static var notificationGenerator: UINotificationFeedbackGenerator?
    private static var selectionGenerator: UISelectionFeedbackGenerator?
    
    private static func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    private static func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let existing = impactGenerators[style] { return existing }
        let g = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = g
        return g
    }
    
    private static func getNotificationGenerator() -> UINotificationFeedbackGenerator {
        if let g = notificationGenerator { return g }
        let g = UINotificationFeedbackGenerator()
        notificationGenerator = g
        return g
    }
    
    private static func getSelectionGenerator() -> UISelectionFeedbackGenerator {
        if let g = selectionGenerator { return g }
        let g = UISelectionFeedbackGenerator()
        selectionGenerator = g
        return g
    }
    
    /// 预热：建议在页面出现时调用一次，提升第一次触发的命中率
    static func warmUp() {
        onMain {
            impactGenerator(for: .light).prepare()
            impactGenerator(for: .medium).prepare()
            impactGenerator(for: .heavy).prepare()
            impactGenerator(for: .soft).prepare()
            impactGenerator(for: .rigid).prepare()
            getNotificationGenerator().prepare()
            getSelectionGenerator().prepare()
        }
    }
    
    /// 轻触反馈
    static func light() {
        impact(style: .light, intensity: 1.0)
    }
    
    /// 中等反馈
    static func medium() {
        impact(style: .medium, intensity: 1.0)
    }
    
    /// 重触反馈
    static func heavy() {
        impact(style: .heavy, intensity: 1.0)
    }
    
    /// 柔和反馈 - 温和但有质感
    static func soft() {
        impact(style: .soft, intensity: 1.0)
    }
    
    /// 硬朗反馈 - 清脆有力
    static func rigid() {
        impact(style: .rigid, intensity: 1.0)
    }
    
    /// 超强反馈 - 最明显的触感
    static func intense() {
        impact(style: .heavy, intensity: 1.0)
    }
    
    /// 自定义强度反馈
    /// - Parameters:
    ///   - style: 震动风格
    ///   - intensity: 强度 (0.0 - 1.0)，默认 1.0 最强
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .heavy, intensity: CGFloat = 1.0) {
        onMain {
            let g = impactGenerator(for: style)
            g.prepare()
            g.impactOccurred(intensity: intensity)
        }
    }
    
    /// 成功反馈
    static func success() {
        onMain {
            let g = getNotificationGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        }
    }
    
    /// 警告反馈
    static func warning() {
        onMain {
            let g = getNotificationGenerator()
            g.prepare()
            g.notificationOccurred(.warning)
        }
    }
    
    /// 错误反馈
    static func error() {
        onMain {
            let g = getNotificationGenerator()
            g.prepare()
            g.notificationOccurred(.error)
        }
    }
    
    /// 选择改变反馈 - 增强版
    static func selection() {
        onMain {
            let g = getSelectionGenerator()
            g.prepare()
            g.selectionChanged()
        }
    }
    
    /// 连续选择反馈 - 更明显的选择触感
    static func selectionStrong() {
        impact(style: .rigid, intensity: 0.8)
    }
}

