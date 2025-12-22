import SwiftUI

// 首页顶部模块 - 包含标题、模式切换和数字人头像
struct HomeHeaderView: View {
    @EnvironmentObject var appState: AppState
    @State private var showContent = false
    
    var body: some View {
        ZStack {
            // 背景图片 - 平铺整个卡片
            AgentImageView(showContent: showContent)
                .environmentObject(appState)
            
            // 顶部白色渐变虚化层 - 不影响标题
            VStack {
                LinearGradient(
                    colors: [
                        Color.white,
                        Color.white.opacity(0.7),
                        Color.white.opacity(0.4),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                
                Spacer()
            }
            
            // 前景内容
            VStack(spacing: 0) {
                // 标题和设置按钮
                ZStack {
                    // 标题 - 简洁灰白风格 - 居中
                    Text("MolyMemo")
                        .font(.custom("SourceHanSerifSC-Bold", size: 32))
                        .italic()
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black, radius: 0, x: -2, y: -2)
                        .shadow(color: Color.black, radius: 0, x: 2, y: -2)
                        .shadow(color: Color.black, radius: 0, x: -2, y: 2)
                        .shadow(color: Color.black, radius: 0, x: 2, y: 2)
                        .shadow(color: Color.black, radius: 1, x: 0, y: 0)
                        .shadow(color: Color.white.opacity(0.6), radius: 12, x: 0, y: 0)
                        .shadow(color: Color.white.opacity(0.4), radius: 20, x: 0, y: 0)
                        .shadow(color: Color.white.opacity(0.3), radius: 30, x: 0, y: 0)
                    
                    // 设置按钮 - 右对齐
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            HapticFeedback.light()
                            appState.showSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color.white)
                                .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                                .frame(width: 40, height: 36)
                                .background(
                                    ZStack {
                                        // 半透明黑色背景
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.black.opacity(0.5),
                                                        Color.black.opacity(0.4)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        
                                        // 玻璃高光
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.15),
                                                        Color.clear
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black, lineWidth: 2.5)
                                )
                                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 2)
                                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 28)
                
                // 模式切换
                ModeToggleView(selectedMode: $appState.currentMode)
                
                Spacer()
            }
            .opacity(showContent ? 1 : 0)
            
            // 底部白色渐变虚化层 - 融入背景
            VStack {
                Spacer()
                
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.3),
                        Color.white.opacity(0.6),
                        Color.white.opacity(0.85),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
        }
        .frame(height: 600)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0
            )
            .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0
            )
        )
        .ignoresSafeArea(edges: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.4)) {
                showContent = true
            }
        }
    }
}

// MARK: - AgentGirl图片视图
struct AgentImageView: View {
    @EnvironmentObject var appState: AppState
    let showContent: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片 - 填充整个区域
                Image("Agent")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(y: 60)
                    .clipped()
                
                // 波纹效果层
                RippleOverlayView()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(showContent ? 1 : 0)
                
                // 顶部遮罩 - 让标题更清晰
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.96, blue: 0.96).opacity(0.6),
                            Color(red: 0.96, green: 0.96, blue: 0.96).opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    
                    Spacer()
                }
                
                // 下方渐变遮罩 - 柔和过渡
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.clear,
                        Color(red: 0.96, green: 0.96, blue: 0.96).opacity(0.2),
                        Color(red: 0.96, green: 0.96, blue: 0.96).opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .opacity(showContent ? 1 : 0)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                appState.planetScale = 0.98
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    appState.planetScale = 1.0
                }
            }
        }
    }
}

// MARK: - 波纹叠加层
struct RippleOverlayView: View {
    @State private var ripples: [SimpleRipple] = []
    
    var body: some View {
        ZStack {
            ForEach(ripples) { ripple in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(ripple.opacity * 0.4),
                                Color.black.opacity(ripple.opacity * 0.2),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: ripple.size, height: ripple.size)
                    .position(x: ripple.x, y: ripple.y)
                    .opacity(ripple.opacity)
            }
        }
        .onAppear {
            startRipples()
        }
    }
    
    private func startRipples() {
        // 初始创建3个波纹
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.7) {
                createRipple()
            }
        }
    }
    
    private func createRipple() {
        // 随机位置创建波纹
        let ripple = SimpleRipple(
            x: CGFloat.random(in: 100...300),
            y: CGFloat.random(in: 120...360)
        )
        ripples.append(ripple)
        
        // 动画扩散
        withAnimation(.easeOut(duration: 2.0)) {
            if let index = ripples.firstIndex(where: { $0.id == ripple.id }) {
                ripples[index].size = CGFloat.random(in: 180...250)
                ripples[index].opacity = 0
            }
        }
        
        // 清理并创建新波纹
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            ripples.removeAll { $0.id == ripple.id }
            createRipple()
        }
    }
}

// MARK: - 简单波纹状态
struct SimpleRipple: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat = 60
    var opacity: Double = 0.6
}

#Preview {
    HomeHeaderView()
        .environmentObject(AppState())
}

