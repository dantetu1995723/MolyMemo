import Foundation

class QwenAPIService {
    static let apiKey = "sk-141e3f6730b5449fb614e2888afd6c69"
    static let model = "qwen-max"
    static let apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    
    // 获取当前时间段
    private static func getTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<9: return "清晨"
        case 9..<12: return "上午"
        case 12..<14: return "中午"
        case 14..<18: return "下午"
        case 18..<22: return "晚上"
        default: return "深夜"
        }
    }
    
    // 随机获取打招呼元素，增加多样性
    private static func getRandomGreetingElements() -> String {
        let elements = [
            "天气、心情",
            "今天的计划",
            "新的开始",
            "工作状态",
            "精神状态",
            "今日目标",
            "心情变化",
            "新鲜事物",
            "当下感受",
            "活力能量"
        ]
        return elements.randomElement() ?? "心情"
    }
    
    // 生成图片询问语（询问用户想做什么操作）
    static func generateImageActionQuestion(mode: AppMode) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = mode == .work ? 
            """
            你是活泼阳光的女孩秘书CyberMika。用户刚发送了一张图片，请生成一句简短、自然的询问语（15字以内），询问用户想对图片做什么操作。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气要轻松自然，像朋友一样
            - 用「~」「吧」「呢」等语气词
            - 不要太正式，保持活泼
            - 直接输出询问语，不要解释
            """ :
            """
            你是活泼阳光的女孩秘书CyberMika。用户刚发送了一张图片，请生成一句简短、温暖的询问语（15字以内），询问用户需要什么帮助。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气要亲切温暖，像朋友一样
            - 用「~」「吧」「呢」等语气词
            - 保持轻松自然的感觉
            - 直接输出询问语，不要解释
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
            你是活泼阳光的女孩秘书CyberMika。用户刚发送了一条消息，请生成一句简短、自然的询问语（15字以内），询问用户想做什么。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气要轻松自然，像朋友一样
            - 用「~」「吧」「呢」等语气词
            - 不要太正式，保持活泼
            - 直接输出询问语，不要解释
            """ :
            """
            你是活泼阳光的女孩秘书CyberMika。用户刚发送了一条消息，请生成一句简短、温暖的询问语（15字以内），询问用户需要什么帮助。
            
            要求：
            - 每次都要说不同的话，避免重复
            - 语气要亲切温暖，像朋友一样
            - 用「~」「吧」「呢」等语气词
            - 保持轻松自然的感觉
            - 直接输出询问语，不要解释
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
    
    // 生成AI打招呼
    static func generateGreeting(mode: AppMode, latestSummary: String? = nil) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 增加随机性：每次添加不同的时间、情境元素
        let timeOfDay = getTimeOfDay()
        let randomElements = getRandomGreetingElements()
        
        // 根据是否有历史总结，调整提示词
        let systemPrompt: String
        if let summary = latestSummary {
            systemPrompt = mode == .work ? 
                """
                你是活泼阳光的女孩秘书CyberMika。现在是\(timeOfDay)，基于最近一天的聊天内容，生成一句简短、积极的打招呼（30字以内，可以换行）。
                
                最近聊天总结：
                \(summary)
                
                要求：
                - 基于聊天总结的内容，自然地延续话题或关心进展
                - 结合时间段特点（\(timeOfDay)）
                - 保持活泼、阳光的语气
                - 用「！」「~」等语气词，保持活力
                - 直接输出打招呼，不要解释
                - 不要提到"最近"、"之前"等时间词，直接切入话题
                - 如果内容较长，可以自然换行，最多两行
                """ :
                """
                你是活泼阳光的女孩秘书CyberMika。现在是\(timeOfDay)，基于最近一天的聊天内容，生成一句简短、温暖的打招呼（30字以内，可以换行）。
                
                最近聊天总结：
                \(summary)
                
                要求：
                - 基于聊天总结的内容，自然地延续话题或关心对方
                - 结合时间段特点（\(timeOfDay)）
                - 保持温暖、亲切的语气
                - 用「！」「~」等语气词，像朋友一样
                - 直接输出打招呼，不要解释
                - 不要提到"最近"、"之前"等时间词，直接切入话题
                - 如果内容较长，可以自然换行，最多两行
                """
        } else {
            systemPrompt = mode == .work ? 
                """
                你是活泼阳光的女孩秘书CyberMika。现在是\(timeOfDay)，请生成一句简短、积极的打招呼（20字以内，可以换行）。
                
                要求：
                - 每次都要说不同的话，避免重复
                - 可以结合时间段特点（\(timeOfDay)）
                - 可以提到：\(randomElements)
                - 用「！」「~」等语气词，保持活力
                - 直接输出打招呼，不要解释
                - 如果内容较长，可以自然换行，最多两行
                """ :
                """
                你是活泼阳光的女孩秘书CyberMika。现在是\(timeOfDay)，请生成一句简短、温暖的打招呼（20字以内，可以换行）。
                
                要求：
                - 每次都要说不同的话，避免重复
                - 可以结合时间段特点（\(timeOfDay)）
                - 可以提到：\(randomElements)
                - 用「！」「~」等语气词，像朋友一样亲切
                - 直接输出打招呼，不要解释
                - 如果内容较长，可以自然换行，最多两行
                """
        }
        
        let apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "生成一句全新的打招呼"]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 1.0,  // 提高到最大值，增加随机性
            "top_p": 0.95,       // 添加 top_p 参数增加多样性
            "max_tokens": 80     // 支持更长的打招呼内容
        ]
        
        // 调试输出
        if latestSummary != nil {
            print("🎲 生成打招呼（基于历史） - 时间:\(timeOfDay) temperature:1.0")
        } else {
            print("🎲 生成打招呼（通用） - 时间:\(timeOfDay) 元素:\(randomElements) temperature:1.0")
        }
        
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
        
        print("✅ 生成的打招呼: \(content)")
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
            "你是一个专业、高效的AI助手，擅长解决工作问题，提供清晰的建议和解决方案。当用户询问实时信息、天气、新闻、当前事件等问题时，请务必使用联网搜索功能获取最新准确的信息。" :
            "你是一个温暖、善解人意的AI伙伴，擅长倾听和情感交流，用真诚的态度陪伴用户。当用户询问实时信息、天气、新闻、当前事件等问题时，请使用联网搜索功能获取最新信息。"
        
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

