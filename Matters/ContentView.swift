import SwiftUI
import PhotosUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showTechPlanet = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 白色背景
                Color.white
                    .ignoresSafeArea()

                // 主界面
                if showTechPlanet {
                    MainView()
                }
            }
            .statusBar(hidden: false)
            .navigationDestination(isPresented: $appState.showChatRoom) {
                ChatRoomPage(initialMode: appState.currentMode)
            }
            .navigationDestination(isPresented: $appState.showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $appState.showTodoList) {
                TodoListView()
            }
            .navigationDestination(isPresented: $appState.showContactList) {
                ContactListView()
            }
            .navigationDestination(isPresented: $appState.showExpenseList) {
                ExpenseListView()
            }
            .navigationDestination(isPresented: $appState.showMeetingList) {
                MeetingRecordView()
            }
            .fullScreenCover(isPresented: $appState.showLiveRecording) {
                LiveRecordingView()
            }
            .onAppear {
                showTechPlanet = true
            }
        }
    }
}

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                // 顶部卡片
                HomeHeaderView()
                    .environmentObject(appState)
                
                Spacer()
                
                // 底部融合面板
                FusedBottomPanel()
                    .environmentObject(appState)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
            }
            .padding(.top, 8)
            .onAppear {
                // 返回首页时收起目录
                if appState.isMenuExpanded {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        appState.isMenuExpanded = false
                    }
                }
            }
        }
    }
}

// ===== 融合底部面板（打招呼+按钮） =====

struct FusedBottomPanel: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @State private var showButtons = false

    var body: some View {
        VStack(spacing: 0) {
            // 按钮组
            if showButtons {
                // 一级按钮行 - 始终显示
                HStack(spacing: 8) {
                    ForEach(BottomButtonType.allCases, id: \.self) { buttonType in
                        Button(action: {
                            handleButtonTap(buttonType)
                        }) {
                            let isMenuExpanded = buttonType == .menu && appState.isMenuExpanded
                            
                            HStack(spacing: 8) {
                                Image(systemName: buttonType.icon)
                                    .font(.system(size: 16, weight: .bold))
                                
                                Text(buttonType.title)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(Color.white)
                            .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                            .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                            .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                            .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(
                                ZStack {
                                    // 玻璃质感背景
                                    if isMenuExpanded {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.7),
                                                        Color(red: 0.78, green: 0.98, blue: 0.2).opacity(0.6)
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
                                                        Color.white.opacity(0.3),
                                                        Color.clear
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    } else {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.95),
                                                        Color.white.opacity(0.8)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                }
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.black, lineWidth: isMenuExpanded ? 3 : 1.5)
                            )
                            .shadow(
                                color: isMenuExpanded ? Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.6) : Color.black.opacity(0.1),
                                radius: isMenuExpanded ? 16 : 8,
                                x: 0,
                                y: isMenuExpanded ? 4 : 3
                            )
                            .shadow(
                                color: isMenuExpanded ? Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.4) : Color.clear,
                                radius: isMenuExpanded ? 24 : 0,
                                x: 0,
                                y: 0
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.white)
        )
        .overlay(alignment: .bottomTrailing) {
            // 浮动菜单 - 在目录按钮上方弹出
            if showButtons && appState.isMenuExpanded {
                // 菜单内容
                VStack(spacing: 6) {
                    ForEach(MenuButtonType.allCases, id: \.self) { menuType in
                        Button(action: {
                            handleMenuButtonTap(menuType)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: menuType.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.black.opacity(0.7))
                                    .frame(width: 20)

                                Text(menuType.title)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.black.opacity(0.85))
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                )
                .padding(.trailing, 0)
                .padding(.bottom, 75)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity)
                    )
                )
            }
        }
        .onAppear {
            // 首次出现需要等星球入场，返回时立即显示
            let delay = appState.isFirstAppearance ? 1.1 : 0.15

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    showButtons = true
                }
            }

            // 标记已经首次显示过
            if appState.isFirstAppearance {
                appState.isFirstAppearance = false
            }
        }
        .onDisappear {
            // 重置状态，下次返回时可以重新播放动画
            showButtons = false
        }
    }
    
    private func handleButtonTap(_ buttonType: BottomButtonType) {
        // 根据按钮类型提供不同触感
        switch buttonType {
        case .text:
            HapticFeedback.light()

            // 跳转到聊天室（打招呼逻辑已在聊天室内部处理）
            appState.showChatRoom = true
        case .menu:
            HapticFeedback.light()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                appState.isMenuExpanded.toggle()
            }
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            appState.selectedBottomButton = buttonType
        }
    }

    private func handleMenuButtonTap(_ menuType: MenuButtonType) {
        HapticFeedback.light()

        // 先收起目录
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            appState.isMenuExpanded = false
        }

        // 延迟跳转，让收起动画完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch menuType {
            case .todos:
                appState.showTodoList = true
            case .contacts:
                appState.showContactList = true
            case .reimbursement:
                appState.showExpenseList = true
            case .meeting:
                appState.showMeetingList = true
            }
        }
    }
}

// ===== 按钮样式 =====

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
