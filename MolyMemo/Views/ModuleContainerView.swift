import SwiftUI

// 模块类型枚举
enum ModuleType: String, CaseIterable {
    case todo = "日程"
    case contact = "联系人"
    case meeting = "会议纪要"
    
    var icon: String {
        switch self {
        // 工具箱底栏图标统一采用"线框/非填充"风格，和「日程」一致
        case .todo: return "calendar"
        case .contact: return "person.2"
        case .meeting: return "mic"
        }
    }
}

// 模块容器视图 - 包含底部导航栏和内容区域
struct ModuleContainerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedModule: ModuleType = .todo
    @State private var showAddSheet = false
    @Namespace private var tabNamespace
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    // 深色版本（用于选中态文字）
    private let accentColor = Color(white: 0.20)
    
    var body: some View {
        // 内容区域
        Group {
            switch selectedModule {
            case .todo:
                // 保留原有日历日程界面
                TodoListView(showAddSheet: $showAddSheet)
            case .contact:
                // 联系人模块
                ContactListView()
            case .meeting:
                MeetingRecordView(showAddSheet: $showAddSheet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ModuleBackgroundView(themeColor: themeColor))
        // 使用 safeAreaInset 让内容在 Tab Bar 上方停止，同时底部有透明挡板
        .safeAreaInset(edge: .bottom) {
            tabBarWithBackdrop()
        }
        .ignoresSafeArea(.keyboard)
    }
    
    // MARK: - 带透明挡板背景的 Tab Bar
    private func tabBarWithBackdrop() -> some View {
        VStack(spacing: 0) {
            // 胶囊形态的 Tab Bar
            liquidGlassTabBar()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        // 透明挡板背景：延伸到屏幕底部安全区域（使用浅色半透明白底）
        .background(Color.white.opacity(0.1))
    }
    
    // MARK: - Liquid Glass 胶囊 Tab Bar
    private func liquidGlassTabBar() -> some View {
        HStack(spacing: 4) {
            ForEach(ModuleType.allCases, id: \.self) { module in
                tabItem(for: module)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // 胶囊本身的玻璃效果
        .modifier(GlassBarBackgroundModifier())
    }
    
    // 单个标签项
    private func tabItem(for module: ModuleType) -> some View {
        let isSelected = selectedModule == module
        
        return Button(action: {
            HapticFeedback.light()
            // 更加灵动的弹性动画
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)) {
                selectedModule = module
            }
        }) {
            VStack(spacing: 3) {
                Image(systemName: module.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                
                Text(module.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? accentColor : .black.opacity(0.42))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    // Pill 选中态滑块
                    liquidPillIndicator()
                        .matchedGeometryEffect(id: "selectedTabPill", in: tabNamespace)
                }
            }
        }
        .buttonStyle(TabItemButtonStyle())
    }
    
    // MARK: - Pill 选中指示器
    private func liquidPillIndicator() -> some View {
        ZStack {
            // 基础白色高亮层
            Capsule()
                .fill(Color.white.opacity(0.85))
            
            // 细腻的玻璃质感描边
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            
            // 极弱的内阴影
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.03), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

// MARK: - 玻璃胶囊背景修饰器
private struct GlassBarBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                )
        } else {
            content
                .background(
                    ZStack {
                        // 更干净的白色毛玻璃
                        Capsule()
                            .fill(.ultraThinMaterial)
                        
                        // 微弱的白色叠加，增强通透感
                        Capsule()
                            .fill(Color.white.opacity(0.4))
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                )
        }
    }
}

// 标签按钮样式
private struct TabItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
