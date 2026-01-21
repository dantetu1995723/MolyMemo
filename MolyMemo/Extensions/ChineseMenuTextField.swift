import UIKit

/// 支持中文菜单的 UITextField 子类
/// 长按输入框时弹出的菜单项（粘贴、选择、全选、自动填充等）会显示为中文
class ChineseMenuTextField: UITextField {
    
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        
        // 移除默认的编辑菜单
        builder.remove(menu: .standardEdit)
        
        // 创建中文菜单项
        var menuItems: [UIMenuElement] = []
        
        // 粘贴
        if canPerformAction(#selector(paste(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "粘贴", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                self?.paste(nil)
            })
        }
        
        // 选择
        if canPerformAction(#selector(select(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "选择", image: UIImage(systemName: "text.cursor")) { [weak self] _ in
                self?.select(nil)
            })
        }
        
        // 全选
        if canPerformAction(#selector(selectAll(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "全选", image: UIImage(systemName: "textformat")) { [weak self] _ in
                self?.selectAll(nil)
            })
        }
        
        // 复制（如果有选中文本）
        if canPerformAction(#selector(copy(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copy(nil)
            })
        }
        
        // 如果有菜单项，创建菜单并插入
        if !menuItems.isEmpty {
            let menu = UIMenu(title: "", children: menuItems)
            builder.insertSibling(menu, afterMenu: .standardEdit)
        }
    }
}

/// 支持中文菜单的 UITextView 子类
/// 长按输入框时弹出的菜单项（粘贴、选择、全选、自动填充等）会显示为中文
class ChineseMenuTextView: UITextView {
    
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        
        // 移除默认的编辑菜单
        builder.remove(menu: .standardEdit)
        
        // 创建中文菜单项
        var menuItems: [UIMenuElement] = []
        
        // 粘贴
        if canPerformAction(#selector(paste(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "粘贴", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                self?.paste(nil)
            })
        }
        
        // 选择
        if canPerformAction(#selector(select(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "选择", image: UIImage(systemName: "text.cursor")) { [weak self] _ in
                self?.select(nil)
            })
        }
        
        // 全选
        if canPerformAction(#selector(selectAll(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "全选", image: UIImage(systemName: "textformat")) { [weak self] _ in
                self?.selectAll(nil)
            })
        }
        
        // 复制（如果有选中文本）
        if canPerformAction(#selector(copy(_:)), withSender: nil) {
            menuItems.append(UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copy(nil)
            })
        }
        
        // 如果有菜单项，创建菜单并插入
        if !menuItems.isEmpty {
            let menu = UIMenu(title: "", children: menuItems)
            builder.insertSibling(menu, afterMenu: .standardEdit)
        }
    }
}
