import SwiftUI
import PhotosUI
import SwiftData
import UIKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.modelContext) private var modelContext
    @State private var showModuleContainer = false
    
    var body: some View {
        Group {
            if authStore.isLoggedIn {
                NavigationStack {
                    // 直接进入对话界面（首次引导在对话中完成）
                    ChatView(showModuleContainer: $showModuleContainer)
                        .environmentObject(appState)
                        .statusBar(hidden: false)
                        .navigationDestination(isPresented: $showModuleContainer) {
                            ModuleContainerView()
                                .environmentObject(appState)
                        }
                }
                .sheet(isPresented: $appState.showSettings) {
                    SettingsView()
                        .presentationDragIndicator(.visible)
                        .presentationDetents([.height(340)])
                }
                .fullScreenCover(isPresented: $appState.showLiveRecording) {
                    LiveRecordingView()
                }
                .onAppear {
                    // 快捷指令/AppIntent：主App前台处理 pending（聊天更新 / 待发送截图）
                    appState.processPendingChatUpdateIfNeeded(modelContext: modelContext)
                    appState.processPendingScreenshotIfNeeded(modelContext: modelContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: .yyChatStorageUpdated)) { note in
                    // ✅ 全局接收（不依赖 ChatView 是否已出现），统一走“pending 兜底+去重”逻辑
                    _ = note
                    appState.processPendingChatUpdateIfNeeded(modelContext: modelContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: .yyPendingScreenshot)) { _ in
                    appState.processPendingScreenshotIfNeeded(modelContext: modelContext)
                }
            } else {
                LoginView()
            }
        }
    }
}

