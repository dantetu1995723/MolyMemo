import SwiftUI

/// 轻量的“浮层单选菜单”，样式与 `ScheduleDetailSheet` 的“提醒时间”一致（glassEffect + 勾选）。
struct SingleSelectOptionMenu: View {
    struct Option: Identifiable, Hashable {
        let title: String
        let value: String
        
        /// 用 value 作为稳定 id，保证 ScrollViewReader 能准确 scrollTo
        var id: String { value }
    }
    
    let title: String
    let options: [Option]
    let selectedValue: String?
    let onSelect: (String) -> Void
    
    static let rowHeight: CGFloat = 44
    static let maxVisibleRows: CGFloat = 3.5
    
    static func maxHeight(optionCount: Int) -> CGFloat {
        Self.rowHeight * min(CGFloat(optionCount), Self.maxVisibleRows)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(options) { opt in
                            Button(action: {
                                HapticFeedback.selection()
                                onSelect(opt.value)
                            }) {
                                HStack(spacing: 10) {
                                    Text(opt.title)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(Color(hex: "333333"))
                                    
                                    Spacer(minLength: 0)
                                    
                                    if isSelected(opt.value) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color(hex: "333333"))
                                    }
                                }
                                .padding(.horizontal, 14)
                        .frame(height: Self.rowHeight)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(opt.id)
                            
                            if opt.id != options.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
                // 打开时让滚动位置对齐到“已勾选项”附近
                .onAppear {
                    let sel = (selectedValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !sel.isEmpty else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(sel, anchor: .center)
                    }
                }
            }
            // 约 3.5 行高度：露半行提示“可滚动”
            .frame(maxHeight: Self.maxHeight(optionCount: options.count))
        }
        .yy_glassEffectCompat(cornerRadius: 24)
    }
    
    private func isSelected(_ v: String) -> Bool {
        let a = (selectedValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let b = v.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else { return false }
        return a == b
    }
}

/// 用于采集某个 row 的 global frame（给浮层菜单计算定位用）
struct GlobalFrameReporter: ViewModifier {
    @Binding var frame: CGRect
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newValue in
                        frame = newValue
                    }
            }
        )
    }
}

enum PopupMenuPositioning {
    static func menuOffset(for globalFrame: CGRect, in rootFrame: CGRect, menuWidth: CGFloat, extraTop: CGFloat) -> CGSize {
        let x = max(16, min(globalFrame.maxX - rootFrame.minX - menuWidth, (rootFrame.width - menuWidth - 16)))
        let y = (globalFrame.maxY - rootFrame.minY) + extraTop
        return CGSize(width: x, height: y)
    }

    /// 右侧对齐到 anchor 的 maxX，并在垂直方向让浮层与 anchor 的 midY 居中对齐（常用于“导航栏胶囊按钮”）
    static func rightAlignedCenterOffset(for globalFrame: CGRect, in rootFrame: CGRect, width: CGFloat, height: CGFloat) -> CGSize {
        let x = max(16, min(globalFrame.maxX - rootFrame.minX - width, (rootFrame.width - width - 16)))
        let y = (globalFrame.midY - rootFrame.minY) - (height * 0.5)
        return CGSize(width: x, height: y)
    }
    
    /// 让菜单从触发行的顶部开始覆盖（遮住触发行内容，而不是出现在下方）
    static func coveringRowOffset(for globalFrame: CGRect, in rootFrame: CGRect, menuWidth: CGFloat, menuHeight: CGFloat, topPadding: CGFloat = 12, bottomPadding: CGFloat = 16) -> CGSize {
        let x = max(16, min(globalFrame.maxX - rootFrame.minX - menuWidth, (rootFrame.width - menuWidth - 16)))
        var y = (globalFrame.minY - rootFrame.minY) - 4
        y = max(topPadding, y)
        y = min(y, rootFrame.height - menuHeight - bottomPadding)
        return CGSize(width: x, height: y)
    }
    
    /// 让菜单“底边”对齐到触发行的底边（菜单向上展开），用于日历这类需要“盖住触发内容”的浮层。
    static func coveringRowFromBottomOffset(for globalFrame: CGRect, in rootFrame: CGRect, menuWidth: CGFloat, menuHeight: CGFloat, topPadding: CGFloat = 12, bottomPadding: CGFloat = 16) -> CGSize {
        let x = max(16, min(globalFrame.maxX - rootFrame.minX - menuWidth, (rootFrame.width - menuWidth - 16)))
        var y = (globalFrame.maxY - rootFrame.minY) - menuHeight
        y = max(topPadding, y)
        y = min(y, rootFrame.height - menuHeight - bottomPadding)
        return CGSize(width: x, height: y)
    }
}


