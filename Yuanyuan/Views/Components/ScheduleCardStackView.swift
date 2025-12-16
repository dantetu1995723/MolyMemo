import SwiftUI
import Combine

extension NSNotification.Name {
    static let dismissScheduleMenu = NSNotification.Name("DismissScheduleMenu")
    static let scheduleMenuDidOpen = NSNotification.Name("ScheduleMenuDidOpen")
}

// MARK: - PreferenceKey for menu state
struct ScheduleMenuStateKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - PreferenceKey for menu frame (global)
/// 用于把胶囊菜单（含下拉）在屏幕坐标系中的 frame 传递到父视图
struct ScheduleMenuFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        // 优先保留非零 frame（避免被其它子树的默认值冲掉）
        if next != .zero {
            value = next
        }
    }
}

struct ScheduleCardStackView: View {
    @Binding var events: [ScheduleEvent]
    /// 横向翻页时，用于通知外层 ScrollView 临时禁用上下滚动，避免手势冲突
    @Binding var isParentScrollDisabled: Bool
    
    // New callback property
    var onDeleteRequest: ((ScheduleEvent) -> Void)? = nil
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showMenu: Bool = false
    @State private var isPressed: Bool = false
    
    // Constants
    private let cardHeight: CGFloat = 300 // Match width for square aspect ratio
    private let cardWidth: CGFloat = 300
    private let pageSwipeDistanceThreshold: CGFloat = 70
    private let pageSwipeVelocityThreshold: CGFloat = 800
    
