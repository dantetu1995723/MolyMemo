import Foundation
import UIKit
import WebKit

// AI智能表单填写服务
// 结合传统规则 + AI视觉理解，适配各种开票平台
@MainActor
class AIFormFillerService {
    
    // 智能填写表单（两阶段策略）
    static func intelligentFillForm(
        webView: WKWebView,
        companyInfo: CompanyInfo,
        onSuccess: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        
        // 阶段1：先用传统规则快速尝试
        fillFormWithRules(webView: webView, companyInfo: companyInfo) { success in
            if success {
                onSuccess()
            } else {
                // 阶段2：AI辅助填写
                Task {
                    await fillFormWithAI(
                        webView: webView,
                        companyInfo: companyInfo,
                        onSuccess: onSuccess,
                        onError: onError
                    )
                }
            }
        }
    }
    
    // 阶段1：传统规则填写
    private static func fillFormWithRules(
        webView: WKWebView,
        companyInfo: CompanyInfo,
        completion: @escaping (Bool) -> Void
    ) {
        let companyNameEscaped = companyInfo.companyName.replacingOccurrences(of: "'", with: "\\'")
        let taxNumberEscaped = (companyInfo.taxNumber ?? "").replacingOccurrences(of: "'", with: "\\'")
        let phoneNumberEscaped = (companyInfo.phoneNumber ?? "").replacingOccurrences(of: "'", with: "\\'")
        let emailEscaped = (companyInfo.email ?? "").replacingOccurrences(of: "'", with: "\\'")
        
        let javascript = """
        (function() {
            var filledCount = 0;
            var coreFieldsFilled = 0;  // 核心字段（公司名、税号）
            
            // 填写输入框
            function fillInput(selector, value) {
                const input = document.querySelector(selector);
                if (input && value) {
                    input.value = value;
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true }));
                    console.log('✅ 已填写: ' + selector);
                    return true;
                }
                return false;
            }
            
            // 尝试填写公司名称
            const companySelectors = [
                'input[placeholder*="抬头"]',
                'input[placeholder*="企业名称"]',
                'input[placeholder*="公司名称"]',
                'input[name*="company"]',
                'input[name*="title"]',
                'input[id*="company"]',
                'input[id*="title"]'
            ];
            for (let s of companySelectors) {
                if (fillInput(s, '\(companyNameEscaped)')) {
                    filledCount++;
                    coreFieldsFilled++;
                    break;
                }
            }
            
            // 尝试填写税号
            const taxSelectors = [
                'input[placeholder*="税号"]',
                'input[placeholder*="纳税人识别号"]',
                'input[name*="tax"]',
                'input[id*="tax"]'
            ];
            for (let s of taxSelectors) {
                if (fillInput(s, '\(taxNumberEscaped)')) {
                    filledCount++;
                    coreFieldsFilled++;
                    break;
                }
            }
            
            // 尝试填写手机号
            const phoneSelectors = [
                'input[placeholder*="手机"]',
                'input[name*="phone"]',
                'input[name*="mobile"]',
                'input[id*="phone"]'
            ];
            for (let s of phoneSelectors) {
                if (fillInput(s, '\(phoneNumberEscaped)')) {
                    filledCount++;
                    break;
                }
            }
            
            // 尝试填写邮箱
            const emailSelectors = [
                'input[placeholder*="邮箱"]',
                'input[type="email"]',
                'input[name*="email"]',
                'input[id*="email"]'
            ];
            for (let s of emailSelectors) {
                if (fillInput(s, '\(emailEscaped)')) {
                    filledCount++;
                    break;
                }
            }
            
            // 只要填写了至少1个核心字段（公司名或税号），就认为成功
            // 如果两个都填上了更好，但不强制要求
            console.log('✅ 填写统计：总共' + filledCount + '个字段，核心字段' + coreFieldsFilled + '个');
            return coreFieldsFilled >= 1;
        })();
        """
        
        webView.evaluateJavaScript(javascript) { result, error in
            if error != nil {
                completion(false)
                return
            }
            completion((result as? Bool) == true)
        }
    }
    
