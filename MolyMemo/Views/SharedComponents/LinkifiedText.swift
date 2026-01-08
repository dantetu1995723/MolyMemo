import SwiftUI

/// 将文本中识别到的 URL（http/https/www）做成行内可点击链接；普通文字不受影响。
struct LinkifiedText: View {
    let text: String
    var font: Font = .system(size: 16)
    var textColor: Color = Color(hex: "333333")
    var linkColor: Color = .blue
    var lineSpacing: CGFloat = 6
    var lineLimit: Int? = nil
    
    var body: some View {
        Text(Linkifier.attributed(text: text, textColor: textColor, linkColor: linkColor))
            .font(font)
            .lineSpacing(lineSpacing)
            .lineLimit(lineLimit)
    }
}

// MARK: - Linkifier

private enum Linkifier {
    /// 说明：
    /// - 用系统 `NSDataDetector(.link)` 识别 URL，能正确处理“链接后紧跟中文/标点”的场景（不会把中文囊括进链接范围）
    /// - 兼容 www.*（无 scheme）场景：补全为 https://
    private static let linkDetector: NSDataDetector = {
        (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)) ?? NSDataDetector()
    }()
    
    static func attributed(text: String, textColor: Color, linkColor: Color) -> AttributedString {
        let raw = text
        var attributed = AttributedString(raw)
        attributed.foregroundColor = textColor
        
        let ns = raw as NSString
        let matches = linkDetector.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return attributed }
        
        for m in matches.reversed() {
            guard let strRange = Range(m.range, in: raw) else { continue }
            let candidate = String(raw[strRange])
            guard let url = normalizeToURL(candidate, detectedURL: m.url) else { continue }
            
            guard
                let aStart = AttributedString.Index(strRange.lowerBound, within: attributed),
                let aEnd = AttributedString.Index(strRange.upperBound, within: attributed)
            else { continue }
            
            let aRange = aStart..<aEnd
            attributed[aRange].link = url
            attributed[aRange].foregroundColor = linkColor
            attributed[aRange].underlineStyle = .single
        }
        
        return attributed
    }
    
    private static func normalizeToURL(_ raw: String, detectedURL: URL?) -> URL? {
        // 1) detector 给的 URL 优先（range 已经准确）
        if let u = detectedURL {
            // 仅接受网页链接；避免把电话/邮箱等 link 也渲染成网页链接
            if let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return u
            }
        }
        
        // 2) 兜底：处理 www.*（无 scheme）或 detector 未返回 url 的情况
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        
        if s.lowercased().hasPrefix("www.") {
            s = "https://\(s)"
        }
        
        if let u = URL(string: s) { return u }
        
        let allowed = CharacterSet.urlFragmentAllowed.union(.urlQueryAllowed)
        if let encoded = s.addingPercentEncoding(withAllowedCharacters: allowed),
           let u = URL(string: encoded) {
            return u
        }
        
        return nil
    }
}


