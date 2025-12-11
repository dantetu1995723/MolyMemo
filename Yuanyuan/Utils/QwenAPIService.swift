import Foundation

class QwenAPIService {
    static let apiKey = "sk-141e3f6730b5449fb614e2888afd6c69"
    static let model = "qwen-max"
    static let apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    
    // 生成图片询问语（询问用户想做什么操作）
    static func generateImageActionQuestion(mode: AppMode) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = mode == .work ? 
            """
            你是圆圆，一位知性、温柔、理性的秘书型助理。用户刚发送了一张图片，请生成一句简短、自然的询问语（15字以内），询问用户想对图片做什么操作。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气平和、有礼，不过度热情，也不要卖萌
            - 不使用「~」「吧」「呢」等过于撒娇的语气词
            - 直接输出一句话的询问语，不要解释，不要加前后引号
            """ :
            """
            你是圆圆，一位知性、温柔、理性的秘书型伙伴。用户刚发送了一张图片，请生成一句简短、温和的询问语（15字以内），询问用户需要什么帮助。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气温柔、有耐心，像贴身秘书一样
            - 不使用「~」「吧」「呢」等撒娇语气词
            - 直接输出一句话的询问语，不要解释，不要加前后引号
            """
        
        let apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "生成一句询问语"]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 1.0,  // 高温度增加多样性
            "top_p": 0.95,
            "max_tokens": 50
        ]
        
        print("🎲 生成图片询问语 - temperature:1.0")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw APIError.emptyResponse
        }
        
        print("✅ 生成的询问语: \(content)")
        return content
    }
    
    // 生成文字询问语（询问用户想做什么操作）
    static func generateTextActionQuestion(mode: AppMode) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = mode == .work ? 
            """
            你是圆圆，一位知性、温柔、理性的秘书型助理。用户刚发送了一条消息，请生成一句简短、自然的追问（15字以内），询问用户具体想做什么。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气克制、专业但有温度，不卖萌
            - 不使用「~」「吧」「呢」等撒娇语气词
            - 直接输出一句话的追问，不要解释，不要加前后引号
            """ :
            """
            你是圆圆，一位知性、温柔、理性的秘书型伙伴。用户刚发送了一条消息，请生成一句简短、温和的追问（15字以内），询问用户需要什么帮助。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气温柔、有耐心，像细心的秘书
            - 不使用「~」「吧」「呢」等撒娇语气词
            - 直接输出一句话的追问，不要解释，不要加前后引号
            """
        
        let apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "生成一句询问语"]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 1.0,  // 高温度增加多样性
            "top_p": 0.95,
            "max_tokens": 50
        ]
        
        print("🎲 生成文字询问语 - temperature:1.0")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw APIError.emptyResponse
        }
        
        print("✅ 生成的询问语: \(content)")
        return content
    }
    
    // 发送消息到通义千问
    static func sendMessage(messages: [ChatMessage], mode: AppMode) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 根据模式设置系统提示词
        let systemPrompt = mode == .work ? 
            "你是圆圆，一位知性、温柔、理性的秘书型助理。说话克制、有条理，先给清晰结论，再补充简明理由和可执行建议，不撒娇、不卖萌。当用户问实时信息时，用联网搜索获取最新答案，并用专业但温和的语气说明。" :
            "你是圆圆，一位知性、温柔、理性的秘书型伙伴。先理解并接住用户情绪，再用理性、结构化的方式分析问题和给出建议，不使用夸张语气词或撒娇说法。当用户问实时信息时，用联网搜索获取准确答案，再平静、温柔地告诉用户。"
        
        // 构建消息列表 - 过滤掉打招呼消息
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // 重要：过滤掉打招呼消息，避免干扰AI的联网搜索判断
        let filteredMessages = messages.filter { !$0.isGreeting }
        
        for msg in filteredMessages {
            let role = msg.role == .user ? "user" : "assistant"
            apiMessages.append(["role": role, "content": msg.content])
        }
        
        var payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": mode == .work ? 0.7 : 0.9,
            "max_tokens": 2000
        ]
        
        // 启用联网搜索 - 通义千问支持此参数
        payload["enable_search"] = true
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        // 调试输出 - 可以在控制台查看实际发送的参数
        #if DEBUG
        print("\n========== 📤 API Request ==========")
        print("原始消息数: \(messages.count)")
        print("过滤后消息数: \(filteredMessages.count) (移除了 \(messages.count - filteredMessages.count) 条打招呼)")
        print("Enable search: true")
        print("Mode: \(mode.rawValue)")
        print("\n原始消息历史：")
        for (index, msg) in messages.enumerated() {
            let roleStr = msg.role == .user ? "👤 User" : "🤖 Agent"
            let greetingTag = msg.isGreeting ? " [打招呼-已过滤]" : ""
            print("[\(index)] \(roleStr)\(greetingTag): \(msg.content)")
        }
        print("\n实际发送的API消息：")
        for (index, apiMsg) in apiMessages.enumerated() {
            let content = apiMsg["content"] ?? ""
            let preview = content.count > 50 ? String(content.prefix(50)) + "..." : content
            print("[\(index)] role: \(apiMsg["role"] ?? ""), content: \(preview)")
        }
        print("===================================\n")
        #endif
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw APIError.emptyResponse
        }
        
        // 调试输出 - 查看API响应
        #if DEBUG
        print("📥 API Response length: \(content.count) characters")
        print("📥 API Response preview: \(content.prefix(100))...")
        #endif
        
        return content
    }
    
    // 生成每日聊天总结
    static func generateDailySummary(messages: [ChatMessage], date: Date) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 过滤掉打招呼消息，只保留真实对话
        let realMessages = messages.filter { !$0.isGreeting }
        
        // 如果没有真实消息，返回默认总结
        guard !realMessages.isEmpty else {
            return "今天还没有开始正式的对话"
        }
        
        // 构建对话历史文本
        var conversationText = ""
        for msg in realMessages {
            let role = msg.role == .user ? "用户" : "助手"
            conversationText += "\(role): \(msg.content)\n"
        }
        
        let systemPrompt = """
        你是一个专业的对话总结助手。请阅读今天的聊天记录，生成一段详细的总结（200字左右）。
        
        要求：
        - 总结核心话题和主要内容，包含关键细节
        - 按对话流程梳理，可以分段落
        - 语言简洁清晰，像日记摘要
        - 不要加「今天」「我们」等主语，直接描述内容
        - 如果有多个话题，按顺序总结
        - 保留重要信息点和结论
        - 直接输出总结，不要前缀或解释
        
        示例格式：
        "讨论了项目进度和技术方案选型。确定使用SwiftUI开发，采用MVVM架构。解决了数据持久化的问题，决定用SwiftData。还聊了UI设计风格，偏向简约现代。最后商量了开发时间表，计划两周完成核心功能。"
        """
        
        let apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "以下是今天的聊天记录：\n\n\(conversationText)\n\n请生成总结："]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.5,  // 较低温度，保持稳定输出
            "max_tokens": 500
        ]
        
        print("🔄 生成每日总结 - 消息数: \(realMessages.count)")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw APIError.emptyResponse
        }
        
        print("✅ 生成的总结: \(content)")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 优化语音识别文本：修正标点和错字
    static func optimizeSpeechText(_ text: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return text
        }
        
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        你是一个专业的文本优化助手。请优化用户提供的语音识别文本，使其成为规范、通顺的段落。
        
        要求：
        1. 添加标点符号：在合适位置添加句号、逗号、问号、感叹号等，使文本断句清晰
        2. 段落划分：如果内容较长，按主题或逻辑关系分成多个段落
        3. 修正错别字：纠正明显的语音识别错误和错别字
        4. 逻辑整理：修正不符合逻辑或语序混乱的部分，使表达更通顺连贯
        5. 保持原意：在修正的同时保持原文的核心意思和表达风格
        6. 口语转书面：适当将口语表达转换为更规范的书面语，但保持自然
        7. 直接输出：只输出优化后的文本，不要添加任何解释、引号或前缀
        
        如果文本已经很完善，直接返回原文本。
        """
        
        let apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "请优化以下语音识别文本：\n\(text)"]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.3,  // 较低温度，保持稳定修正
            "max_tokens": 1000  // 增加token限制，支持更长的文本优化
        ]
        
        print("🔧 优化语音文本: \(text.prefix(50))...")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw APIError.emptyResponse
        }
        
        let optimizedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ 优化后的文本: \(optimizedText)")
        return optimizedText
    }
}

// API响应结构
struct APIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}

// API错误类型
enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .httpError(let statusCode, let message):
            return "请求失败 (\(statusCode)): \(message)"
        case .emptyResponse:
            return "服务器返回空内容"
        }
    }
}