    var body: some View {
        VStack(spacing: 8) {
            // Card Stack
            ZStack {
                
                if events.isEmpty {
                    Text("无日程")
                        .foregroundColor(.gray)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color.white)
                        .cornerRadius(24)
                } else {
                    ForEach(0..<events.count, id: \.self) { index in
                        // Calculate relative index for cyclic view
                        let relativeIndex = getRelativeIndex(index)
                        
                        // Only show relevant cards for performance
                        // Show current, next few, and the one that might be swiping out/in
                        if relativeIndex < 4 || relativeIndex == events.count - 1 {
                            ScheduleCardView(event: $events[index])
                                .frame(width: cardWidth, height: cardHeight)
                                .scaleEffect(getScale(relativeIndex))
                                .rotationEffect(.degrees(getRotation(relativeIndex)))
                                .offset(x: getOffsetX(relativeIndex), y: 0) // Only horizontal offset for stack look
                                .zIndex(getZIndex(relativeIndex))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                                // 只在「横向意图」时才会开始识别，从根上避免竖滑被卡片 DragGesture 抢走
                                .overlay(
                                    index == currentIndex
                                    ? HorizontalPanGestureInstaller(
                                        directionRatio: 1.15,
                                        onChanged: { dx in
                                            isParentScrollDisabled = true
                                            dragOffset = CGSize(width: dx, height: 0)
                                            if showMenu { withAnimation { showMenu = false } }
                                        },
                                        onEnded: { dx, vx in
                                            defer {
                                                isParentScrollDisabled = false
                                                withAnimation(.spring()) {
                                                    dragOffset = .zero
                                                }
                                            }
                                            guard !events.isEmpty else { return }
                                            withAnimation(.spring()) {
                                                // 翻页方向与底部圆点方向保持一致：向右 = 下一个点；向左 = 上一个点
                                                if dx > pageSwipeDistanceThreshold || vx > pageSwipeVelocityThreshold {
                                                    currentIndex = (currentIndex + 1) % events.count
                                                } else if dx < -pageSwipeDistanceThreshold || vx < -pageSwipeVelocityThreshold {
                                                    currentIndex = (currentIndex - 1 + events.count) % events.count
                                                }
                                            }
                                        }
                                    )
                                    : nil
                                )
                                .longPressCapsuleMenu(
                                    isCurrentIndex: index == currentIndex,
                                    showMenu: $showMenu,
                                    isPressed: $isPressed,
                                    onEdit: {
                                        // TODO: 编辑逻辑
                                        withAnimation { showMenu = false }
                                    },
                                    onRescan: {
                                        // TODO: 重新识别逻辑
                                        withAnimation { showMenu = false }
                                    },
                                    onDelete: {
                                        withAnimation {
                                            showMenu = false
                                            if events.indices.contains(index) {
                                                if let onDeleteRequest = onDeleteRequest {
                                                    onDeleteRequest(events[index])
                                                } else {
                                                    events.remove(at: index)
                                                    if events.isEmpty {
                                                        currentIndex = 0
                                                    } else {
                                                        currentIndex = currentIndex % events.count
                                                    }
                                                }
                                            }
                                        }
                                    }
                                )
                                .allowsHitTesting(index == currentIndex)
                        }
                    }
                }
            }
            .frame(height: cardHeight + 20) // Give some space for rotation/offset
            .padding(.horizontal)
            
            // Pagination Dots
            if events.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<events.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 4)
            }
        }
        // 将菜单状态传递到父视图，用于在 HomeChatView 中添加全屏背景层
        .preference(key: ScheduleMenuStateKey.self, value: showMenu)
        .onReceive(NotificationCenter.default.publisher(for: .dismissScheduleMenu)) { _ in
            withAnimation {
                showMenu = false
                isPressed = false
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getRelativeIndex(_ index: Int) -> Int {
        return (index - currentIndex + events.count) % events.count
    }
    
    private func getScale(_ relativeIndex: Int) -> CGFloat {
        if relativeIndex == 0 {
            return 1.0
        } else {
            // Cards behind get smaller
            return 1.0 - (CGFloat(relativeIndex) * 0.05)
        }
    }
    
    private func getRotation(_ relativeIndex: Int) -> Double {
        if relativeIndex == 0 {
            // Rotate with drag
            return Double(dragOffset.width / 20)
        } else {
            // Static rotation for stack effect
            return Double(relativeIndex) * 2
        }
    }
    
    private func getOffsetX(_ relativeIndex: Int) -> CGFloat {
        if relativeIndex == 0 {
            return dragOffset.width
        } else {
            // Stack offset to the right
            return CGFloat(relativeIndex) * 10
        }
    }
    
    private func getZIndex(_ relativeIndex: Int) -> Double {
        if relativeIndex == 0 {
            return 100
        } else {
            return Double(events.count - relativeIndex)
        }
    }
}

struct ScheduleCardView: View {
    @Binding var event: ScheduleEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Row: Dot
            HStack(alignment: .top) {
                // 左上角装饰圆点 (18x18, #EBEBEB, Inner Shadow: Y:4, B:5, #000000 25%)
                Circle()
                    .fill(Color(hex: "EBEBEB"))
                    .frame(width: 18, height: 18)
                    .overlay(
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            ZStack {
                                Rectangle()
                                    .fill(Color.black.opacity(0.25))
                                    .mask(
                                        ZStack {
                                            Rectangle().fill(Color.black)
                                            Circle().frame(width: w, height: h).blendMode(.destinationOut)
                                        }
                                        .compositingGroup()
                                    )
                                    .offset(x: 0, y: 4)
                                    .blur(radius: 2.5) // Figma Blur 5 ~= SwiftUI radius 2.5
                            }
                            .frame(width: w, height: h)
                            .clipShape(Circle())
                        }
                    )
                
                Spacer()
            }
            .padding(.bottom, 8)
            
            // Date Row & Conflict Tag
            HStack(alignment: .center, spacing: 8) {
                Text(event.fullDateString)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "333333"))
                
                Spacer()
                
                // 冲突提示标签 - 右对齐
                if event.hasConflict {
                    Text("有日程冲突")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(hex: "F5A623"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "F5A623"), lineWidth: 1)
                        )
                }
            }
            .padding(.bottom, 14)
            
            // Divider
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color(hex: "EEEEEE"))
                    .frame(height: 1)
                
                // 右端空心小圆圈
                Circle()
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                    .background(Circle().fill(Color.white))
                    .frame(width: 7, height: 7)
            }
            .padding(.bottom, 20)
            
            // Content Row
            HStack(alignment: .top, spacing: 20) {
                // Time
                VStack(alignment: .leading, spacing: 6) {
                    Text(timeString(event.startTime))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "333333"))
                    
                    Text("~")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "999999"))
                        .padding(.leading, 2)
                    
                    Text(timeString(event.endTime))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "666666"))
                }
                .fixedSize()
                
                // Title & Description
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "333333"))
                        .lineLimit(1)
                    
                    Text(event.description)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "666666"))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            // Bottom Hint
            Text("日程将在开始前半小时提醒")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "999999"))
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.black.opacity(0.03), lineWidth: 1)
        )
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Long Press Menu Modifier
struct LongPressCapsuleMenuModifier: ViewModifier {
    let isCurrentIndex: Bool
    @Binding var showMenu: Bool
    @Binding var isPressed: Bool
    var onEdit: () -> Void
    var onRescan: () -> Void
    var onDelete: () -> Void
    var onDismiss: () -> Void
    
