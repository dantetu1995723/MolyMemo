import UIKit
import PDFKit

/// 报销PDF生成器
class ExpensePDFGenerator {
    
    /// 为多个事件分组生成汇总PDF文档
    /// - Parameter groupedExpenses: 按事件分组的报销列表 [(事件名称, [报销项目])]
    /// - Returns: PDF数据
    static func generateGroupedPDF(groupedExpenses: [(String, [Expense])]) -> Data? {
        // PDF页面尺寸（A4）
        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        // 页边距
        let margin: CGFloat = 40
        let contentWidth = pageWidth - 2 * margin
        
        var currentY: CGFloat = margin
        
        // 创建PDF上下文
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        
        // 开始第一页
        UIGraphicsBeginPDFPage()
        
        // 绘制总标题
        let titleText = "报销发票汇总（全部事件）"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let titleSize = titleText.size(withAttributes: titleAttributes)
        titleText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
        currentY += titleSize.height + 10
        
        // 生成日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        let dateText = "生成时间：\(dateFormatter.string(from: Date()))"
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.gray
        ]
        let dateSize = dateText.size(withAttributes: dateAttributes)
        dateText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: dateAttributes)
        currentY += dateSize.height + 8
        
        // 事件数量
        let eventCountText = "共 \(groupedExpenses.count) 个事件"
        let eventCountSize = eventCountText.size(withAttributes: dateAttributes)
        eventCountText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: dateAttributes)
        currentY += eventCountSize.height + 20
        
        // 分隔线
        drawDivider(at: currentY, margin: margin, contentWidth: contentWidth)
        currentY += 30
        
        // 遍历每个事件分组
        for (eventIndex, group) in groupedExpenses.enumerated() {
            let eventName = group.0
            let expenses = group.1
            
            // 从第二个事件开始，每个事件都从新页开始
            if eventIndex > 0 {
                UIGraphicsBeginPDFPage()
                currentY = margin
            }
            
            // 事件标题
            let eventTitleText = "\(eventIndex + 1). \(eventName)"
            let eventTitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let eventTitleSize = eventTitleText.size(withAttributes: eventTitleAttributes)
            eventTitleText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: eventTitleAttributes)
            currentY += eventTitleSize.height + 15
            
            // 收集该事件的所有发票图片
            var eventImages: [(image: UIImage, expense: Expense)] = []
            for expense in expenses {
                if let imageDataArray = expense.imageData {
                    for imageData in imageDataArray {
                        if let image = UIImage(data: imageData) {
                            eventImages.append((image, expense))
                        }
                    }
                }
            }
            
            // 如果有图片，绘制图片
            if !eventImages.isEmpty {
                for (imageIndex, item) in eventImages.enumerated() {
                    let image = item.image
                    let expense = item.expense
                    
                    // 计算图片显示尺寸
                    let maxImageHeight: CGFloat = 400
                    let imageSize = calculateImageSize(image: image, maxWidth: contentWidth, maxHeight: maxImageHeight)
                    
                    // 检查是否需要新页面
                    let requiredHeight = imageSize.height + 60 + 30
                    if currentY + requiredHeight > pageHeight - margin {
                        UIGraphicsBeginPDFPage()
                        currentY = margin
                    }
                    
                    // 绘制报销信息
                    let infoText = "  [\(imageIndex + 1)] \(expense.title) - \(expense.formattedAmount)"
                    let infoAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                        .foregroundColor: UIColor.darkGray
                    ]
                    let infoSize = infoText.size(withAttributes: infoAttributes)
                    infoText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: infoAttributes)
                    currentY += infoSize.height + 10
                    
                    // 绘制图片
                    let imageRect = CGRect(x: margin, y: currentY, width: imageSize.width, height: imageSize.height)
                    image.draw(in: imageRect)
                    currentY += imageSize.height + 25
                }
            } else {
                // 无图片时，显示报销明细表
                let noImageText = "  该事件暂无发票图片"
                let noImageAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: UIColor.gray
                ]
                let noImageSize = noImageText.size(withAttributes: noImageAttributes)
                noImageText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: noImageAttributes)
                currentY += noImageSize.height + 15
            }
            
            // 事件汇总信息
            let totalAmount = expenses.reduce(0.0) { $0 + $1.amount }
            let summaryText = "  小计：\(expenses.count)项  金额：¥\(String(format: "%.2f", totalAmount))"
            let summaryAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            
            // 背景框
            let summarySize = summaryText.size(withAttributes: summaryAttributes)
            let summaryRect = CGRect(x: margin, y: currentY, width: contentWidth, height: summarySize.height + 12)
            UIColor(red: 0.85, green: 1.0, blue: 0.25, alpha: 0.2).setFill()
            UIBezierPath(roundedRect: summaryRect, cornerRadius: 6).fill()
            
            summaryText.draw(at: CGPoint(x: margin + 8, y: currentY + 6), withAttributes: summaryAttributes)
            currentY += summarySize.height + 12 + 30
        }
        
        // 总计
        if currentY + 80 > pageHeight - margin {
            UIGraphicsBeginPDFPage()
            currentY = margin
        }
        
        drawDivider(at: currentY, margin: margin, contentWidth: contentWidth)
        currentY += 20
        
        let allExpenses = groupedExpenses.flatMap { $0.1 }
        let grandTotal = allExpenses.reduce(0.0) { $0 + $1.amount }
        
        let grandTotalText = "总计：\(allExpenses.count)项  金额：¥\(String(format: "%.2f", grandTotal))"
        let grandTotalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        
        let grandTotalSize = grandTotalText.size(withAttributes: grandTotalAttributes)
        let grandTotalRect = CGRect(x: margin, y: currentY, width: contentWidth, height: grandTotalSize.height + 16)
        UIColor(red: 0.85, green: 1.0, blue: 0.25, alpha: 0.4).setFill()
        UIBezierPath(roundedRect: grandTotalRect, cornerRadius: 8).fill()
        
        grandTotalText.draw(at: CGPoint(x: margin + 12, y: currentY + 8), withAttributes: grandTotalAttributes)
        
        // 结束PDF上下文
        UIGraphicsEndPDFContext()
        
        return pdfData as Data
    }
    
    /// 为指定的报销列表生成PDF文档
    /// - Parameters:
    ///   - expenses: 报销列表
    ///   - eventName: 事件名称（用于PDF标题）
    /// - Returns: PDF数据
    static func generatePDF(for expenses: [Expense], eventName: String?) -> Data? {
        // PDF页面尺寸（A4）
        let pageWidth: CGFloat = 595.2  // A4宽度（点）
        let pageHeight: CGFloat = 841.8  // A4高度（点）
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        // 页边距
        let margin: CGFloat = 40
        let contentWidth = pageWidth - 2 * margin
        
        var currentY: CGFloat = margin
        var isFirstPage = true
        
        // 创建PDF上下文
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        
        // 开始第一页
        UIGraphicsBeginPDFPage()
        
        // 绘制标题
        currentY = drawTitle(eventName: eventName, at: currentY, margin: margin, contentWidth: contentWidth)
        currentY += 20
        
        // 绘制分隔线
        drawDivider(at: currentY, margin: margin, contentWidth: contentWidth)
        currentY += 30
        
        // 收集所有发票图片
        var allImages: [(image: UIImage, expense: Expense)] = []
        for expense in expenses {
            if let imageDataArray = expense.imageData {
                for imageData in imageDataArray {
                    if let image = UIImage(data: imageData) {
                        allImages.append((image, expense))
                    }
                }
            }
        }
        
        // 如果没有图片，生成汇总页
        if allImages.isEmpty {
            drawNoImagesMessage(at: currentY, margin: margin, contentWidth: contentWidth)
            currentY += 60
            
            // 绘制报销汇总
            currentY = drawExpenseSummary(expenses: expenses, at: currentY, margin: margin, contentWidth: contentWidth, pageHeight: pageHeight, pageRect: pageRect)
        } else {
            // 逐张绘制发票图片
            for (index, item) in allImages.enumerated() {
                let image = item.image
                let expense = item.expense
                
                // 计算图片显示尺寸（保持宽高比，适应页面）
                let maxImageHeight: CGFloat = 500
                let imageSize = calculateImageSize(image: image, maxWidth: contentWidth, maxHeight: maxImageHeight)
                
                // 检查是否需要新页面（图片 + 信息文字 + 间距）
                let requiredHeight = imageSize.height + 80 + 40
                if currentY + requiredHeight > pageHeight - margin && !isFirstPage {
                    // 开始新页面
                    UIGraphicsBeginPDFPage()
                    currentY = margin
                }
                
                isFirstPage = false
                
                // 绘制报销信息
                currentY = drawExpenseInfo(expense: expense, index: index + 1, at: currentY, margin: margin, contentWidth: contentWidth)
                currentY += 15
                
                // 绘制图片
                let imageRect = CGRect(x: margin, y: currentY, width: imageSize.width, height: imageSize.height)
                image.draw(in: imageRect)
                currentY += imageSize.height + 40
            }
        }
        
        // 结束PDF上下文
        UIGraphicsEndPDFContext()
        
        return pdfData as Data
    }
    
    // MARK: - 辅助绘制方法
    
    /// 绘制标题
    private static func drawTitle(eventName: String?, at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var currentY = y
        
        // 主标题
        let titleText = "报销发票汇总"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let titleSize = titleText.size(withAttributes: titleAttributes)
        titleText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
        currentY += titleSize.height + 10
        
        // 事件名称
        if let event = eventName, !event.isEmpty {
            let eventText = "事件：\(event)"
            let eventAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            let eventSize = eventText.size(withAttributes: eventAttributes)
            eventText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: eventAttributes)
            currentY += eventSize.height + 8
        }
        
        // 生成日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        let dateText = "生成时间：\(dateFormatter.string(from: Date()))"
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.gray
        ]
        let dateSize = dateText.size(withAttributes: dateAttributes)
        dateText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: dateAttributes)
        currentY += dateSize.height
        
        return currentY
    }
    
    /// 绘制分隔线
    private static func drawDivider(at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        UIColor.lightGray.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    
    /// 绘制报销信息文字
    private static func drawExpenseInfo(expense: Expense, index: Int, at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var currentY = y
        
        // 序号和标题
        let titleText = "发票 \(index) - \(expense.title)"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        let titleSize = titleText.size(withAttributes: titleAttributes)
        titleText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
        currentY += titleSize.height + 6
        
        // 详细信息
        var infoText = "金额：\(expense.formattedAmount)"
        if let category = expense.category {
            infoText += "  |  类别：\(category)"
        }
        infoText += "  |  时间：\(expense.occurredDateText)"
        
        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        let infoSize = infoText.size(withAttributes: infoAttributes)
        infoText.draw(at: CGPoint(x: margin, y: currentY), withAttributes: infoAttributes)
        currentY += infoSize.height
        
        return currentY
    }
    
    /// 计算图片显示尺寸
    private static func calculateImageSize(image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let imageSize = image.size
        let widthRatio = maxWidth / imageSize.width
        let heightRatio = maxHeight / imageSize.height
        let ratio = min(widthRatio, heightRatio)
        
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }
    
    /// 绘制无图片提示
    private static func drawNoImagesMessage(at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) {
        let message = "此报销项目暂无发票图片附件"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.gray
        ]
        let messageSize = message.size(withAttributes: attributes)
        let x = margin + (contentWidth - messageSize.width) / 2
        message.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
    
    /// 绘制报销汇总表
    private static func drawExpenseSummary(expenses: [Expense], at y: CGFloat, margin: CGFloat, contentWidth: CGFloat, pageHeight: CGFloat, pageRect: CGRect) -> CGFloat {
        var currentY = y
        
        // 汇总标题
        let summaryTitle = "报销明细汇总"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let titleSize = summaryTitle.size(withAttributes: titleAttributes)
        summaryTitle.draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
        currentY += titleSize.height + 20
        
        // 表头
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        
        let headerHeight: CGFloat = 30
        let headerRect = CGRect(x: margin, y: currentY, width: contentWidth, height: headerHeight)
        UIColor(red: 0.85, green: 1.0, blue: 0.25, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 6).fill()
        
        "项目名称".draw(at: CGPoint(x: margin + 10, y: currentY + 8), withAttributes: headerAttributes)
        "金额".draw(at: CGPoint(x: margin + contentWidth - 80, y: currentY + 8), withAttributes: headerAttributes)
        currentY += headerHeight + 5
        
        // 表格内容
        let rowAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.black
        ]
        
        let rowHeight: CGFloat = 28
        var totalAmount: Double = 0
        
        for (index, expense) in expenses.enumerated() {
            // 检查是否需要新页面
            if currentY + rowHeight + 60 > pageHeight - margin {
                UIGraphicsBeginPDFPage()
                currentY = margin
            }
            
            // 行背景
            let rowRect = CGRect(x: margin, y: currentY, width: contentWidth, height: rowHeight)
            (index % 2 == 0 ? UIColor(white: 0.95, alpha: 1.0) : UIColor.white).setFill()
            UIBezierPath(rect: rowRect).fill()
            
            // 绘制内容
            expense.title.draw(at: CGPoint(x: margin + 10, y: currentY + 7), withAttributes: rowAttributes)
            expense.formattedAmount.draw(at: CGPoint(x: margin + contentWidth - 80, y: currentY + 7), withAttributes: rowAttributes)
            
            totalAmount += expense.amount
            currentY += rowHeight
        }
        
        currentY += 10
        
        // 总计
        let totalRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 35)
        UIColor(red: 0.85, green: 1.0, blue: 0.25, alpha: 0.3).setFill()
        UIBezierPath(roundedRect: totalRect, cornerRadius: 6).fill()
        
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        
        "合计".draw(at: CGPoint(x: margin + 10, y: currentY + 10), withAttributes: totalAttributes)
        
        let totalAmountText = String(format: "¥%.2f", totalAmount)
        totalAmountText.draw(at: CGPoint(x: margin + contentWidth - 80, y: currentY + 10), withAttributes: totalAttributes)
        
        currentY += 35
        
        return currentY
    }
}