// MARK: - 圆圆首页主视图
struct YuanyuanHomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showModuleContainer: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var waveformTimer: Timer?
    @State private var waveformAnimationPhase: CGFloat = 0
    @State private var cachedInputBeforeRecording: String = ""
    @State private var isPressedDown = false  // 是否按下
    @State private var longPressStartTime: Date?  // 长按开始时间
    @State private var longPressCheckTimer: Timer?  // 长按检测定时器
    @State private var recordingMessageId: UUID?  // 当前录音中的用户消息ID
    
    // 附件相关
    @State private var showAttachmentOptions = false
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var attachmentFiles: [(name: String, data: Data)] = []
    
    @State private var breathingBrightness: CGFloat = 0.0
    @State private var breathingTimer: Timer?
    @State private var breathingTime: Double = 0.0
    @State private var titlePulseTimer: Timer?
    @State private var titlePulseTime: Double = 0.0
    @State private var titlePulseScale: CGFloat = 1.0
    @State private var notificationsExpanded: Bool = false // 通知栏展开状态
    @State private var upcomingTodos: [TodoItem] = [] // 即将到来的待办
    @State private var isUserDismissingChat: Bool = false // 用户是否主动退出聊天
    
    // 统一灰白主题色
    private let themeGray = Color(white: 0.55)
    private let darkGray = Color(white: 0.35)
    
    @State private var isChatMode: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变
                backgroundGradient(geometry: geometry)
                
                // 光球作为背景层
                middleSection(
                    availableSize: geometry.size,
                    screenWidth: geometry.size.width,
                    breathingBrightness: breathingBrightness,
                    isChatMode: isChatMode
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(isChatMode ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isChatMode)
                .allowsHitTesting(false)
                
                VStack(spacing: 0) {
                    // 顶部区域：标题、调色按钮和通知栏
                    VStack(spacing: 8) {
                        topSection()
                        
                        // 通知栏 - 只在主页状态时显示
                        if !isChatMode && !upcomingTodos.isEmpty {
                            todoNotificationsSection()
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .zIndex(2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    // 中间区域：聊天列表（只在聊天模式时显示）
                    if isChatMode {
                        ZStack(alignment: .top) {
                            chatSection()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    dismissChatMode()
                                }
                            
                            // 模糊分界线 - 灰色柔和过渡
                            VStack {
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: themeGray.opacity(0.25), location: 0.0),
                                        .init(color: themeGray.opacity(0.1), location: 0.6),
                                        .init(color: Color.clear, location: 1.0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 20)
                                .blur(radius: 12)
                                
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(1)
                    } else {
                        // 主页状态：中间区域为空，光球占据视觉中心
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .zIndex(1)
                    }
                    
                    // 底部区域：模块按钮和输入框
                    bottomSection()
                        .padding(.top, isChatMode ? 8 : 40)
                        .zIndex(2)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .animation(.easeInOut(duration: 0.25), value: isChatMode)
            }
        }
        .onAppear {
            startAnimations()
            loadUpcomingTodos()
            speechRecognizer.requestAuthorization()
            // 进入首页时默认关闭聊天模式，由用户主动下拉或点输入框再进入
            isChatMode = false
        }
        .onChange(of: isInputFocused) { _, newValue in
            if newValue {
                // 获得焦点时确保进入聊天模式（双重保险）
                if !isChatMode {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isChatMode = true
                    }
                }
                isUserDismissingChat = false
            } else {
                // 失去焦点时，只有在用户主动退出时才退出聊天模式
                if isUserDismissingChat {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isChatMode = false
                    }
                    
                    // 如果为空，则清空
                    if appState.chatMessages.isEmpty {
                        withAnimation {
                            appState.chatMessages.removeAll()
                        }
                    }
                    
                    isUserDismissingChat = false
                }
            }
        }
        .onChange(of: appState.showTodoList) { oldValue, newValue in
            // 当待办列表关闭时重新加载通知栏
            if !newValue {
                loadUpcomingTodos()
            }
        }
        .onDisappear {
            stopAnimations()
            longPressCheckTimer?.invalidate()
            longPressCheckTimer = nil
            stopRecording(shouldSend: false)
        }
    }
    
    // MARK: - 子区域
    
    
    // 通知栏区域 - 显示待办项目
    private func todoNotificationsSection() -> some View {
        ZStack(alignment: .top) {
            // 根据待办数量显示不同层数
            if upcomingTodos.count >= 3 {
                // 第三层（最底层）
                todoNotificationCard(
                    todo: upcomingTodos[2],
                    isExpanded: notificationsExpanded,
                    showContent: notificationsExpanded
                )
                .offset(y: notificationsExpanded ? 148 : 20)
                .opacity(notificationsExpanded ? 1.0 : 0.6)
                .scaleEffect(notificationsExpanded ? 1.0 : 0.96)
                .zIndex(0)
            }
            
            if upcomingTodos.count >= 2 {
                // 第二层（中间层）
                todoNotificationCard(
                    todo: upcomingTodos[1],
                    isExpanded: notificationsExpanded,
                    showContent: notificationsExpanded
                )
                .offset(y: notificationsExpanded ? 74 : 10)
                .opacity(notificationsExpanded ? 1.0 : 0.75)
                .scaleEffect(notificationsExpanded ? 1.0 : 0.98)
                .zIndex(1)
            }
            
            if upcomingTodos.count >= 1 {
                // 第一层（顶层）- 完整显示
                todoNotificationCard(
                    todo: upcomingTodos[0],
                    isExpanded: notificationsExpanded,
                    showContent: true
                )
                .zIndex(2)
            }
        }
        .padding(.horizontal, 16)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                notificationsExpanded.toggle()
            }
        }
    }
    
    // 单个待办通知卡片
    private func todoNotificationCard(todo: TodoItem, isExpanded: Bool, showContent: Bool = true) -> some View {
        HStack(spacing: 12) {
            // 左侧圆形图标（高亮白底）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.98), location: 0.0),
                                .init(color: Color.white.opacity(0.9), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(darkGray)
                    .frame(width: 32, height: 32)
                    .opacity(showContent ? 1 : 0.3)
            }
            .opacity(showContent ? 1 : 0)
            
            // 卡片内容
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：标题和时间
                HStack(spacing: 8) {
                    Text(todo.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.black.opacity(0.85))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(todo.timeRangeText)
                        .font(.system(size: 13))
                        .foregroundColor(.gray.opacity(0.7))
                }
                
                // 第二行：待办内容描述
                if !todo.taskDescription.isEmpty {
                    Text(todo.taskDescription)
                        .font(.system(size: 13))
                        .foregroundColor(.gray.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .opacity(showContent ? 1 : 0)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 64)
        .background(
            ZStack {
                // 展开状态背景：晶体液态玻璃
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.2), location: 0.0),
                                    .init(color: Color.white.opacity(0.05), location: 0.5),
                                    .init(color: Color.white.opacity(0.1), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.3), location: 0.0),
                                    .init(color: Color.white.opacity(0.1), location: 0.2),
                                    .init(color: Color.clear, location: 0.6)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.8), location: 0.0),
                                    .init(color: Color.white.opacity(0.2), location: 0.5),
                                    .init(color: Color.white.opacity(0.5), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
                .opacity(isExpanded ? 1 : 0)
                
                // 缩起状态背景：晶体液态玻璃（带阴影）
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.2), location: 0.0),
                                    .init(color: Color.white.opacity(0.05), location: 0.5),
                                    .init(color: Color.white.opacity(0.1), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.3), location: 0.0),
                                    .init(color: Color.white.opacity(0.1), location: 0.2),
                                    .init(color: Color.clear, location: 0.6)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.8), location: 0.0),
                                    .init(color: Color.white.opacity(0.2), location: 0.5),
                                    .init(color: Color.white.opacity(0.5), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
                .shadow(color: Color.white.opacity(0.8), radius: 12, x: 0, y: -4)
                .shadow(color: Color.white.opacity(0.4), radius: 6, x: 0, y: -2)
                .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
                .opacity(isExpanded ? 0 : 1)
            }
        )
    }
    
    // 顶部区域 - 灰白色调
    private func topSection() -> some View {
        HStack(spacing: 0) {
            // 左侧：品牌标识胶囊
            HStack(spacing: 6) {
                // 呼吸小圆环
                let haloOpacity = 0.25 + Double(breathingBrightness) * 0.9
                Circle()
                    .strokeBorder(Color.white.opacity(haloOpacity), lineWidth: 1.6)
                    .overlay(
                        Circle()
                            .strokeBorder(themeGray.opacity(haloOpacity * 0.7), lineWidth: 0.8)
                    )
                    .frame(width: 16, height: 16)
                
                Text("圆圆")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    // 发光效果 - 跟随光球呼吸动画
                    .shadow(color: Color.white.opacity(0.5 + Double(breathingBrightness) * 0.3), radius: 0, x: 0, y: 0)
                    .shadow(color: Color.white.opacity(0.4 + Double(breathingBrightness) * 0.3), radius: 2, x: 0, y: 0)
                    .shadow(color: Color.white.opacity(0.3 + Double(breathingBrightness) * 0.2), radius: 4, x: 0, y: 0)
                    .shadow(color: Color.white.opacity(0.2 + Double(breathingBrightness) * 0.15), radius: 6, x: 0, y: 0)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: themeGray.opacity(0.95), location: 0.0),
                        .init(color: themeGray.opacity(0.75), location: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            .scaleEffect(titlePulseScale)
            .frame(height: 32)
            
            Spacer()
            
            // 右侧设置按钮 - 灰色胶囊
            Button(action: {
                HapticFeedback.light()
                appState.showSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: themeGray.opacity(0.95), location: 0.0),
                                .init(color: themeGray.opacity(0.75), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .frame(height: 32)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 2)
    }
    
    // 聊天列表区域 - 全展开状态
    private func chatSection() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 顶部留白，给导航栏让位
                    Color.clear.frame(height: 12)
                    
                    // 聊天消息列表
                    ForEach(appState.chatMessages) { message in
                        HomeChatBubble(message: message)
                            .id(message.id)
                    }
                    
                    // 底部填充空间
                    Spacer(minLength: 150)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 0)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onChange(of: appState.chatMessages.count) { _, _ in
                // 有新消息时滚动到底部
                if let lastId = appState.chatMessages.last?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: appState.chatMessages.last?.content) { _, _ in
                // 流式输出或录音实时更新时自动滚动
                if let lastId = appState.chatMessages.last?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .onAppear {
                // 进入聊天模式时，如果有消息则滚动到底部
                if let lastId = appState.chatMessages.last?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // 中间光圈区域 - 灰白色光球
    private func middleSection(availableSize: CGSize, screenWidth: CGFloat, breathingBrightness: CGFloat, isChatMode: Bool = false) -> some View {
        let maxSize = min(availableSize.width, availableSize.height) * 1.05
        let ballColor = themeGray  // 使用灰色
        // 光球半径
        let ballRadius = maxSize * 0.32
        let coronaRadius = maxSize * 0.65
        // 亮度呼吸：从 0.15 到 0.55，最暗时更暗，呼吸感更明显
        let ballBrightness = 0.15 + (breathingBrightness * 0.4)
        // 光球位置：聊天模式时在上半部中间（45%），非聊天模式在中间偏上（42%）
        let ballPositionY = isChatMode ? availableSize.height * 0.45 : availableSize.height * 0.42
        
        return ZStack {
            // 底层：日冕效果 - 灰色光晕
            ZStack {
                // 日冕外层光晕
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: ballColor.opacity(0.15 * ballBrightness), location: 0.0),
                                .init(color: ballColor.opacity(0.1 * ballBrightness), location: 0.3),
                                .init(color: ballColor.opacity(0.05 * ballBrightness), location: 0.6),
                                .init(color: ballColor.opacity(0.02 * ballBrightness), location: 0.85),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: ballRadius * 1.2,
                            endRadius: coronaRadius
                        )
                    )
                    .frame(width: coronaRadius * 2, height: coronaRadius * 2)
                    .blur(radius: maxSize * 0.08)
                
                // 日冕中层光晕
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: ballColor.opacity(0.2 * ballBrightness), location: 0.0),
                                .init(color: ballColor.opacity(0.08 * ballBrightness), location: 0.25),
                                .init(color: ballColor.opacity(0.05 * ballBrightness), location: 0.5),
                                .init(color: ballColor.opacity(0.08 * ballBrightness), location: 0.75),
                                .init(color: ballColor.opacity(0.2 * ballBrightness), location: 1.0)
                            ]),
                            center: .center,
                            angle: .degrees(0)
                        )
                    )
                    .overlay(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: ballColor.opacity(0.15 * ballBrightness), location: 0.4),
                                .init(color: ballColor.opacity(0.05 * ballBrightness), location: 0.7),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: ballRadius * 1.1,
                            endRadius: coronaRadius * 0.9
                        )
                    )
                    .frame(width: coronaRadius * 1.8, height: coronaRadius * 1.8)
                    .blur(radius: maxSize * 0.06)
                
                // 日冕内层光晕
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: ballColor.opacity(0.25 * ballBrightness), location: 0.0),
                                .init(color: ballColor.opacity(0.15 * ballBrightness), location: 0.5),
                                .init(color: ballColor.opacity(0.05 * ballBrightness), location: 0.85),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: ballRadius * 1.05,
                            endRadius: ballRadius * 1.8
                        )
                    )
                    .frame(width: ballRadius * 3.6, height: ballRadius * 3.6)
                    .blur(radius: maxSize * 0.04)
            }
            .zIndex(0)
            
            // 上层：光球 - 灰白色渐变
            ZStack {
                // 灰黑色日冕 - 最外层
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.black.opacity(0.15 * ballBrightness), location: 0.0),
                                .init(color: Color.black.opacity(0.12 * ballBrightness), location: 0.2),
                                .init(color: Color.gray.opacity(0.1 * ballBrightness), location: 0.4),
                                .init(color: Color.gray.opacity(0.06 * ballBrightness), location: 0.6),
                                .init(color: Color.gray.opacity(0.03 * ballBrightness), location: 0.8),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: ballRadius * 1.8,
                            endRadius: ballRadius * 2.5
                        )
                    )
                    .frame(width: ballRadius * 5.0, height: ballRadius * 5.0)
                    .blur(radius: maxSize * 0.08)
                
                // 银白色日冕 - 外日冕
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(min(ballBrightness * 1.2, 1.0)), location: 0.0),
                                .init(color: Color.white.opacity(min(ballBrightness * 1.0, 1.0)), location: 0.15),
                                .init(color: Color.white.opacity(min(ballBrightness * 0.8, 1.0)), location: 0.3),
                                .init(color: Color.white.opacity(min(ballBrightness * 0.6, 1.0)), location: 0.5),
                                .init(color: Color.white.opacity(min(ballBrightness * 0.4, 1.0)), location: 0.7),
                                .init(color: Color.white.opacity(min(ballBrightness * 0.2, 1.0)), location: 0.85),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: ballRadius,
                            endRadius: ballRadius * 1.8
                        )
                    )
                    .frame(width: ballRadius * 3.6, height: ballRadius * 3.6)
                    .blur(radius: maxSize * 0.05)
                
                // 光球主体 - 灰白渐变
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: ballColor.opacity(min(ballBrightness * 1.2, 1.0)), location: 0.0),
                                .init(color: ballColor.opacity(min(0.7 * ballBrightness * 1.2, 1.0)), location: 0.5),
                                .init(color: ballColor.opacity(min(0.4 * ballBrightness * 1.2, 1.0)), location: 0.7),
                                .init(color: Color.white.opacity(min(0.8 * ballBrightness * 1.2, 1.0)), location: 0.9),
                                .init(color: Color.white.opacity(min(ballBrightness * 1.2, 1.0)), location: 1.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: ballRadius
                        )
                    )
                    .frame(width: ballRadius * 2, height: ballRadius * 2)
                
                // 白色实边
                Circle()
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 0)
                    .frame(width: ballRadius * 2, height: ballRadius * 2)
            }
            .zIndex(1)
        }
        .frame(width: availableSize.width, height: availableSize.height)
        .position(x: availableSize.width / 2, y: ballPositionY)
        .animation(.easeInOut(duration: 0.3), value: isChatMode)
    }
    
    // 背景径向渐变 - 灰白色调，从中心向边缘加深
    private func backgroundGradient(geometry: GeometryProxy) -> some View {
        let centerColor = Color(white: 0.75)  // 中心浅灰
        let edgeColor = Color(white: 0.45)    // 边缘深灰
        
        return ZStack {
            // 底层：边缘深灰
            edgeColor
            
            // 径向渐变：中心浅，边缘深
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: centerColor, location: 0.0),
                    .init(color: centerColor.opacity(0.95), location: 0.35),
                    .init(color: edgeColor.opacity(0.6), location: 0.7),
                    .init(color: edgeColor, location: 1.0)
                ]),
                center: .init(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: max(geometry.size.width, geometry.size.height) * 0.75
            )
        }
        .ignoresSafeArea(.all)
    }
    
    // 底部区域：模块按钮 + 输入框
    private func bottomSection() -> some View {
        VStack(spacing: 0) {
            // 输入框容器 - 条形布局
            HStack(spacing: 12) {
                // 统一的输入框/录音按钮容器
                unifiedInputContainer()
                
                // 工具按钮（录音时隐藏）
                if !speechRecognizer.isRecording {
                    Button(action: {
                        HapticFeedback.light()
                        showModuleContainer = true
                    }) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(width: 50, height: 50)
                            .background(glassButtonBackground())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .frame(height: 50)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 3)
            .animation(.spring(response: 0.15, dampingFraction: 0.85), value: speechRecognizer.isRecording)
            // 附件选择
            .confirmationDialog("选择附件类型", isPresented: $showAttachmentOptions, titleVisibility: .visible) {
                Button("图片") {
                    showImagePicker = true
                }
                Button("文件") {
                    showFilePicker = true
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(onImagesSelected: { images in
                    appState.selectedImages = images
                    appState.showChatRoom = true
                })
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(selectedFiles: $attachmentFiles, isPresented: $showFilePicker)
                    .presentationDragIndicator(.visible)
            }
            
            // 增加输入框到底部的距离
            Spacer()
                .frame(height: 20)
        }
    }
    
    // 统一的输入框/录音按钮容器 - 高亮白色样式，与工具按钮一致
    private func unifiedInputContainer() -> some View {
        ZStack {
            // 背景层：高亮白色玻璃效果
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.98), location: 0.0),
                            .init(color: Color.white.opacity(0.95), location: 0.5),
                            .init(color: Color.white.opacity(0.98), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.8), location: 0.0),
                                    .init(color: Color.white.opacity(0.4), location: 0.5),
                                    .init(color: Color.white.opacity(0.6), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                .shadow(color: Color.white.opacity(0.6), radius: 4, x: -1, y: -1)
            
            // 内容层：根据状态切换
            ZStack {
                // 始终渲染输入框（用于手势识别），但录音时隐藏
                ChatTextField(
                    text: $inputText,
                    placeholder: "发送消息或按住说话",
                    shouldFocus: Binding(
                        get: { isInputFocused },
                        set: { newValue in
                            isInputFocused = newValue
                            if newValue && !isChatMode {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isChatMode = true
                                }
                            }
                        }
                    ),
                    onSubmit: {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage()
                        }
                    },
                    onLongPressStart: {
                        // 无论是否有焦点，都可以长按录音
                        cachedInputBeforeRecording = inputText
                        isPressedDown = true
                        longPressStartTime = Date()
                        startRecording()
                    },
                    onLongPressEnd: {
                        handlePressUp()
                    }
                )
                .font(.system(size: 17, weight: .regular))
                .padding(.leading, 56)
                .padding(.trailing, 20)
                .opacity(speechRecognizer.isRecording ? 0 : 1)
                .allowsHitTesting(!speechRecognizer.isRecording)
                
                // 录音状态内容（显示在输入框上方）
                if speechRecognizer.isRecording {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(width: 24)
                        
                        Text("松开发送")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                        
                        Spacer()
                        
                        Text(formatDuration(recordingDuration))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black.opacity(0.6))
                            .monospacedDigit()
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                }
            }
            
            // 附件按钮（悬浮在左侧，录音时显示麦克风图标位置）
            HStack {
                if !speechRecognizer.isRecording {
                    Button(action: {
                        openAttachmentPicker()
                    }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color.gray.opacity(0.75))
                            .frame(width: 32, height: 32)
                    }
                    .padding(.leading, 18)
                }
                Spacer()
            }
            
        }
        .frame(height: 50)
        .animation(.easeInOut(duration: 0.15), value: speechRecognizer.isRecording)
    }
    
    // 开始录音
    private func startRecording() {
        guard !speechRecognizer.isRecording else { return }
        
        HapticFeedback.medium()
        recordingDuration = 0
        waveformAnimationPhase = 0
        inputText = ""
        
        // 立即进入聊天模式
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isChatMode = true
        }
        
        // 创建用户消息气泡（空内容，实时更新）
        let userMsg = ChatMessage(role: .user, content: "")
        recordingMessageId = userMsg.id
        withAnimation {
            appState.chatMessages.append(userMsg)
        }
        
        // 启动录音时长计时器
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard self.speechRecognizer.isRecording else {
                timer.invalidate()
                self.recordingTimer = nil
                return
            }
            self.recordingDuration += 0.1
        }
        
        // 开始录音，实时更新用户消息内容
        speechRecognizer.startRecording { text in
            guard let messageId = self.recordingMessageId else { return }
            
            // 更新用户消息气泡内容
            if let index = self.appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                var updatedMessage = self.appState.chatMessages[index]
                updatedMessage.content = text
                // 更新消息内容（SwiftUI 会自动处理动画）
                self.appState.chatMessages[index] = updatedMessage
            }
        }
    }
    
    // 停止录音
    private func stopRecording(shouldSend: Bool = true) {
        guard speechRecognizer.isRecording else {
            if !shouldSend {
                inputText = cachedInputBeforeRecording
                cachedInputBeforeRecording = ""
            }
            return
        }
        
        // 立即停止录音和计时器（同步执行，UI立即恢复）
        HapticFeedback.light()
        speechRecognizer.stopRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        waveformTimer?.invalidate()
        waveformTimer = nil
        waveformAnimationPhase = 0
        
        // 保存 messageId 和文本用于后续处理
        let currentMessageId = recordingMessageId
        
        // 获取最终录音文本
        let finalText: String
        if let messageId = currentMessageId,
           let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
            finalText = appState.chatMessages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 立即清理UI状态，让界面立即恢复
        recordingMessageId = nil
        inputText = ""
        
        // 消息发送在后台异步处理，不阻塞UI
        if shouldSend, !finalText.isEmpty {
            Task { @MainActor in
                await sendRecordedMessage(messageId: currentMessageId, text: finalText)
            }
        } else {
            // 取消录音，删除空消息
            if let messageId = currentMessageId,
               let index = appState.chatMessages.firstIndex(where: { $0.id == messageId }) {
                appState.chatMessages.remove(at: index)
            }
            inputText = cachedInputBeforeRecording
            cachedInputBeforeRecording = ""
        }
    }
    
    // 后台发送录音消息
    private func sendRecordedMessage(messageId: UUID?, text: String) async {
        
        // 更新用户消息内容并发送
        if let msgId = messageId,
           let index = appState.chatMessages.firstIndex(where: { $0.id == msgId }) {
            var updatedMessage = appState.chatMessages[index]
            updatedMessage.content = text
            appState.chatMessages[index] = updatedMessage
            
            // 保存消息
            appState.saveMessageToStorage(updatedMessage, modelContext: modelContext)
            
            // 创建AI占位消息并发送
            let agentMsg = ChatMessage(role: .agent, content: "")
            appState.chatMessages.append(agentMsg)
            let agentMessageId = agentMsg.id
            
            // 调用AI
            appState.isAgentTyping = true
            appState.startStreaming(messageId: agentMessageId)
            
            await SmartModelRouter.sendMessageStream(
                messages: appState.chatMessages,
                mode: appState.currentMode,
                onStructuredOutput: { output in
                    DispatchQueue.main.async {
                        self.appState.applyStructuredOutput(output, to: agentMessageId)
                    }
                },
                onComplete: { finalText in
                    await self.appState.playResponse(finalText, for: agentMessageId)
                    await MainActor.run {
                        if let completedMessage = self.appState.chatMessages.first(where: { $0.id == agentMessageId }) {
                            self.appState.saveMessageToStorage(completedMessage, modelContext: self.modelContext)
                        }
                    }
                },
                onError: { error in
                    DispatchQueue.main.async {
                        self.appState.handleStreamingError(error, for: agentMessageId)
                        self.appState.isAgentTyping = false
                    }
                }
            )
        } else {
            // 如果找不到消息ID，直接发送
            let userMsg = ChatMessage(role: .user, content: text)
            appState.chatMessages.append(userMsg)
            appState.saveMessageToStorage(userMsg, modelContext: modelContext)
            
            let agentMsg = ChatMessage(role: .agent, content: "")
            appState.chatMessages.append(agentMsg)
            let agentMessageId = agentMsg.id
            
            appState.isAgentTyping = true
            appState.startStreaming(messageId: agentMessageId)
            
            await SmartModelRouter.sendMessageStream(
                messages: appState.chatMessages,
                mode: appState.currentMode,
                onStructuredOutput: { output in
                    DispatchQueue.main.async {
                        self.appState.applyStructuredOutput(output, to: agentMessageId)
                    }
                },
                onComplete: { finalText in
                    await self.appState.playResponse(finalText, for: agentMessageId)
                    await MainActor.run {
                        if let completedMessage = self.appState.chatMessages.first(where: { $0.id == agentMessageId }) {
                            self.appState.saveMessageToStorage(completedMessage, modelContext: self.modelContext)
                        }
                    }
                },
                onError: { error in
                    DispatchQueue.main.async {
                        self.appState.handleStreamingError(error, for: agentMessageId)
                        self.appState.isAgentTyping = false
                    }
                }
            )
        }
    }
    
    // 打开附件选择
    private func openAttachmentPicker() {
        HapticFeedback.light()
        stopRecording(shouldSend: false)
        showAttachmentOptions = true
    }
    
    
    // 处理按下
    private func handlePressDown() {
        guard !isPressedDown else { return }
        isPressedDown = true
        longPressStartTime = Date()
        
        // 启动长按检测定时器
        longPressCheckTimer?.invalidate()
        longPressCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            // 0.15秒后仍在按住，开始录音（更敏感）
            if self.isPressedDown && !self.speechRecognizer.isRecording {
                self.cachedInputBeforeRecording = self.inputText
                self.startRecording()
            }
        }
    }
    
    // 处理松开
    private func handlePressUp() {
        
        let wasPressedDown = isPressedDown
        isPressedDown = false
        
        // 取消长按检测定时器
        longPressCheckTimer?.invalidate()
        longPressCheckTimer = nil
        
        // 如果正在录音，立即停止并发送
        if speechRecognizer.isRecording {
            stopRecording(shouldSend: true)
        } else if wasPressedDown, let startTime = longPressStartTime {
            // 如果按下时间小于0.15秒，视为点击，激活输入框（更敏感）
            let pressDuration = Date().timeIntervalSince(startTime)
            if pressDuration < 0.15 {
                isInputFocused = true
            }
        }
        
        longPressStartTime = nil
    }
    
    // 波形条高度（根据索引和动画相位）
    private func waveformBarHeight(index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 24
        let phase = waveformAnimationPhase + Double(index) * 0.5
        let height = baseHeight + (sin(phase) + 1) / 2 * (maxHeight - baseHeight)
        return max(baseHeight, min(maxHeight, height))
    }
    
    // 格式化录音时长
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // 液态玻璃圆形背景
    private func liquidGlassCircle() -> some View {
        ZStack {
            // 1. 极淡的填充基底
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.2), location: 0.0),
                            .init(color: Color.white.opacity(0.05), location: 0.5),
                            .init(color: Color.white.opacity(0.1), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 2. 表面光泽
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.3), location: 0.0),
                            .init(color: Color.white.opacity(0.1), location: 0.2),
                            .init(color: Color.clear, location: 0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // 3. 晶体边框
            Circle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.8), location: 0.0),
                            .init(color: Color.white.opacity(0.2), location: 0.5),
                            .init(color: Color.white.opacity(0.5), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
    
    // 液态玻璃胶囊背景 - 复用组件
    private func liquidGlassCapsule() -> some View {
        ZStack {
            // 1. 极淡的填充基底
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.2), location: 0.0),
                            .init(color: Color.white.opacity(0.05), location: 0.5),
                            .init(color: Color.white.opacity(0.1), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 2. 表面光泽
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.3), location: 0.0),
                            .init(color: Color.white.opacity(0.1), location: 0.2),
                            .init(color: Color.clear, location: 0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // 3. 晶体边框
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.8), location: 0.0),
                            .init(color: Color.white.opacity(0.2), location: 0.5),
                            .init(color: Color.white.opacity(0.5), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
    
    // 玻璃按钮背景
    private func glassButtonBackground() -> some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.98), location: 0.0),
                        .init(color: Color.white.opacity(0.95), location: 0.5),
                        .init(color: Color.white.opacity(0.98), location: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.8), location: 0.0),
                                .init(color: Color.white.opacity(0.4), location: 0.5),
                                .init(color: Color.white.opacity(0.6), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .shadow(color: Color.white.opacity(0.6), radius: 4, x: -1, y: -1)
    }
    
    // MARK: - 数据加载
    
    // 加载即将到来的待办（未完成且在未来7天内）
    private func loadUpcomingTodos() {
        let now = Date()
        let sevenDaysLater = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { todo in
                !todo.isCompleted && todo.startTime >= now && todo.startTime <= sevenDaysLater
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        do {
            let todos = try modelContext.fetch(descriptor)
            upcomingTodos = Array(todos.prefix(3)) // 最多显示3个
        } catch {
            upcomingTodos = []
        }
    }
    
    // MARK: - 动画控制
    
    private func startAnimations() {
        // 呼吸动画
        let breathingDuration: TimeInterval = 2.5
        let frameInterval: TimeInterval = 0.016
        
        let breathingTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { _ in
            breathingTime += frameInterval
            breathingBrightness = (sin(breathingTime * 2 * .pi / breathingDuration) + 1.0) / 2.0
            if breathingTime >= breathingDuration * 100 {
                breathingTime = breathingTime.truncatingRemainder(dividingBy: breathingDuration)
            }
        }
        RunLoop.current.add(breathingTimer, forMode: .common)
        self.breathingTimer = breathingTimer
        
        // 标题脉冲动画
        let pulseDuration: TimeInterval = 3.0
        let pulseTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { _ in
            titlePulseTime += frameInterval
            titlePulseScale = 1.0 + (sin(titlePulseTime * 2 * .pi / pulseDuration) + 1.0) / 2.0 * 0.03
            if titlePulseTime >= pulseDuration * 100 {
                titlePulseTime = titlePulseTime.truncatingRemainder(dividingBy: pulseDuration)
            }
        }
        RunLoop.current.add(pulseTimer, forMode: .common)
        self.titlePulseTimer = pulseTimer
    }
    
    private func stopAnimations() {
        breathingTimer?.invalidate()
        breathingTimer = nil
        titlePulseTimer?.invalidate()
        titlePulseTimer = nil
    }
    
    // MARK: - 消息处理
    
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !appState.isAgentTyping else { return }
        
        let messageText = trimmedText
        inputText = ""
        
        // 确保进入聊天模式
        if !isChatMode {
            isChatMode = true
        }
        
        // 添加用户消息并保存
        let userMsg = ChatMessage(role: .user, content: messageText)
        withAnimation {
            appState.chatMessages.append(userMsg)
        }
        appState.saveMessageToStorage(userMsg, modelContext: modelContext)
        
        // 创建AI占位消息
        let agentMsg = ChatMessage(role: .agent, content: "")
            withAnimation {
                appState.chatMessages.append(agentMsg)
            }
        let messageId = agentMsg.id
        
        // 调用后端聊天AI（与聊天室共用的智能路由）
        Task {
            appState.isAgentTyping = true
            appState.startStreaming(messageId: messageId)
            
            await SmartModelRouter.sendMessageStream(
                messages: appState.chatMessages,
                mode: appState.currentMode,
                onStructuredOutput: { output in
                    DispatchQueue.main.async {
                        appState.applyStructuredOutput(output, to: messageId)
                    }
                },
                onComplete: { finalText in
                    await self.appState.playResponse(finalText, for: messageId)
                    await MainActor.run {
                        if let completedMessage = self.appState.chatMessages.first(where: { $0.id == messageId }) {
                            self.appState.saveMessageToStorage(completedMessage, modelContext: self.modelContext)
                        }
                    }
                },
                onError: { error in
                    self.appState.handleStreamingError(error, for: messageId)
                    self.appState.isAgentTyping = false
                }
            )
        }
    }
    
    // 退出聊天模式
    private func dismissChatMode() {
        isUserDismissingChat = true
        
        // 先收起键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isInputFocused = false
        
        // 如果聊天模式已开启，直接退出
        if isChatMode {
            withAnimation {
                isChatMode = false
            }
            
            // 如果为空，则清空，恢复初始状态
            if appState.chatMessages.isEmpty {
                withAnimation {
                    appState.chatMessages.removeAll()
                }
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
    
// MARK: - 首页简化聊天气泡

private struct HomeChatBubble: View {
    let message: ChatMessage
    @EnvironmentObject var appState: AppState
    @State private var dotCount = 0
    @State private var dotTimer: Timer?
    
    private var isUser: Bool {
        message.role == .user
    }
    
    // 用户消息字体颜色（白色气泡上的深灰色）
    private let userTextColor = Color(hex: "3A3A3A")
    
    // 判断是否显示等待文字
    private var shouldShowWaitingText: Bool {
        !isUser && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appState.isAgentTyping
    }
    
    // 等待文字内容（带动画点）
    private var waitingText: String {
        "正在思考" + String(repeating: ".", count: dotCount)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer()
                
                // 用户消息：高亮白色透明背景气泡
                Text(message.content)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(userTextColor)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(8)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.white.opacity(0.85))
                    )
                    .frame(maxWidth: ScreenMetrics.width * 0.75, alignment: .trailing)
                
                Spacer(minLength: 20)
            } else {
                // AI消息：白色发光文字 - 柔和光晕效果
                Text(shouldShowWaitingText ? waitingText : message.content)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(8)
                    // 内层白色光晕
                    .shadow(color: Color.white.opacity(0.7), radius: 0, x: 0, y: 0)
                    .shadow(color: Color.white.opacity(0.6), radius: 2, x: 0, y: 0)
                    .shadow(color: Color.white.opacity(0.45), radius: 4, x: 0, y: 0)
                    // 外层柔和光晕
                    .shadow(color: Color.white.opacity(0.3), radius: 6, x: 0, y: 0)
                    // 深色阴影确保可读性
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .frame(maxWidth: ScreenMetrics.width * 0.85, alignment: .leading)
                    .onChange(of: shouldShowWaitingText) { _, isWaiting in
                        if isWaiting {
                            startDotAnimation()
                        } else {
                            stopDotAnimation()
                        }
                    }
                    .onAppear {
                        if shouldShowWaitingText {
                            startDotAnimation()
                        }
                    }
                    .onDisappear {
                        stopDotAnimation()
                    }
                
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
    }
    
    private func startDotAnimation() {
        stopDotAnimation()
        dotCount = 1
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                dotCount = (dotCount % 3) + 1
            }
        }
        RunLoop.current.add(dotTimer!, forMode: .common)
    }
    
    private func stopDotAnimation() {
        dotTimer?.invalidate()
        dotTimer = nil
        dotCount = 0
    }
}

