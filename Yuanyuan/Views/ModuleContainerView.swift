import SwiftUI

// 模块类型枚举
enum ModuleType: String, CaseIterable {
    case todo = "日程"
    case expense = "报销发票"
    case contact = "联系人"
    case meeting = "会议纪要"
    
    var icon: String {
        switch self {
        case .todo: return "calendar"
        case .expense: return "dollarsign.circle.fill"
        case .contact: return "person.2.fill"
        case .meeting: return "mic.circle.fill"
        }
    }
}

// 模块容器视图 - 包含底部导航栏和内容区域
struct ModuleContainerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedModule: ModuleType = .todo
    @State private var showAddSheet = false
    @Namespace private var tabNamespace
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
    // 深色版本（用于选中态）
    private let accentColor = Color(white: 0.35)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 渐变背景
                ModuleBackgroundView(themeColor: themeColor)
                
                // 内容区域
                Group {
                    switch selectedModule {
                    case .todo:
                        TodoListView(showAddSheet: $showAddSheet)
                    case .contact:
                        ContactListView(showAddSheet: $showAddSheet)
                    case .expense:
                        ExpenseListView(showAddSheet: $showAddSheet)
                    case .meeting:
                        MeetingRecordView(showAddSheet: $showAddSheet)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 底部悬浮导航栏
                liquidGlassTabBar()
            }
        }
    }
    
    // MARK: - Liquid Glass 底部导航栏
    private func liquidGlassTabBar() -> some View {
        HStack(spacing: 0) {
            ForEach(ModuleType.allCases, id: \.self) { module in
                tabItem(for: module)
            }
            
            // 添加按钮
            addButton()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(liquidGlassBarBackground())
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
    
    // 添加按钮
    private func addButton() -> some View {
        Button(action: {
            HapticFeedback.light()
            showAddSheet = true
        }) {
            ZStack {
                // 背景圆形 - 主题色
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: themeColor.opacity(0.9), location: 0.0),
                                .init(color: themeColor.opacity(0.7), location: 1.0)
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
                                        .init(color: Color.white.opacity(0.6), location: 0.0),
                                        .init(color: Color.white.opacity(0.2), location: 0.5),
                                        .init(color: Color.white.opacity(0.4), location: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: themeColor.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(TabItemButtonStyle())
        .padding(.horizontal, 4)
    }
    
    // 单个标签项
    private func tabItem(for module: ModuleType) -> some View {
        let isSelected = selectedModule == module
        
        return Button(action: {
            HapticFeedback.light()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedModule = module
            }
        }) {
            VStack(spacing: 3) {
                Image(systemName: module.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                
                Text(module.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(isSelected ? accentColor : .black.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Group {
                    if isSelected {
                        liquidDropletBackground()
                            .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                    }
                }
            )
        }
        .buttonStyle(TabItemButtonStyle())
    }
    
    // MARK: - Liquid Glass 水滴选中效果
    private func liquidDropletBackground() -> some View {
        ZStack {
            // 1. 水滴形状 - 主题色染色的玻璃
            Capsule()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: themeColor.opacity(0.25), location: 0.0),
                            .init(color: themeColor.opacity(0.12), location: 0.5),
                            .init(color: themeColor.opacity(0.06), location: 1.0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
            
            // 2. 内部高光 - 水滴折射效果
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.5), location: 0.0),
                            .init(color: Color.white.opacity(0.15), location: 0.3),
                            .init(color: Color.clear, location: 0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(0.92)
                .offset(y: -2)
            
            // 3. 底部阴影 - 水滴立体感
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.clear, location: 0.5),
                            .init(color: accentColor.opacity(0.08), location: 0.8),
                            .init(color: accentColor.opacity(0.15), location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // 4. 边缘高光 - 水滴表面张力
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.7), location: 0.0),
                            .init(color: Color.white.opacity(0.2), location: 0.3),
                            .init(color: themeColor.opacity(0.2), location: 0.7),
                            .init(color: Color.white.opacity(0.4), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    // MARK: - Liquid Glass 导航栏背景
    private func liquidGlassBarBackground() -> some View {
        ZStack {
            // 1. 超薄毛玻璃材质
            Capsule()
                .fill(.ultraThinMaterial)
            
            // 2. 主题色微染
            Capsule()
                .fill(themeColor.opacity(0.08))
            
            // 3. 内部柔和渐变 - 玻璃深度感
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.5), location: 0.0),
                            .init(color: Color.white.opacity(0.2), location: 0.3),
                            .init(color: Color.white.opacity(0.1), location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // 4. 顶部高光线 - 玻璃边缘
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.8), location: 0.0),
                            .init(color: Color.white.opacity(0.3), location: 0.5),
                            .init(color: Color.white.opacity(0.5), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

// 标签按钮样式
private struct TabItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

