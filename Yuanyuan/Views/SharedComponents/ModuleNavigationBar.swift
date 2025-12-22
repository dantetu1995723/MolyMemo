import SwiftUI

/// 统一的模块顶部导航，尽量克制的玻璃质感
struct ModuleNavigationBar: View {
    let title: String
    let themeColor: Color
    let onBack: () -> Void
    var trailingIcon: String?
    var trailingAction: (() -> Void)?
    var customTrailing: AnyView?
    
    private let buttonSize: CGFloat = 34
    
    init(
        title: String,
        themeColor: Color,
        onBack: @escaping () -> Void,
        trailingIcon: String? = nil,
        trailingAction: (() -> Void)? = nil,
        customTrailing: AnyView? = nil
    ) {
        self.title = title
        self.themeColor = themeColor
        self.onBack = onBack
        self.trailingIcon = trailingIcon
        self.trailingAction = trailingAction
        self.customTrailing = customTrailing
    }
    
    var body: some View {
        HStack(spacing: 12) {
            navButton(icon: "chevron.left", action: onBack)
            
            Spacer(minLength: 8)
            
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.black.opacity(0.78))
                .lineLimit(1)
            
            Spacer(minLength: 8)
            
            if let custom = customTrailing {
                custom
            } else if let icon = trailingIcon,
               let action = trailingAction {
                navButton(icon: icon, action: action)
            } else {
                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(Color.clear)
    }
    
    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: icon == "plus" ? 17 : 15, weight: .semibold))
                .foregroundColor(themeColor.opacity(0.85))
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

