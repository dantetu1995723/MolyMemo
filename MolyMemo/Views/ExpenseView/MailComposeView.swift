import SwiftUI
import MessageUI

/// 邮件发送视图
struct MailComposeView: UIViewControllerRepresentable {
    let pdfData: Data
    let eventName: String
    let recipientEmail: String
    
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        
        // 设置收件人
        if !recipientEmail.isEmpty {
            composer.setToRecipients([recipientEmail])
        }
        
        // 设置主题
        let subject = eventName.isEmpty ? "报销发票" : "报销发票 - \(eventName)"
        composer.setSubject(subject)
        
        // 设置正文
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日"
        let dateString = dateFormatter.string(from: Date())
        
        let messageBody = """
        您好，
        
        附件是\(eventName.isEmpty ? "" : "【\(eventName)】")的报销发票PDF文档，请查收。
        
        生成日期：\(dateString)
        
        此邮件由Yuanyuan报销管理系统自动生成。
        """
        
        composer.setMessageBody(messageBody, isHTML: false)
        
        // 附加PDF文件
        let fileName = eventName.isEmpty ? "报销发票.pdf" : "报销发票-\(eventName).pdf"
        composer.addAttachmentData(pdfData, mimeType: "application/pdf", fileName: fileName)
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        
        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            switch result {
            case .sent:
                HapticFeedback.success()
            case .saved:
                HapticFeedback.light()
            case .cancelled:
                break
            case .failed:
                HapticFeedback.error()
            @unknown default:
                break
            }
            
            dismiss()
        }
    }
}

/// 检查邮件服务是否可用
extension MailComposeView {
    static var canSendMail: Bool {
        return MFMailComposeViewController.canSendMail()
    }
}