    func body(content: Content) -> some View {
        let scale: CGFloat = isCurrentIndex && (isPressed || showMenu) ? 1.05 : 1.0
        // 长按更灵活：缩短触发时间，但仍区分“短按/长按”
        // 0 会等同于短按，且会被全局“点击空白关闭”误伤（抬手瞬间就关掉）
        let longPressDuration: Double = 0.01
        
        return content
            .scaleEffect(scale)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showMenu)
            // 交互逻辑1：按下卡片 -> 立刻显示胶囊菜单，卡片放大1.05倍
            .onLongPressGesture(minimumDuration: longPressDuration, pressing: { pressing in
                if isCurrentIndex {
                    withAnimation { isPressed = pressing }
                }
            }, perform: {
                if isCurrentIndex {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showMenu = true
                    }
                    // 立刻通知父视图：菜单已打开（用于避免“抬手那一下”被当作点击空白立刻关闭）
                    NotificationCenter.default.post(name: .scheduleMenuDidOpen, object: nil)
                }
            })
            // 注意：点击卡片关闭菜单的逻辑现在由卡片上的覆盖层统一处理（在 ScheduleCardStackView 中）
            .overlay(alignment: .topLeading) {
                if showMenu && isCurrentIndex {
                    CapsuleMenuView(
                        onEdit: onEdit,
                        onRescan: onRescan,
                        onDelete: onDelete,
                        onDismiss: {
                            withAnimation {
                                showMenu = false
                                isPressed = false
                            }
                        }
                    )
                    // 把胶囊菜单（含下拉）在全屏坐标下的 frame 传给父视图
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScheduleMenuFrameKey.self, value: geo.frame(in: .global))
                        }
                    )
                    .scaleEffect(scale)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showMenu)
                    .offset(y: -60) // 增加呼吸空间
                    .transition(.opacity)
                    .zIndex(1000) // 确保菜单在最上层，高于背景层
                    .allowsHitTesting(true) // 确保菜单可以接收点击事件
                }
            }
    }
}

extension View {
    func longPressCapsuleMenu(
        isCurrentIndex: Bool,
        showMenu: Binding<Bool>,
        isPressed: Binding<Bool>,
        onEdit: @escaping () -> Void,
        onRescan: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(LongPressCapsuleMenuModifier(
            isCurrentIndex: isCurrentIndex,
            showMenu: showMenu,
            isPressed: isPressed,
            onEdit: onEdit,
            onRescan: onRescan,
            onDelete: onDelete,
            onDismiss: {
                showMenu.wrappedValue = false
                isPressed.wrappedValue = false
            }
        ))
    }
}

struct CapsuleMenuView: View {
    var onEdit: () -> Void
    var onRescan: () -> Void
    var onDelete: () -> Void
    var onDismiss: () -> Void
    
