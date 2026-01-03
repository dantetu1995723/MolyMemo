import SwiftUI
import Combine

struct InvoiceCardStackView: View {
    @Binding var invoices: [InvoiceCard]

    /// 短按打开详情（由外部打开 InvoiceDetailSheet）
    var onOpenDetail: ((InvoiceCard) -> Void)? = nil
    /// 删除回调（外部可做二次确认）；不提供则默认直接从数组移除
    var onDeleteRequest: ((InvoiceCard) -> Void)? = nil

    @State private var menuInvoiceId: UUID? = nil
    @State private var lastMenuOpenedAt: CFTimeInterval = 0
    @State private var pressingInvoiceId: UUID? = nil
    
    // Constants
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 260
    
    var body: some View {
        VStack(spacing: 8) {
            // 卡片列表 - 垂直排列，不做堆叠
            if invoices.isEmpty {
                Text("无发票信息")
                    .foregroundColor(.gray)
                    .frame(width: cardWidth, height: cardHeight)
                    .background(Color.white)
                    .cornerRadius(24)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ForEach(0..<invoices.count, id: \.self) { index in
                        let invoice = invoices[index]
                        InvoiceCardView(invoice: invoice)
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(menuInvoiceId == invoice.id ? 1.03 : (pressingInvoiceId == invoice.id ? 0.985 : 1.0))
                            .shadow(color: Color.black.opacity(menuInvoiceId == invoice.id ? 0.14 : 0.10),
                                    radius: menuInvoiceId == invoice.id ? 14 : 10,
                                    x: 0,
                                    y: menuInvoiceId == invoice.id ? 8 : 5)
                            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: pressingInvoiceId)
                            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: menuInvoiceId)
                            .contentShape(Rectangle())
                            // 短按：未选中时打开详情；选中（菜单打开）时再次短按取消选中
                            .onTapGesture {
                                if menuInvoiceId == invoice.id {
                                    withAnimation { menuInvoiceId = nil }
                                    return
                                }
                                guard CACurrentMediaTime() - lastMenuOpenedAt > 0.18 else { return }
                                onOpenDetail?(invoice)
                            }
                            // 长按：打开胶囊菜单（与日程一致）
                            .onLongPressGesture(
                                minimumDuration: 0.12,
                                maximumDistance: 20,
                                perform: {
                                    guard menuInvoiceId == nil else { return }
                                    lastMenuOpenedAt = CACurrentMediaTime()
                                    HapticFeedback.selection()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        menuInvoiceId = invoice.id
                                    }
                                },
                                onPressingChanged: { pressing in
                                    if menuInvoiceId != nil { return }
                                    pressingInvoiceId = pressing ? invoice.id : nil
                                }
                            )
                            // 胶囊菜单：左上角上方（不改变卡片 UI）
                            .overlay(alignment: .topLeading) {
                                if menuInvoiceId == invoice.id {
                                    CardCapsuleMenuView(
                                        onEdit: {
                                            withAnimation { menuInvoiceId = nil }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                onOpenDetail?(invoice)
                                            }
                                        },
                                        onDelete: {
                                            withAnimation { menuInvoiceId = nil }
                                            if let onDeleteRequest {
                                                onDeleteRequest(invoice)
                                            } else {
                                                if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
                                                    withAnimation { invoices.remove(at: idx) }
                                                }
                                            }
                                        },
                                        onDismiss: {
                                            withAnimation { menuInvoiceId = nil }
                                        }
                                    )
                                    .offset(y: -60)
                                    .transition(.opacity)
                                    .zIndex(1000)
                                }
                            }
                    }
                }
                .padding(.top, 10) // 与人脉、日程卡片一致，ZStack的frame height是cardHeight+20，卡片居中，上方有10pt空间
                .padding(.horizontal)
            }
            
            // Pagination Dots - 底部横向，和人脉、日程卡片一致
            if invoices.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<invoices.count, id: \.self) { index in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        // 点击聊天空白处统一取消选中
        .onReceive(NotificationCenter.default.publisher(for: .dismissScheduleMenu)) { _ in
            if menuInvoiceId != nil {
                withAnimation { menuInvoiceId = nil }
            }
            pressingInvoiceId = nil
        }
    }
}

struct InvoiceCardView: View {
    let invoice: InvoiceCard
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部区域
            VStack(spacing: 8) {
                Text("*发票记录*")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.top, 14) // 与日程卡片顶部padding一致
                
                HStack {
                    Text(invoice.invoiceNumber)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text(formatDate(invoice.date))
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                
                // 虚线分割
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(Color.gray.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                
                // 商户名称
                Text(invoice.merchantName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .lineLimit(2)
                
                // 类型和金额
                HStack {
                    Text(invoice.type)
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("¥ \(String(format: "%.0f", invoice.amount))")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                
                // 虚线分割
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(Color.gray.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                
                // 备注
                if let notes = invoice.notes {
                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            .background(Color.white)
            
            // 2. 底部锯齿装饰
            SawtoothShape(toothWidth: 12, toothHeight: 6)
                .fill(Color.white)
                .frame(height: 6)
                // 反转一下，让锯齿朝下（默认是矩形底部平的）
                // 实际上我们可以让上面的 VStack 不要有圆角底部，直接接这个锯齿
                // 为了简单，我们让上面的白色背景延伸下来，用 mask 裁剪出锯齿
        }
        // 整个卡片背景和形状
        .background(Color.white)
        .mask(
            TicketMaskShape(toothWidth: 24, toothHeight: 8, cornerRadius: 16)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// 虚线形状
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

// 票据形状遮罩（带圆角和底部锯齿）
struct TicketMaskShape: Shape {
    let toothWidth: CGFloat
    let toothHeight: CGFloat
    let cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // 左上圆角
        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(center: CGPoint(x: cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        
        // 顶部边
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: 0))
        
        // 右上圆角
        path.addArc(center: CGPoint(x: rect.width - cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        
        // 右侧边
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - toothHeight))
        
        // 底部锯齿
        let width = rect.width
        let count = Int(width / toothWidth)
        let actualToothWidth = width / CGFloat(count) // 重新计算宽度以填满
        
        for i in 0..<count {
            let startX = width - CGFloat(i) * actualToothWidth
            // 锯齿尖端朝下
            path.addLine(to: CGPoint(x: startX - actualToothWidth / 2, y: rect.height))
            path.addLine(to: CGPoint(x: startX - actualToothWidth, y: rect.height - toothHeight))
        }
        
        // 左侧边
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        
        path.closeSubpath()
        return path
    }
}

// 仅用于底部的锯齿形状
struct SawtoothShape: Shape {
    let toothWidth: CGFloat
    let toothHeight: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - toothHeight))
        
        let width = rect.width
        let count = Int(width / toothWidth)
        let actualToothWidth = width / CGFloat(count)
        
        for i in 0..<count {
            let startX = width - CGFloat(i) * actualToothWidth
            path.addLine(to: CGPoint(x: startX - actualToothWidth / 2, y: rect.height))
            path.addLine(to: CGPoint(x: startX - actualToothWidth, y: rect.height - toothHeight))
        }
        
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}
