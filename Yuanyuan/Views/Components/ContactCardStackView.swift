import SwiftUI
import Combine

struct ContactCardStackView: View {
    @Binding var contacts: [ContactCard]
    /// 横向翻页时，用于通知外层 ScrollView 临时禁用上下滚动，避免手势冲突
    @Binding var isParentScrollDisabled: Bool

    /// 短按打开详情（由外部决定如何打开：sheet / push）
    var onOpenDetail: ((ContactCard) -> Void)? = nil
    /// 删除回调（外部可做二次确认）；不提供则默认直接从数组移除
    var onDeleteRequest: ((ContactCard) -> Void)? = nil

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showMenu: Bool = false
    @State private var lastMenuOpenedAt: CFTimeInterval = 0
    
    // Constants
    private let cardHeight: CGFloat = 220 // Adjusted height for contact card
    private let cardWidth: CGFloat = 300
    private let pageSwipeDistanceThreshold: CGFloat = 70
    private let pageSwipeVelocityThreshold: CGFloat = 800
    
    var body: some View {
        VStack(spacing: 8) {
            // Card Stack
            ZStack {
                if contacts.isEmpty {
                    Text("无人脉信息")
                        .foregroundColor(.gray)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color.white)
                        .cornerRadius(24)
                } else {
                    ForEach(0..<contacts.count, id: \.self) { index in
                        // Calculate relative index for cyclic view
                        let relativeIndex = getRelativeIndex(index)
                        
                        // Only show relevant cards for performance
                        if relativeIndex < 4 || relativeIndex == contacts.count - 1 {
                            ContactCardView(contact: $contacts[index])
                                .frame(width: cardWidth, height: cardHeight)
                                .scaleEffect(getScale(relativeIndex) * (index == currentIndex && showMenu ? 1.05 : 1.0))
                                .rotationEffect(.degrees(getRotation(relativeIndex)))
                                .offset(x: getOffsetX(relativeIndex), y: 0)
                                .zIndex(getZIndex(relativeIndex))
                                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                                .contentShape(Rectangle())
                                // 短按：未选中时打开详情；选中（菜单打开）时再次短按取消选中
                                .onTapGesture {
                                    guard index == currentIndex else { return }
                                    if showMenu {
                                        withAnimation { showMenu = false }
                                        return
                                    }
                                    guard CACurrentMediaTime() - lastMenuOpenedAt > 0.18 else { return }
                                    guard contacts.indices.contains(index) else { return }
                                    onOpenDetail?(contacts[index])
                                }
                                // 长按：打开胶囊菜单（与日程一致）
                                .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 20) {
                                    guard index == currentIndex else { return }
                                    guard !showMenu else { return }
                                    lastMenuOpenedAt = CACurrentMediaTime()
                                    HapticFeedback.medium()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        showMenu = true
                                    }
                                }
                                // 胶囊菜单（规格/位置与日程一致：左上角、半透明、offset -60）
                                .overlay(alignment: .topLeading) {
                                    if showMenu && index == currentIndex {
                                        CardCapsuleMenuView(
                                            onEdit: {
                                                guard contacts.indices.contains(index) else { return }
                                                let contact = contacts[index]
                                                withAnimation { showMenu = false }
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    onOpenDetail?(contact)
                                                }
                                            },
                                            onDelete: {
                                                guard contacts.indices.contains(index) else { return }
                                                let contact = contacts[index]
                                                withAnimation { showMenu = false }
                                                if let onDeleteRequest {
                                                    onDeleteRequest(contact)
                                                } else {
                                                    withAnimation {
                                                        contacts.remove(at: index)
                                                        if contacts.isEmpty {
                                                            currentIndex = 0
                                                        } else {
                                                            currentIndex = currentIndex % contacts.count
                                                        }
                                                    }
                                                }
                                            },
                                            onDismiss: {
                                                withAnimation { showMenu = false }
                                            }
                                        )
                                        .offset(y: -60)
                                        .transition(.opacity)
                                        .zIndex(1000)
                                    }
                                }
                                .allowsHitTesting(index == currentIndex)
                        }
                    }
                }
            }
            .frame(height: cardHeight + 20)
            .padding(.horizontal)
            // 横滑翻页：与日程一致（不阻塞长按），竖滑放行给外层 ScrollView
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard !contacts.isEmpty else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) else { return }
                        isParentScrollDisabled = true
                        dragOffset = CGSize(width: dx, height: 0)
                        if showMenu { withAnimation { showMenu = false } }
                    }
                    .onEnded { value in
                        defer {
                            isParentScrollDisabled = false
                            withAnimation(.spring()) { dragOffset = .zero }
                        }
                        guard !contacts.isEmpty else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) else { return }
                        let vx = (value.predictedEndTranslation.width - dx) * 10 // 粗略速度量级
                        withAnimation(.spring()) {
                            if dx > pageSwipeDistanceThreshold || vx > pageSwipeVelocityThreshold {
                                currentIndex = (currentIndex - 1 + contacts.count) % contacts.count
                            } else if dx < -pageSwipeDistanceThreshold || vx < -pageSwipeVelocityThreshold {
                                currentIndex = (currentIndex + 1) % contacts.count
                            }
                        }
                    }
            )
            
            // Pagination Dots
            if contacts.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<contacts.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        // 点击聊天空白处统一取消选中
        .onReceive(NotificationCenter.default.publisher(for: .dismissScheduleMenu)) { _ in
            if showMenu { withAnimation { showMenu = false } }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getRelativeIndex(_ index: Int) -> Int {
        return (index - currentIndex + contacts.count) % contacts.count
    }
    
    private func getScale(_ relativeIndex: Int) -> CGFloat {
        if relativeIndex == 0 {
            return 1.0
        } else {
            return 1.0 - (CGFloat(relativeIndex) * 0.05)
        }
    }
    
    private func getRotation(_ relativeIndex: Int) -> Double {
        if relativeIndex == 0 {
            return Double(dragOffset.width / 20)
        } else {
            return Double(relativeIndex) * 2
        }
    }
    
    private func getOffsetX(_ relativeIndex: Int) -> CGFloat {
        if relativeIndex == 0 {
            return dragOffset.width
        } else {
            return CGFloat(relativeIndex) * 10
        }
    }
    
    private func getZIndex(_ relativeIndex: Int) -> Double {
        if relativeIndex == 0 {
            return 100
        } else {
            return Double(contacts.count - relativeIndex)
        }
    }
}

