import UIKit

/// 分类结果（包含置信度）
struct ClassificationResult {
    let category: ScreenshotCategory
    let confidence: Double  // 0.0 ~ 1.0
    
    /// 是否需要用户确认（置信度低于阈值）
    var needsConfirmation: Bool {
        return confidence < 0.7
    }
}

/// 截图快速分类服务
/// 在 Intent 阶段快速判断截图属于哪个模块（待办/报销/人脉）
struct ScreenshotClassifier {
    
    private static let apiKey = "sk-141e3f6730b5449fb614e2888afd6c69"
    private static let model = "qwen-vl-max-latest"
    private static let apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    
    enum ClassifierError: Error {
        case invalidResponse
        case httpError(statusCode: Int, message: String)
        case parseError
    }
    
    /// 快速分类截图
    /// - Parameter image: 待分类的截图
    /// - Returns: 分类结果（包含置信度）
    static func classifyScreenshot(image: UIImage) async throws -> ClassificationResult {
        print("🔍 开始快速分类截图...")
        
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 系统提示词 - 快速分类（包含置信度）
        let systemPrompt = """
        你是一个图片分类专家，需要快速判断截图属于以下哪个类别：
        
        1. 待办 (todo) - 包含任务、日程、会议、提醒等信息
        2. 报销 (expense) - 包含发票、收据、消费记录、开票二维码等
        3. 人脉 (contact) - 包含名片、联系方式、个人信息等
        4. 未知 (unknown) - 无法明确分类
        
        判断标准：
        - 如果图片中有发票、收据、价格、金额、开票二维码 → expense
        - 如果图片中有日程、时间安排、会议通知、任务列表 → todo
        - 如果图片中有姓名、电话、公司、职位、名片 → contact
        - 如果无法明确判断 → unknown
        
        返回格式：分类|置信度
        例如：todo|0.9 或 expense|0.6 或 unknown|0.3
        置信度范围：0.0-1.0，越高表示越确定
        只返回这一行，不要其他内容。
        """
        
        // 压缩图片
        let resizedImage = resizeImage(image, maxSize: 1024)  // 使用较小尺寸加快速度
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw ClassifierError.invalidResponse
        }
        let base64String = imageData.base64EncodedString()
        
        let contentArray: [[String: Any]] = [
            [
                "type": "text",
                "text": "请快速判断这张截图属于哪个类别"
            ],
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]
            ]
        ]
        
        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": contentArray]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.1,  // 低温度，更确定的结果
            "max_tokens": 10,    // 只需要一个单词
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClassifierError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClassifierError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ClassifierError.parseError
        }
        
        // 解析分类结果（格式：category|confidence）
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        print("📊 AI分类结果: \(trimmedContent)")
        
        let components = trimmedContent.split(separator: "|")
        let categoryString = String(components.first ?? "unknown")
        let confidenceString = components.count > 1 ? String(components[1]) : "0.5"
        let confidence = Double(confidenceString) ?? 0.5
        
        let category: ScreenshotCategory
        if categoryString.contains("todo") {
            category = .todo
        } else if categoryString.contains("expense") {
            category = .expense
        } else if categoryString.contains("contact") {
            category = .contact
        } else {
            category = .unknown
        }
        
        let result = ClassificationResult(category: category, confidence: confidence)
        print("✅ 分类完成: \(category.rawValue), 置信度: \(String(format: "%.2f", confidence))")
        
        return result
    }
    
    // 辅助方法：压缩图片
    private static func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let maxDimension = max(size.width, size.height)
        
        if maxDimension <= maxSize {
            return image
        }
        
        let scale = maxSize / maxDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
}

