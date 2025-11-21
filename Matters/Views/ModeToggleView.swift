import SwiftUI

struct ModeToggleView: View {
    @Binding var selectedMode: AppMode

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Button(action: {
                        HapticFeedback.light()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            selectedMode = mode
                        }
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white)
                            .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                            .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                            .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                            .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    // 黄绿色霓虹滑动指示器
                    let buttonWidth = geo.size.width / CGFloat(AppMode.allCases.count)
                    let offset = buttonWidth * CGFloat(AppMode.allCases.firstIndex(of: selectedMode) ?? 0)

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
                    .frame(width: buttonWidth - 8, height: geo.size.height - 8)
                    .position(x: offset + buttonWidth / 2, y: geo.size.height / 2)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 2)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 1)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: selectedMode)
                }
            )
            .background(
                // 半透明玻璃胶囊背景
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .overlay(
                        Capsule()
                            .stroke(Color.black, lineWidth: 2.5)
                    )
            )
        }
        .frame(width: 240, height: 36)
    }
}

#Preview {
    ZStack {
        Color(white: 0.9)
        ModeToggleView(selectedMode: .constant(.work))
    }
}

