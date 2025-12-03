import SwiftUI

struct TechPlanetView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseAnimation: Bool = false
    
    // 入场动画状态
    @State private var planetScale: CGFloat = 0.3
    @State private var planetOpacity: Double = 0
    @State private var showRipples: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            let planetSize = min(geometry.size.width, geometry.size.height) * 0.75
            
            ZStack {
                ShadowLayer(planetSize: planetSize, pulseAnimation: pulseAnimation)
                    .opacity(planetOpacity)
                
                if showRipples {
                    RippleEffectView(planetSize: planetSize)
                        .transition(.opacity)
                }
                
                AvatarWithGlassView(planetSize: planetSize)
                    .scaleEffect(planetScale)
                    .opacity(planetOpacity)
            }
            .frame(width: planetSize, height: planetSize)
            .scaleEffect(appState.planetScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.42)
        }
        .onAppear {
            // 头像飞入
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05)) {
                planetScale = 1.0
                planetOpacity = 1.0
            }
            
            // 波纹动画出现
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeIn(duration: 0.3)) {
                    showRipples = true
                }
            }
            
            // 呼吸动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                appState.planetScale = 0.95
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    appState.planetScale = 1.0
                }
            }
        }
    }
}

// MARK: - 外层阴影
struct ShadowLayer: View {
    let planetSize: CGFloat
    let pulseAnimation: Bool
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.12)
                    ],
                    center: .center,
                    startRadius: planetSize * 0.4,
                    endRadius: planetSize * 0.65
                )
            )
            .frame(width: planetSize * 1.3, height: planetSize * 1.3)
            .blur(radius: 25)
            .offset(y: planetSize * 0.05)
            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
    }
}

// MARK: - 波纹效果
struct RippleEffectView: View {
    let planetSize: CGFloat
    @State private var ripples: [RippleState] = []
    
    var body: some View {
        ZStack {
            ForEach(ripples) { ripple in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(ripple.opacity * 0.6),
                                Color.white.opacity(ripple.opacity * 0.3),
                                Color.black.opacity(ripple.opacity * 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: planetSize * ripple.scale, height: planetSize * ripple.scale)
                    .opacity(ripple.opacity)
            }
        }
        .onAppear {
            startRippleAnimation()
        }
    }
    
    private func startRippleAnimation() {
        // 创建4个波纹，依次触发
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                createRipple()
            }
        }
    }
    
    private func createRipple() {
        let ripple = RippleState()
        ripples.append(ripple)
        
        // 动画：从1.0放大到2.2倍，透明度从0.8降到0
        withAnimation(.easeOut(duration: 2.4)) {
            if let index = ripples.firstIndex(where: { $0.id == ripple.id }) {
                ripples[index].scale = 2.2
                ripples[index].opacity = 0
            }
        }
        
        // 动画结束后移除
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            ripples.removeAll { $0.id == ripple.id }
            // 持续创建新波纹
            createRipple()
        }
    }
}

// MARK: - 波纹状态
struct RippleState: Identifiable {
    let id = UUID()
    var scale: CGFloat = 1.0
    var opacity: Double = 0.8
}

// MARK: - 头像和玻璃
struct AvatarWithGlassView: View {
    let planetSize: CGFloat
    
    var body: some View {
        ZStack {
            Image("Agent")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: planetSize, height: planetSize)
                .clipShape(Circle())
            
            Circle()
                .fill(.ultraThinMaterial.opacity(0.2))
                .frame(width: planetSize, height: planetSize)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .blur(radius: 15)
                .frame(width: planetSize, height: planetSize)
                .offset(x: -planetSize * 0.15, y: -planetSize * 0.15)
            
            // 动效层已移除，保留静态质感
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
        )
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                .padding(-1)
        )
        .frame(width: planetSize, height: planetSize)
        .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 15)
        .shadow(color: Color.black.opacity(0.08), radius: 15, x: 0, y: 8)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.08, blue: 0.12),
                Color(red: 0.12, green: 0.12, blue: 0.15),
                Color(red: 0.05, green: 0.05, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        TechPlanetView()
            .environmentObject(AppState())
    }
}
