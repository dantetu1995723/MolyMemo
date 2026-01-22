import SwiftUI
import Combine
import Foundation
import SwiftData
import UIKit

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
    @State private var isPressingCurrentCard: Bool = false

    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    // Constants
    private let cardHeight: CGFloat = 220 // Adjusted height for contact card
    private let cardWidth: CGFloat = 300
    private let pageSwipeDistanceThreshold: CGFloat = 70
    private let pageSwipeVelocityThreshold: CGFloat = 800
    
    var body: some View {
        let canHorizontalPage = contacts.count > 1
        
        VStack(alignment: .leading, spacing: 8) {
            // Card Stack
            Group {
                if canHorizontalPage {
                    cardStack
                        // 横滑翻页：与日程一致（不阻塞长按），竖滑放行给外层 ScrollView
                        .simultaneousGesture(horizontalPagingGesture)
                } else {
                    // 单张卡片：不响应左右滑动（避免卡片跟手位移/翻页），多张保持现有逻辑
                    cardStack
                }
            }
            
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
            isPressingCurrentCard = false
        }
    }
    
    private var cardStack: some View {
        ZStack {
            if contacts.isEmpty {
                Text("无人脉信息")
                    .foregroundColor(.gray)
                    .frame(width: cardWidth, height: cardHeight)
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                ForEach(0..<contacts.count, id: \.self) { index in
                    // Calculate relative index for cyclic view
                    let relativeIndex = getRelativeIndex(index)
                    let focusScale: CGFloat = (index == currentIndex
                                               ? (showMenu ? 1.05 : (isPressingCurrentCard ? 0.985 : 1.0))
                                               : 1.0)
                    let scale = getScale(relativeIndex) * focusScale
                    
                    // Only show relevant cards for performance
                    if relativeIndex < 4 || relativeIndex == contacts.count - 1 {
                        ContactCardView(contact: $contacts[index])
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(scale)
                            .rotationEffect(.degrees(getRotation(relativeIndex)))
                            .offset(x: getOffsetX(relativeIndex), y: 0)
                            .zIndex(getZIndex(relativeIndex))
                            .shadow(color: Color.black.opacity(showMenu && index == currentIndex ? 0.14 : 0.10),
                                    radius: showMenu && index == currentIndex ? 14 : 10,
                                    x: 0,
                                    y: showMenu && index == currentIndex ? 8 : 5)
                            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPressingCurrentCard)
                            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showMenu)
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
                                // 🚫 废弃卡片不允许再打开详情，避免误编辑旧版本
                                guard !contacts[index].isObsolete else { return }
                                onOpenDetail?(contacts[index])
                            }
                            // 长按：打开胶囊菜单（与日程一致）
                            .onLongPressGesture(
                                minimumDuration: 0.08,
                                maximumDistance: 28,
                                perform: {
                                    guard !contacts[index].isObsolete else { return } // 🚫 废弃卡片不触发菜单
                                    guard index == currentIndex else { return }
                                    guard !showMenu else { return }
                                    lastMenuOpenedAt = CACurrentMediaTime()
                                    HapticFeedback.selection()
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                        showMenu = true
                                    }
                                },
                                onPressingChanged: { pressing in
                                    guard !contacts[index].isObsolete else { return }
                                    guard index == currentIndex else { return }
                                    if showMenu { return }
                                    isPressingCurrentCard = pressing
                                }
                            )
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
                                        },
                                        onRescanAsSchedule: {
                                            guard contacts.indices.contains(index) else { return }
                                            triggerRescanCreateSchedule(from: contacts[index])
                                        },
                                        onRescanAsContact: {
                                            guard contacts.indices.contains(index) else { return }
                                            triggerRescanCreateContact(from: contacts[index])
                                        }
                                    )
                                    // 让胶囊跟随卡片缩放后的左边缘（默认缩放 anchor 是中心，leading 会向左/右移动半个增量）
                                    .offset(x: -(cardWidth * (scale - 1) / 2), y: -60)
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
    }
    
    private var horizontalPagingGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // 单张/空：不做任何横向响应
                guard contacts.count > 1 else { return }
                
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) else { return }
                isParentScrollDisabled = true
                dragOffset = CGSize(width: dx, height: 0)
                if showMenu { withAnimation { showMenu = false } }
            }
            .onEnded { value in
                // 单张/空：不做任何横向响应
                guard contacts.count > 1 else { return }
                
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

    // MARK: - 重新识别：复用“创建日程/人脉”链路（优先带原始截图）
    private func triggerRescanCreateSchedule(from card: ContactCard) {
        let payload = rescanPayload(from: card)
        let text = "创建日程\n\n\(payload)"
        let images = rescanImages(from: card)
        ChatSendFlow.send(appState: appState, modelContext: modelContext, text: text, images: images, includeHistory: true)
    }

    private func triggerRescanCreateContact(from card: ContactCard) {
        let payload = rescanPayload(from: card)
        let text = "创建人脉\n\n\(payload)"
        let images = rescanImages(from: card)
        ChatSendFlow.send(appState: appState, modelContext: modelContext, text: text, images: images, includeHistory: true)
    }

    private func rescanImages(from card: ContactCard) -> [UIImage] {
        guard let data = card.rawImage, let img = UIImage(data: data) else { return [] }
        return [img]
    }

    private func rescanPayload(from card: ContactCard) -> String {
        func t(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var lines: [String] = []
        let name = t(card.name)
        if !name.isEmpty { lines.append("姓名：\(name)") }
        let en = t(card.englishName)
        if !en.isEmpty { lines.append("英文名：\(en)") }
        let company = t(card.company)
        if !company.isEmpty { lines.append("公司：\(company)") }
        let title = t(card.title)
        if !title.isEmpty { lines.append("职位：\(title)") }
        let phone = t(card.phone)
        if !phone.isEmpty { lines.append("电话：\(phone)") }
        let email = t(card.email)
        if !email.isEmpty { lines.append("邮箱：\(email)") }
        let location = t(card.location)
        if !location.isEmpty { lines.append("地区：\(location)") }
        let industry = t(card.industry)
        if !industry.isEmpty { lines.append("行业：\(industry)") }
        let rel = t(card.relationshipType)
        if !rel.isEmpty { lines.append("关系：\(rel)") }
        let notes = t(card.notes)
        if !notes.isEmpty { lines.append("备注：\(notes)") }
        let impression = t(card.impression)
        if !impression.isEmpty { lines.append("印象：\(impression)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Loading (Skeleton) Card
/// 与正式联系人卡片同规格的 loading 卡片，用于工具调用期间占位（避免展示 raw tool 文本）
struct ContactCardLoadingStackView: View {
    var title: String = "创建联系人"
    var subtitle: String = "正在保存联系人信息…"
    
    /// 横向翻页时，用于通知外层 ScrollView 临时禁用上下滚动，避免手势冲突（与正式卡片保持签名一致，方便替换）
    @Binding var isParentScrollDisabled: Bool
    
    // 与 ContactCardStackView 保持一致
    private let cardHeight: CGFloat = 220
    private let cardWidth: CGFloat = 300
    
    init(
        title: String = "创建联系人",
        subtitle: String = "正在保存联系人信息…",
        isParentScrollDisabled: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isParentScrollDisabled = isParentScrollDisabled
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ContactCardLoadingView(title: title, subtitle: subtitle)
                    .frame(width: cardWidth, height: cardHeight)
                    .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
            }
            .frame(height: cardHeight + 20)
        }
    }
}

struct ContactCardLoadingView: View {
    let title: String
    let subtitle: String
    
    private let primaryText = Color(red: 0.2, green: 0.2, blue: 0.2)
    private let skeleton = Color.black.opacity(0.06)
    private let skeletonStrong = Color.black.opacity(0.10)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Title + spinner
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(title)
                    .font(.custom("SourceHanSerifSC-Bold", size: 24))
                    .foregroundColor(primaryText)
                
                Spacer()
                
                ProgressView()
                    .progressViewStyle(.circular)
            }
            .padding(.bottom, 8)
            
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .padding(.bottom, 14)
            
            // Skeleton lines（对齐正式卡片的 company/title 区域）
            RoundedRectangle(cornerRadius: 6)
                .fill(skeletonStrong)
                .frame(width: 160, height: 16)
                .padding(.bottom, 8)
            
            RoundedRectangle(cornerRadius: 6)
                .fill(skeleton)
                .frame(width: 110, height: 14)
                .padding(.bottom, 20)
            
            // Divider（保持一致）
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color(hex: "EEEEEE"))
                    .frame(height: 1)
                
                Circle()
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                    .background(Circle().fill(Color.white))
                    .frame(width: 7, height: 7)
            }
            .padding(.bottom, 20)
            
            // Phone skeleton row
            HStack(spacing: 6) {
                Image(systemName: "phone")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 20)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(skeleton)
                    .frame(width: 140, height: 14)
            }
            .padding(.bottom, 10)
            
            // Email skeleton row
            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 20)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(skeleton)
                    .frame(width: 180, height: 14)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

