import SwiftUI

struct VoiceRecordingOverlay: View {
    @Binding var isRecording: Bool
    @Binding var isCanceling: Bool
    var audioPower: CGFloat
    var transcript: String
    var inputFrame: CGRect
    var toolboxFrame: CGRect
    
    @State private var isAnimatingEntry = true
    @State private var showMainUI = false
    
    var body: some View {
        ZStack {
            // 背景渐变
            Color.black.opacity(showMainUI ? 0.3 : 0.0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: showMainUI)
            
            if isAnimatingEntry {
                // 进入动画：粘滞球融合 + 缩小
                StickyBallAnimationView(
                    inputFrame: inputFrame,
                    toolboxFrame: toolboxFrame,
                    isAnimating: $isAnimatingEntry,
                    onComplete: {
                        withAnimation {
                            showMainUI = true
                        }
                    }
                )
            }
            
            if showMainUI {
                // 录音主界面
                VStack(spacing: 30) {
                    Spacer()
                    
                    // 文字识别结果
                    VStack(spacing: 12) {
                        Text(isCanceling ? "松开手指，取消发送" : "正在聆听...")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(transcript)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .frame(height: 80)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                    // 录音球 (最终状态)
                    ZStack {
                        // 呼吸或波动效果
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 80 + audioPower * 40, height: 80 + audioPower * 40)
                        
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: isCanceling ? "xmark" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 60)
                    .safeAreaPadding(.bottom)
                }
                .transition(.opacity)
            }
        }
    }
}
