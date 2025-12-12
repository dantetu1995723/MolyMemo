import SwiftUI
import UIKit

/// 安装一个「只在横向意图时才会开始」的 UIPanGestureRecognizer 到宿主 view（superview）上。
/// - 目的：卡片区域竖滑时不拦截，让外层 ScrollView 顺畅滚动；横滑时稳定驱动卡片翻页。
struct HorizontalPanGestureInstaller: UIViewRepresentable {
    /// 横向意图判定比例：|vx| 必须明显大于 |vy| 才开始识别
    var directionRatio: CGFloat = 1.15
    
    var onChanged: (CGFloat) -> Void
    /// - Parameters:
    ///   - translationX: 结束时的横向位移
    ///   - velocityX: 结束时的横向速度（pt/s），用于支持“短距离快速甩动”也能翻页
    var onEnded: (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        view.isUserInteractionEnabled = false // 不占用点击命中，手势安装在祖先 view 上
        context.coordinator.markerView = view
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.directionRatio = directionRatio
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.markerView = uiView
        
        // superview 可用时再安装；避免 SwiftUI 背景/前景分支导致挂在“非触摸祖先”上
        guard let host = resolveHostView(for: uiView) else { return }
        context.coordinator.installIfNeeded(on: host)
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func resolveHostView(for view: UIView) -> UIView? {
        guard var candidate = view.superview else { return nil }
        
        // 向上找几层：尽量挂到真正包住内容、会参与 hit-test 祖先链的视图上
        //（SwiftUI 可能会为 background/overlay 生成不同分支）
        var best: UIView = candidate
        var depth = 0
        
        while let next = candidate.superview, depth < 5 {
            // window 再往上没有意义
            if next is UIWindow { break }
            best = next
            candidate = next
            depth += 1
        }
        return best
    }
    
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var directionRatio: CGFloat = 1.15
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void = { _, _ in }
        
        /// 用于限定手势只在对应 SwiftUI 区域内生效（避免多个卡片安装到同一宿主后互相抢）
        weak var markerView: UIView?
        
        private weak var hostView: UIView?
        private var pan: UIPanGestureRecognizer?
        
        func installIfNeeded(on host: UIView) {
            // 如果已经安装在同一个 host 上，直接返回
            if hostView === host, pan != nil { return }
            
            uninstall()
            
            hostView = host
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            host.addGestureRecognizer(recognizer)
            pan = recognizer
        }
        
        func uninstall() {
            if let pan, let hostView {
                hostView.removeGestureRecognizer(pan)
            }
            pan = nil
            hostView = nil
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let hostView, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: hostView)
            // 允许慢速横滑：如果速度很小，用 translation 的趋势兜底
            if abs(v.x) < 30, abs(v.y) < 30 {
                let t = pan.translation(in: hostView)
                if abs(t.x) < 2, abs(t.y) < 2 { return false }
                return abs(t.x) > abs(t.y) * directionRatio
            }
            return abs(v.x) > abs(v.y) * directionRatio
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let hostView, let markerView else { return true }
            // 仅当触摸起点落在 markerView 的范围内，才接管该手势
            let locationInHost = touch.location(in: hostView)
            let locationInMarker = hostView.convert(locationInHost, to: markerView)
            return markerView.bounds.contains(locationInMarker)
        }
        
        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let hostView else { return }
            let translation = pan.translation(in: hostView).x
            
            switch pan.state {
            case .began, .changed:
                onChanged(translation)
            case .ended, .cancelled, .failed:
                let velocityX = pan.velocity(in: hostView).x
                onEnded(translation, velocityX)
            default:
                break
            }
        }
    }
    
    /// 一个透明占位 view：不参与命中，避免挡住 SwiftUI 子视图的点击。
    private final class PassthroughView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            false
        }
    }
}