struct ContactCardView: View {
    @Binding var contact: ContactCard
    @State private var showPhoneSheet: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Name
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(contact.name)
                    .font(.custom("SourceHanSerifSC-Bold", size: 24))
                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                
                Spacer()
            }
            .padding(.bottom, 8)
            
            // Company
            if let company = contact.company {
                Text(company)
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                    .padding(.bottom, 4)
            }
            
            // Title
            if let title = contact.title {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
            } else {
                Spacer().frame(height: 20)
            }
            
            // Divider (参考日程卡片样式)
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
            
            // Phone
            if let phone = contact.phone {
                Button(action: {
                    showPhoneSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "phone")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        
                        Text(phone)
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 10)
            }
            
            // Email
            if let email = contact.email {
                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(width: 20)
                    
                    Text(email)
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .sheet(isPresented: $showPhoneSheet) {
            if let phone = contact.phone {
                PhoneActionSheet(phoneNumber: phone)
                    .presentationDetents([.height(240)])
            }
        }
    }
}

// MARK: - Phone Action Sheet
struct PhoneActionSheet: View {
    let phoneNumber: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 32) {
            // Phone Number
            Text(phoneNumber)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.blue)
                .padding(.top, 24)
            
            // Action Buttons
            HStack(spacing: 16) {
                // Copy Button
                Button(action: {
                    UIPasteboard.general.string = phoneNumber
                    dismiss()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "757575"))
                        
                        Text("复制")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "757575"))
                            .kerning(0.5)
                    }
                    .frame(width: 135, height: 135)
                    .background(Color(hex: "F8F8F8"))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Call Button
                Button(action: {
                    if let url = URL(string: "tel://\(phoneNumber.replacingOccurrences(of: " ", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                    dismiss()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "phone")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "757575"))
                        
                        Text("呼叫")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "757575"))
                            .kerning(0.5)
                    }
                    .frame(width: 135, height: 135)
                    .background(Color(hex: "F8F8F8"))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "FFFFFF"))
    }
}
