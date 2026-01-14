import SwiftUI

// 模块类型枚举
enum ModuleType: String, CaseIterable {
    case todo = "日程"
    case contact = "联系人"
    case meeting = "会议记录"
    
    var icon: String {
        switch self {
        // 工具箱底栏图标统一采用“线框/非填充”风格，和「日程」一致
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
    
    // 主题色 - 统一灰色
    private let themeColor = Color(white: 0.55)
    
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
        .safeAreaInset(edge: .bottom) {
            modernTabBar()
        }
        .ignoresSafeArea(.keyboard)
    }
    
    // MARK: - 现代铺满底部导航栏
    private func modernTabBar() -> some View {
        HStack(spacing: 0) {
            ForEach(ModuleType.allCases, id: \.self) { module in
                tabItem(for: module)
            }
        }
        .padding(.horizontal, 0)
        // 让整体 Tab 栏背景也铺满底部安全区域
        .background(.ultraThinMaterial)
    }
    
    // 单个标签项
    private func tabItem(for module: ModuleType) -> some View {
        let isSelected = selectedModule == module
        
        return Button(action: {
            HapticFeedback.light()
            selectedModule = module
        }) {
            VStack(spacing: 4) {
                Image(systemName: module.icon)
                    .font(.system(size: 26))
                    .symbolVariant(isSelected ? .fill : .none)
                
                Text(module.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .black : .black.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            // 底部 padding 调成 0
            .padding(.bottom, 0) 
            .background {
                ZStack {
                    if isSelected {
                        Rectangle()
                            .fill(Color.white.opacity(0.92))
                            // 顶部一点点高光，让“提亮”更干净
                            .overlay(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
                // 让选中背景向下延伸，填充系统的安全区域空隙
                .padding(.bottom, -50)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 移除旧版 Liquid Glass 组件以简化架构