    @State private var showRescanMenu: Bool = false
    @State private var rescanButtonFrame: CGRect = .zero
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 交互逻辑3：当重新识别下拉菜单显示时，点击外部（包括胶囊菜单外部）-> 关闭所有菜单
            // 包括：下拉菜单、胶囊菜单、卡片全选状态
            if showRescanMenu {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        withAnimation {
                            showRescanMenu = false
                            // 同时关闭胶囊菜单和取消卡片全选状态
                            onDismiss()
                        }
                    }
                    .zIndex(100)
            }
            
            HStack(spacing: 0) {
                // 交互逻辑4：点击"编辑"按钮 -> 执行编辑逻辑并关闭胶囊菜单
                Button(action: onEdit) {
                    Text("编辑")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "333333"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .allowsHitTesting(true) // 确保按钮可以接收点击
                
                Divider()
                    .background(Color.black.opacity(0.1))
                    .frame(height: 16)
                
                // 交互逻辑5：点击"重新识别"按钮 -> 展开/收起下拉菜单（不关闭胶囊菜单）
                Button(action: {
                    withAnimation {
                        showRescanMenu.toggle()
                    }
                }) {
                    HStack(spacing: 2) {
                        Text("重新识别")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "333333"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    rescanButtonFrame = geo.frame(in: .local)
                                }
                                .onChange(of: geo.frame(in: .local)) { _, newFrame in
                                    rescanButtonFrame = newFrame
                                }
                        }
                    )
                }
                .allowsHitTesting(true) // 确保按钮可以接收点击
                
                Divider()
                    .background(Color.black.opacity(0.1))
                    .frame(height: 16)
                
                // 交互逻辑6：点击"删除"按钮 -> 执行删除逻辑并关闭胶囊菜单
                Button(action: onDelete) {
                    Text("删除")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "FF3B30"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .allowsHitTesting(true) // 确保按钮可以接收点击
            }
            .modifier(ConditionalCapsuleBackground(showRescanMenu: showRescanMenu))
            .contentShape(Capsule()) // 确保整个胶囊区域都可以接收点击
            .allowsHitTesting(true) // 确保胶囊菜单可以接收点击事件
            .zIndex(1000) // 确保在背景层上方，按钮点击不会被背景层拦截
            
            // 交互逻辑7：选择下拉菜单中的选项 -> 关闭下拉菜单和胶囊菜单，执行相应逻辑
            if showRescanMenu {
                RescanDropdownMenu(
                    onSelectSchedule: {
                        showRescanMenu = false
                        onRescan() // 这会关闭胶囊菜单（在 onRescan 回调中处理）
                    },
                    onSelectContact: {
                        showRescanMenu = false
                        onRescan()
                    },
                    onSelectInvoice: {
                        showRescanMenu = false
                        onRescan()
                    }
                )
                .offset(x: rescanButtonFrame.minX, y: rescanButtonFrame.maxY - 8) // 稍微叠放在胶囊下部
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .allowsHitTesting(true) // 确保下拉菜单可以接收点击
                .zIndex(1000) // 确保在背景层上方
            }
        }
    }
}

struct RescanDropdownMenu: View {
    var onSelectSchedule: () -> Void
    var onSelectContact: () -> Void
    var onSelectInvoice: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题 - 带向下箭头
            HStack {
                Text("重新识别")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "333333"))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "666666"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // 分栏线 - 不占满全宽，有左右边距
            HStack {
                Spacer()
                    .frame(width: 20) // 左边距
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
                Spacer()
                    .frame(width: 20) // 右边距
            }
            
            // 选项 - 下面三个没有分栏线
            Button(action: onSelectSchedule) {
                Text("这是日程")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "333333"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            
            Button(action: onSelectContact) {
                Text("这是人脉")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "333333"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            
            Button(action: onSelectInvoice) {
                Text("这是发票")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "333333"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16)) // 使用系统 Liquid Glass 效果，更大的圆角
        .frame(width: 200) // 更大的宽度
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            // 阻止点击事件传播
        }
    }
}

// MARK: - Conditional Capsule Background Modifier
struct ConditionalCapsuleBackground: ViewModifier {
    let showRescanMenu: Bool
    
    func body(content: Content) -> some View {
        Group {
            if showRescanMenu {
                content
                    .background(
                        Capsule()
                            .fill(Color(hex: "F5F5F5")) // 点击重新识别后显示灰色背景
                    )
            } else {
                content
                    .glassEffect(in: .capsule) // 正常情况下使用与重新识别模块卡片一样的 Liquid glass 透明效果
            }
        }
    }
}