// MARK: - 自定义输入框（回车发送后键盘不收起，支持长按录音）
struct ChatTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var shouldFocus: Bool
    var onSubmit: () -> Void
    var onLongPressStart: (() -> Void)?
    var onLongPressEnd: (() -> Void)?
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.delegate = context.coordinator
        textField.returnKeyType = .send
        textField.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        textField.textColor = UIColor.black.withAlphaComponent(0.85)
        textField.backgroundColor = .clear
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        context.coordinator.textField = textField
        
        // 添加长按手势（只在未获得焦点时触发录音）
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.05  // 尽量贴近按下即录音
        textField.addGestureRecognizer(longPress)
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // 同步文本
        if uiView.text != text {
            uiView.text = text
        }
        
        // 只处理显式请求获得焦点的情况
        // 不在这里处理 resignFirstResponder，避免竞态条件
        // 收起键盘通过 UIApplication.sendAction 全局处理
        if shouldFocus && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ChatTextField
        weak var textField: UITextField?
        private var didStartLongPressForCurrentGesture: Bool = false
        private var ignoreLongPressUntil: Date = Date()
        private var didBecomeActiveObserver: NSObjectProtocol?
        
        init(_ parent: ChatTextField) {
            self.parent = parent
            super.init()
            
            // 关键修复：
            // 灵动岛/通知唤回 App 的瞬间，用户的“同一次按压”可能被 UIKit 投递到新出现的 UITextField 上，
            // 导致 UILongPressGestureRecognizer 立即进入 .began，从而误触发语音转文字。
            // 这里在 App 刚回到前台的短窗口内抑制 long press，只影响误触发，不影响正常长按灵敏度。
            ignoreLongPressUntil = Date().addingTimeInterval(0.35)
            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.ignoreLongPressUntil = Date().addingTimeInterval(0.35)
            }
        }
        
        deinit {
            if let token = didBecomeActiveObserver {
                NotificationCenter.default.removeObserver(token)
            }
        }
        
        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                // 前台恢复/视图重建后的误触发抑制
                guard Date() >= ignoreLongPressUntil else {
                    didStartLongPressForCurrentGesture = false
                    return
                }
                didStartLongPressForCurrentGesture = true
                // 长按时触发触觉反馈
                HapticFeedback.medium()
                // 长按时直接触发录音，保持键盘弹起状态（不调用resignFirstResponder）
                parent.onLongPressStart?()
            } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                // 长按结束、取消或失败，都触发松开事件
                // 只有真正触发过开始事件，才允许结束事件继续向上传递，避免“没开始却 stop”的竞态。
                guard didStartLongPressForCurrentGesture else { return }
                didStartLongPressForCurrentGesture = false
                // 使用主线程确保立即执行
                DispatchQueue.main.async {
                    self.parent.onLongPressEnd?()
                }
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            // 立即同步更新焦点状态，触发进入聊天模式
            DispatchQueue.main.async {
                self.parent.shouldFocus = true
            }
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            // 使用 async 确保 SwiftUI 能正确处理 @FocusState 更新
            DispatchQueue.main.async {
                if self.parent.shouldFocus {
                    self.parent.shouldFocus = false
                }
            }
        }
    }
}

// MARK: - Color Hex 扩展
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