    // 阶段2：AI辅助填写
    private static func fillFormWithAI(
        webView: WKWebView,
        companyInfo: CompanyInfo,
        onSuccess: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        
        // 1. 截取当前页面
        guard let screenshot = await captureWebViewScreenshot(webView: webView) else {
            onError("无法截取页面")
            return
        }
        
        
        // 2. 调用AI分析页面结构
        let prompt = """
        请分析这个开票表单页面，识别以下输入字段的位置：
        1. 公司名称/抬头 输入框
        2. 税号/纳税人识别号 输入框
        3. 手机号 输入框
        4. 邮箱 输入框
        5. 提交按钮
        
        对于每个字段，请提供最准确的CSS选择器或XPath。
        
        要求：
        - 如果看到输入框的placeholder、label或附近文字，用它来确定字段类型
        - 优先返回ID选择器（最准确）
        - 如果是自定义组件（如div contenteditable），请特别说明
        - 如果某个字段不存在，明确说明
        
        请以JSON格式返回，例如：
        {
          "companyName": {"selector": "#company_name", "type": "input"},
          "taxNumber": {"selector": "#tax_id", "type": "input"},
          "phone": {"selector": "#mobile", "type": "input"},
          "email": {"selector": "#email", "type": "input"},
          "submitButton": {"selector": ".submit-btn", "type": "button"}
        }
        """
        
        do {
            let analysisResult = try await analyzeFormWithAI(screenshot: screenshot, prompt: prompt)
            
            // 3. 解析AI返回的选择器
            guard let selectors = parseAIResponse(analysisResult) else {
                onError("AI分析结果解析失败")
                return
            }
            
            // 4. 根据AI返回的选择器生成填写代码
            let fillScript = generateFillScript(selectors: selectors, companyInfo: companyInfo)
            
            // 5. 执行填写（使用 async API，避免 evaluateJavaScript 的 deprecation/提示）
            do {
                _ = try await webView.evaluateJavaScript(fillScript)
            } catch {
                onError("填写失败：\(error.localizedDescription)")
                return
            }

            // 尝试点击提交按钮
            if let submitSelector = selectors["submitButton"]?["selector"] as? String {
                let submitScript = "document.querySelector('\(submitSelector)')?.click();"
                _ = try? await webView.evaluateJavaScript(submitScript)
            }
            onSuccess()
            
        } catch {
            onError("AI分析失败：\(error.localizedDescription)")
        }
    }
    
    // 截取WebView页面
    private static func captureWebViewScreenshot(webView: WKWebView) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKSnapshotConfiguration()
                webView.takeSnapshot(with: config) { image, error in
                    if error != nil {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    // 调用AI分析表单
    private static func analyzeFormWithAI(screenshot: UIImage, prompt: String) async throws -> String {
        // Qwen 已弃用：统一走自有后端做视觉分析
        let resizedImage = resizeImage(screenshot, maxSize: 2048)
        let instruction = "你是专业的网页表单分析专家，擅长识别表单字段并提供精确的CSS选择器。"
        let fullPrompt = instruction + "\n\n" + prompt
        return try await BackendAIService.generateText(prompt: fullPrompt, images: [resizedImage], mode: .work)
    }
    
    // 压缩图片
    private static func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }
        
        let ratio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxSize, height: maxSize / ratio)
        } else {
            newSize = CGSize(width: maxSize * ratio, height: maxSize)
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // 解析AI返回的JSON
    private static func parseAIResponse(_ response: String) -> [String: [String: Any]]? {
        // 提取JSON部分（AI可能返回带解释的文字）
        guard let jsonStart = response.range(of: "{"),
              let jsonEnd = response.range(of: "}", options: .backwards) else {
            return nil
        }
        
        let jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: [String: Any]] else {
            return nil
        }
        
        return json
    }
    
    // 根据AI返回的选择器生成填写脚本
    private static func generateFillScript(selectors: [String: [String: Any]], companyInfo: CompanyInfo) -> String {
        var script = "(function() {\n"
        
        // 填写公司名称
        if let info = selectors["companyName"],
           let selector = info["selector"] as? String {
            let value = companyInfo.companyName.replacingOccurrences(of: "'", with: "\\'")
            script += "  const company = document.querySelector('\(selector)');\n"
            script += "  if (company) {\n"
            script += "    company.value = '\(value)';\n"
            script += "    company.dispatchEvent(new Event('input', { bubbles: true }));\n"
            script += "    company.dispatchEvent(new Event('change', { bubbles: true }));\n"
            script += "  }\n"
        }
        
        // 填写税号
        if let info = selectors["taxNumber"],
           let selector = info["selector"] as? String,
           let taxNumber = companyInfo.taxNumber {
            let value = taxNumber.replacingOccurrences(of: "'", with: "\\'")
            script += "  const tax = document.querySelector('\(selector)');\n"
            script += "  if (tax) {\n"
            script += "    tax.value = '\(value)';\n"
            script += "    tax.dispatchEvent(new Event('input', { bubbles: true }));\n"
            script += "    tax.dispatchEvent(new Event('change', { bubbles: true }));\n"
            script += "  }\n"
        }
        
        // 填写手机号
        if let info = selectors["phone"],
           let selector = info["selector"] as? String,
           let phone = companyInfo.phoneNumber {
            let value = phone.replacingOccurrences(of: "'", with: "\\'")
            script += "  const mobile = document.querySelector('\(selector)');\n"
            script += "  if (mobile) {\n"
            script += "    mobile.value = '\(value)';\n"
            script += "    mobile.dispatchEvent(new Event('input', { bubbles: true }));\n"
            script += "    mobile.dispatchEvent(new Event('change', { bubbles: true }));\n"
            script += "  }\n"
        }
        
        // 填写邮箱
        if let info = selectors["email"],
           let selector = info["selector"] as? String,
           let email = companyInfo.email {
            let value = email.replacingOccurrences(of: "'", with: "\\'")
            script += "  const emailInput = document.querySelector('\(selector)');\n"
            script += "  if (emailInput) {\n"
            script += "    emailInput.value = '\(value)';\n"
            script += "    emailInput.dispatchEvent(new Event('input', { bubbles: true }));\n"
            script += "    emailInput.dispatchEvent(new Event('change', { bubbles: true }));\n"
            script += "  }\n"
        }
        
        script += "  return true;\n"
        script += "})();"
        
        return script
    }
}

