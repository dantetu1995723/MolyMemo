import SwiftUI

struct InvoiceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var invoice: InvoiceCard
    
    @State private var editedInvoice: InvoiceCard
    @State private var showDeleteMenu = false
    
    // 颜色定义
    private let bgColor = Color(red: 0.97, green: 0.97, blue: 0.97)
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    private let iconColor = Color(hex: "CCCCCC")
    
    // 预定义费用类型
    private let expenseTypes = ["餐饮", "交通", "住宿", "办公", "娱乐", "招待费", "其他"]
    // 预定义报销集
    private let reimbursementSets = ["王总来北京出差报销", "12月办公用品采购", "项目二季度差旅", "未分类"]
    
    // 外部传入的回调
    var onDelete: (() -> Void)? = nil
    
    init(invoice: Binding<InvoiceCard>, onDelete: (() -> Void)? = nil) {
        self._invoice = invoice
        self._editedInvoice = State(initialValue: invoice.wrappedValue)
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Amount Section
                    VStack(spacing: 8) {
                        Text("¥ \(String(format: "%.0f", editedInvoice.amount))")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(primaryTextColor)
                    }
                    .padding(.top, 10)
                    
                    // Info List
                    VStack(spacing: 0) {
                        InfoRowView(title: "商户名称", value: editedInvoice.merchantName)
                        InfoRowView(title: "发票号", value: editedInvoice.invoiceNumber)
                        InfoRowView(title: "开票日期", value: formatDate(editedInvoice.date))
                        
                        // Pickers
                        PickerRowView(title: "费用类型", selection: $editedInvoice.type, options: expenseTypes)
                        PickerRowView(title: "所属报销集", selection: .constant("王总来北京出差报销"), options: reimbursementSets)
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Notes Section
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 18))
                            .foregroundColor(iconColor)
                            .frame(width: 24)
                        
                        TextField("添加描述信息", text: Binding(
                            get: { editedInvoice.notes ?? "" },
                            set: { editedInvoice.notes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .font(.system(size: 16))
                        .foregroundColor(primaryTextColor)
                        .lineSpacing(6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    
                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .background(bgColor)
        .onDisappear {
            // 自动保存编辑的内容
            invoice = editedInvoice
        }
    }
    
    private var headerView: some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showDeleteMenu = true
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                }
            }
            
            Text("发票记录")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(primaryTextColor)
            
            if showDeleteMenu {
                InvoiceDeletePillButton(
                    onDelete: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showDeleteMenu = false
                        }
                        HapticFeedback.medium()
                        onDelete?()
                        dismiss()
                    }
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 44 + 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .zIndex(100)
        .overlay {
            if showDeleteMenu {
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { withAnimation { showDeleteMenu = false } }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}

struct InvoiceDeletePillButton: View {
    var onDelete: () -> Void
    var body: some View {
        Button(action: onDelete) {
            HStack(spacing: 8) {
                Image(systemName: "trash").font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: "FF3B30"))
                Text("删除记录").foregroundColor(Color(hex: "FF3B30")).font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.leading, 20).padding(.trailing, 16).frame(width: 200, height: 52)
            .background(Capsule().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

// MARK: - Subviews

struct InfoRowView: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(Color(hex: "666666"))
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 17))
                .foregroundColor(Color(hex: "333333"))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 14)
    }
}

struct PickerRowView: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(Color(hex: "666666"))
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection = option
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection)
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: "333333"))
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "CCCCCC"))
                }
            }
        }
        .padding(.vertical, 14)
    }
}

