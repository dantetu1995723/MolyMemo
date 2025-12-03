import SwiftUI

/// 重新分类意图类型
enum ReclassifyIntent: String {
    case todo = "生成待办"
    case contact = "生成人脉"
    case expense = "生成报销"
    
    var icon: String {
        switch self {
        case .todo: return "checklist"
        case .contact: return "person.crop.circle"
        case .expense: return "dollarsign.circle"
        }
    }
    
    // 统一使用黄绿色系
    var color: Color {
        return Color(red: 0.85, green: 1.0, blue: 0.25)
    }
}

/// 重新分类气泡 - 当用户觉得识别错误时显示
struct ReclassifyBubble: View {
    let originalImages: [UIImage]
    let onConfirm: (String, String) -> Void  // (意图类型, 补充说明)
    let onCancel: () -> Void
    
    @State private var additionalNote: String = ""  // 补充说明
    @State private var selectedQuickIntent: ReclassifyIntent? = .todo  // 默认选择待办
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("重新识别这张图片")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            // 快捷按钮
            HStack(spacing: 12) {
                ForEach([ReclassifyIntent.todo, ReclassifyIntent.contact, ReclassifyIntent.expense], id: \.self) { intent in
                    quickIntentButton(intent)
                }
            }
            
            // 分隔线和提示
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
                
                Text("补充说明（可选）")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
            }
            
            // 补充说明输入框
            VStack(alignment: .leading, spacing: 8) {
                Text("可以补充一些额外信息帮助我更好理解：")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                TextField("例如：下周要开的会议", text: $additionalNote)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.97))
                    )
                    .focused($isInputFocused)
            }
            
            // 确定和取消按钮
            HStack(spacing: 12) {
                // 取消按钮
                Button(action: {
                    HapticFeedback.light()
                    isInputFocused = false
                    onCancel()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text("取消")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // 确定按钮（永远不禁用）
                Button(action: {
                    HapticFeedback.medium()
                    isInputFocused = false
                    
                    // 获取选择的意图类型
                    let intentType = selectedQuickIntent?.rawValue ?? ReclassifyIntent.todo.rawValue
                    
                    // 传递意图类型和补充说明
                    onConfirm(intentType, additionalNote)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("确定")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 1.0, blue: 0.25),
                                        Color(red: 0.78, green: 0.98, blue: 0.2)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3), radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }
    
    @ViewBuilder
    private func quickIntentButton(_ intent: ReclassifyIntent) -> some View {
        Button(action: {
            HapticFeedback.light()
            selectedQuickIntent = intent
            // 不清空补充说明，让用户可以结合使用
            isInputFocused = false
        }) {
            VStack(spacing: 6) {
                Image(systemName: intent.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(red: 0.78, green: 0.98, blue: 0.2))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.15))
                    )
                
                Text(intent.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedQuickIntent == intent ? Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedQuickIntent == intent ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.black.opacity(0.1),
                        lineWidth: selectedQuickIntent == intent ? 2 : 1
                    )
            )
            .scaleEffect(selectedQuickIntent == intent ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedQuickIntent)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 预览
struct ReclassifyBubble_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ReclassifyBubble(
                originalImages: [],
                onConfirm: { intent, note in
                    print("确认重新分类: \(intent), 补充说明: \(note)")
                },
                onCancel: {
                    print("取消重新分类")
                }
            )
            .padding()
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.95))
    }
}