struct ContactCardView: View {
    @Binding var contact: ContactCard
    @State private var showPhoneSheet: Bool = false

    /// 仅用于「人脉卡片」姓名高亮色
    /// 用纯 SwiftUI Color 避免被 UIKit bridging / 外层样式链路影响
    private let contactNameColor = Color(red: 0.63, green: 0.4, blue: 0.01)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Name
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(contact.name)
                    .font(.custom("SourceHanSerifSC-Bold", size: 24))
                    .foregroundStyle(contact.isObsolete ? Color(hex: "999999") : contactNameColor)
                    .strikethrough(contact.isObsolete, color: Color(hex: "999999"))
                
                Spacer()
            }
            .padding(.bottom, 8)
            
            // Company
            if let company = contact.company {
                Text(company)
                    .font(.system(size: 16))
                    .foregroundColor(contact.isObsolete ? Color(hex: "AAAAAA") : .black)
                    .strikethrough(contact.isObsolete, color: Color(hex: "AAAAAA"))
                    .padding(.bottom, 4)
            }
            
            // Title
            if let title = contact.title {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(contact.isObsolete ? Color(hex: "BBBBBB") : .gray)
                    .strikethrough(contact.isObsolete, color: Color(hex: "BBBBBB"))
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
                    guard !contact.isObsolete else { return }
                    showPhoneSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "phone")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        
                        Text(phone)
                            .font(.system(size: 15))
                            .foregroundColor(contact.isObsolete ? Color(hex: "BBBBBB") : .blue)
                            .strikethrough(contact.isObsolete, color: Color(hex: "BBBBBB"))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 10)
                .disabled(contact.isObsolete)
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
                        .foregroundColor(Color(hex: "BBBBBB"))
                        .strikethrough(contact.isObsolete, color: Color(hex: "BBBBBB"))
                }
            }
            
            Spacer()
        }
        .padding(14)
        .background(contact.isObsolete ? Color(hex: "F9F9F9") : Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(contact.isObsolete ? 0.01 : 0.03), lineWidth: 1)
        )
        .opacity(contact.isObsolete ? 0.8 : 1.0)
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
