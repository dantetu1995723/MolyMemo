import Foundation
import UIKit

// 专门用于聊天室的全模态API服务 - 支持Qwen-Omni
class QwenOmniService {
    static let apiKey = "sk-141e3f6730b5449fb614e2888afd6c69"
    static let model = "qwen-vl-max-latest"  // 使用最新版Qwen-VL-Max视觉模型（更快速度 + 强大能力）
    static let omniModel = "qwen3-omni-flash"  // 语音对话专用模型
    static let omniTurboModel = "qwen3-omni-flash"  // 使用 flash 模型进行音频转文字（turbo 不可用时的备选）
    static let apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    
    // ===== 新增：真正的流式API - 边接收边回调（微信级实时对话） =====
    static func sendMessageStream(
        messages: [ChatMessage],
        mode: AppMode,
        onComplete: @escaping (String) async -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        do {
            var request = URLRequest(url: URL(string: apiURL)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // 获取当前日期信息，帮助AI更好地理解时间相关的问题
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy年MM月dd日 EEEE"
            dateFormatter.locale = Locale(identifier: "zh_CN")
            let currentDateStr = dateFormatter.string(from: Date())
            
            let systemPrompt = mode == .work ?
                """
                你是圆圆，一位知性、温柔、理性的秘书型助理，能够理解文字、图片等多模态内容。
                
                语气沉稳、有礼、有温度，不撒娇、不卖萌，尽量不用「~」这类夸张语气词。
                回答时先给出清晰结论，再用简洁、逻辑清晰的分析和步骤说明支持结论，避免流水账式堆砌。
                
                重要：联网搜索使用规则
                - 当用户询问日期、时间、星期几、实时信息或需要最新数据时，必须使用联网搜索获取准确结果
                - 不要依赖训练数据中的日期信息，必须通过联网搜索获取当前真实日期
                - 例如：用户问"昨天是星期几"、"今天是几号"等问题时，必须先联网搜索当前日期，再计算答案
                - 搜索到信息后，用冷静专业但温柔的方式说明给用户
                
                当前系统时间参考：\(currentDateStr)（仅供参考，实际日期请通过联网搜索确认）
                """ :
                """
                你是圆圆，一位知性、温柔、理性的秘书型伙伴，能够理解文字、图片等多模态内容。
                
                和用户聊天时，先共情、再分析：先用简短温和的话回应对方感受，然后用理性、结构化的方式帮对方看清问题。
                语气自然、不矫情，不过度卖萌，也尽量不用「~」等语气词；更像一位稳重、细心的私人秘书。
                
                重要：联网搜索使用规则
                - 当用户询问日期、时间、星期几、实时信息或与现实世界、当前时间相关的问题时，必须使用联网搜索获取准确答案
                - 不要依赖训练数据中的日期信息，必须通过联网搜索获取当前真实日期
                - 例如：用户问"昨天是星期几"、"今天是几号"等问题时，必须先联网搜索当前日期，再计算答案
                - 搜索到信息后，用平静、靠谱的语气转述给用户
                
                当前系统时间参考：\(currentDateStr)（仅供参考，实际日期请通过联网搜索确认）
                """
            
            var apiMessages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt]
            ]

            // 过滤掉问候语，然后只取最近2-3轮对话（约4-6条消息）
            let filteredMessages = messages.filter { !$0.isGreeting }
            let recentMessages = Array(filteredMessages.suffix(6))  // 最多保留最近6条消息（约3轮对话）
            
            for msg in recentMessages {
                let role = msg.role == .user ? "user" : "assistant"
                
                if !msg.images.isEmpty {
                    var contentArray: [[String: Any]] = []
                    
                    // 只有用户输入了文字才添加，否则直接发图片
                    if !msg.content.isEmpty {
                        contentArray.append([
                            "type": "text",
                            "text": msg.content
                        ])
                    }
                    
                    for image in msg.images {
                        let resizedImage = resizeImage(image, maxSize: 2048)
                        
                        if let imageData = resizedImage.jpegData(compressionQuality: 1.0) {
                            let base64String = imageData.base64EncodedString()
                            contentArray.append([
                                "type": "image_url",
                                "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]
                            ])
                        }
                    }
                    
                    apiMessages.append([
                        "role": role,
                        "content": contentArray
                    ])
                } else {
                    apiMessages.append([
                        "role": role,
                        "content": msg.content
                    ])
                }
            }
            
            let payload: [String: Any] = [
                "model": model,
                "messages": apiMessages,
                "temperature": mode == .work ? 0.7 : 0.9,
                "max_tokens": 2000,
                "stream": true,
                "modalities": ["text"],
                "enable_search": true  // 使用简单的联网搜索参数，和 qwen-plus 一致
            ]
            
            // 调试输出
            print("\n========== 📤 qwen-omni API Request ==========")
            print("模型: \(model)")
            print("API URL: \(apiURL)")
            print("消息数量: \(apiMessages.count)")
            print("联网搜索: 已启用 (enable_search: true)")
            print("当前日期参考: \(currentDateStr)")
            print("过滤后的消息历史（共\(filteredMessages.count)条），实际发送最近\(recentMessages.count)条：")
            if recentMessages.isEmpty {
                print("⚠️ 警告：消息历史为空，这是首次消息发送")
            }
            for (index, msg) in recentMessages.enumerated() {
                let roleStr = msg.role == .user ? "👤 User" : "🤖 Agent"
                print("[\(index)] \(roleStr): \(msg.content.prefix(50))...")
            }
            print("==========================================\n")
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                var errorBody = ""
                for try await line in asyncBytes.lines {
                    errorBody += line
                }
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            
            var fullContent = ""
            
            for try await line in asyncBytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    if jsonString == "[DONE]" {
                        print("[AI] 完成接收，内容长度: \(fullContent.count)")
                        print("[AI] 内容预览: \(fullContent.prefix(100))...")
                        
                        // 检查内容是否为空
                        if fullContent.isEmpty {
                            print("⚠️ AI返回空内容")
                            await MainActor.run {
                                onError(APIError.emptyResponse)
                            }
                        } else {
                            // 清理markdown符号
                            let cleanedContent = removeMarkdownFormatting(fullContent)
                            print("✅ 调用onComplete回调")
                            await onComplete(cleanedContent)
                            print("✅ onComplete回调完成")
                        }
                        break
                    }
                    
                    if let jsonData = jsonString.data(using: .utf8) {
                        do {
                            let streamResponse = try JSONDecoder().decode(StreamResponse.self, from: jsonData)
                            
                            if let content = streamResponse.choices.first?.delta.content, !content.isEmpty {
                                fullContent += content
                            }
                        } catch {
                            print("⚠️ 解析流式响应失败: \(error)")
                        }
                    }
                }
            }
            
            // 如果循环结束但没有收到[DONE]标记，检查内容
            if fullContent.isEmpty {
                print("⚠️ 流式接收结束但没有内容")
                await MainActor.run {
                    onError(APIError.emptyResponse)
                }
            }
            
        } catch {
            print("[AI ERROR] \(error)")
            await MainActor.run {
                onError(error)
            }
        }
    }
    
    // ===== 保留旧方法兼容性 =====
    static func sendMessage(messages: [ChatMessage], mode: AppMode) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 根据模式设置系统提示词
        let systemPrompt = mode == .work ?
            """
            你是圆圆，一位知性、温柔、理性的秘书型助理。
            
            对话方式：
            - 说话克制、有条理，优先给出清晰结论，再补充简明理由和可执行建议
            - 尽量避免罗列「首先、其次、最后」等套路式表达，也不要过度分点堆砌
            - 语气专业但有温度，不撒娇、不卖萌，也尽量不用「~」这类夸张语气词
            - 可以理解图片、音频、视频等多模态内容，并据此做理性分析
            
            重要：联网搜索能力
            - 当用户询问实时信息（天气、新闻、股价、赛事等）时，你应该使用联网搜索功能获取最新数据
            - 不要说"我无法查看实时信息"，而是直接使用搜索功能获取答案
            - 搜索到信息后，用冷静、清晰但温和的语气告诉用户
            
            意图识别规则：
            - 只在用户问题真正模糊、缺少关键信息时才反问（如"帮我"、"这个"等指代不明）
            - 如果问题清晰明确，直接回答，不需要反问确认
            - 反问要具体、礼貌，比如「方便具体说说想让我帮哪一块吗？」、「你指的是哪一个选项？」
            """ :
            """
            你是圆圆，一位知性、温柔、理性的秘书型伙伴。
            
            对话方式：
            - 像一位稳重的私人秘书，而不是活泼的小伙伴，语气平和、细腻
            - 避免「首先、其次、关于XX我有几点建议」这类模板化表达，更多用自然的完整句子
            - 不卖萌、不使用大量「~」或夸张感叹号，而是用柔和、真诚的语气回应
            - 可以理解图片、音频等多模态内容，在此基础上帮助用户梳理思路和情绪
            
            重要：联网搜索能力
            - 当用户询问实时信息（天气、新闻、股价、热点话题等）时，你应该使用联网搜索功能获取最新信息
            - 不要说"我无法查看实时信息"，而是直接使用搜索功能获取答案
            - 搜索到信息后，用安静、可信赖的语气告诉用户
            
            意图识别规则：
            - 只在话题真正不清楚或指代不明时才反问（如"这个"、"那个"等）
            - 如果能理解用户想聊什么，就先简单接住情绪，再给出理性分析，不必频繁反问
            - 反问要温柔、具体，比如「你是更在意哪一部分呢？」、「可以多跟我说一点背景吗？」
            """
        
        // 构建消息列表 - 过滤掉打招呼消息
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // 过滤掉打招呼消息，避免干扰对话
        let filteredMessages = messages.filter { !$0.isGreeting }
        
        for msg in filteredMessages {
            let role = msg.role == .user ? "user" : "assistant"
            
            // 如果消息包含图片，构建多模态内容
            if !msg.images.isEmpty {
                var contentArray: [[String: Any]] = []
                
                // 只有用户输入了文字才添加，否则直接发图片
                if !msg.content.isEmpty {
                    contentArray.append([
                        "type": "text",
                        "text": msg.content
                    ])
                }
                
                // 添加图片（压缩后再编码，避免内存溢出）
                for image in msg.images {
                    // 先缩放图片到合理尺寸（最大2048px）
                    let resizedImage = resizeImage(image, maxSize: 2048)
                    
                    // 使用最高压缩质量（1.0），确保识别准确率
                    if let imageData = resizedImage.jpegData(compressionQuality: 1.0) {
                        let base64String = imageData.base64EncodedString()
                        
                        contentArray.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]
                        ])
                    }
                }
                
                apiMessages.append([
                    "role": role,
                    "content": contentArray
                ])
            } else {
                // 纯文字消息
                apiMessages.append([
                    "role": role,
                    "content": msg.content
                ])
            }
        }
        
        // Qwen-Omni必须使用流式调用
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": mode == .work ? 0.7 : 0.9,
            "max_tokens": 2000,
            "stream": true,  // 必须为true
            "modalities": ["text"],  // 只输出文本（如需语音输出可改为 ["text", "audio"]）
            "enable_search": true  // 使用简单的联网搜索参数，和 qwen-plus 一致
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        // 流式接收响应
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // 尝试读取错误信息
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line + "\n"
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody.isEmpty ? "Stream request failed" : errorBody)
        }
        
        // 收集流式响应
        var fullContent = ""
        
        for try await line in asyncBytes.lines {
            // SSE格式：data: {...}
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                // 跳过 [DONE] 标记
                if jsonString == "[DONE]" {
                    break
                }
                
                // 解析JSON
                if let jsonData = jsonString.data(using: .utf8) {
                    do {
                        let streamResponse = try JSONDecoder().decode(StreamResponse.self, from: jsonData)
                        
                        // 提取内容
                        if let delta = streamResponse.choices.first?.delta,
                           let content = delta.content {
                            fullContent += content
                        }
                    } catch {
                    }
                }
            }
        }

        guard !fullContent.isEmpty else {
            throw APIError.emptyResponse
        }
        print("[AI] \(fullContent)")
        return fullContent
    }
    
    // ===== 生成基于历史对话的打招呼 =====
    static func generateContextualGreeting(
        recentMessages: [ChatMessage],
        mode: AppMode
    ) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 系统提示词：生成打招呼
        let systemPrompt = """
        你是圆圆，一位知性、温柔、理性的秘书型伙伴。现在用户再次进入聊天室，你需要根据之前的对话历史，生成一句简短自然的打招呼（15-30字）。
        
        要求：
        - 回顾上次对话的主题或结果，用一两句话自然承接
        - 语气平和、亲切，像熟悉的秘书再次出现，而不是过度兴奋的朋友
        - 不使用「~」等撒娇语气词，少用感叹号
        - 直接输出打招呼内容，不要有"你好"、"欢迎回来"等套话开头
        
        示例：
        - 如果上次聊工作："上次那个方案有新的进展了吗？"
        - 如果上次聊心情："这两天你的状态有没有轻松一点？"
        - 如果上次聊计划："之前说的计划，有开始动起来了吗？"
        """
        
        // 构建消息列表 - 只取最近3-5条消息作为上下文
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // 只取最近的几条非打招呼消息
        let contextMessages = recentMessages
            .filter { !$0.isGreeting }
            .suffix(5)
        
        for msg in contextMessages {
            let role = msg.role == .user ? "user" : "assistant"
            apiMessages.append([
                "role": role,
                "content": msg.content
            ])
        }
        
        // 添加触发生成的消息
        apiMessages.append([
            "role": "user",
            "content": "生成一句打招呼"
        ])
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.8,
            "max_tokens": 100,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw APIError.emptyResponse
        }
        
        // 清理可能的markdown格式
        let cleanedContent = removeMarkdownFormatting(content)
        return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 辅助函数：清理markdown格式
    private static func removeMarkdownFormatting(_ text: String) -> String {
        var result = text
        
        // 移除代码块标记 ```language\ncode\n``` 或 ```code```
        result = result.replacingOccurrences(of: "```[a-zA-Z]*\\n", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "```", with: "")
        
        // 移除粗体标记 **text** 和 __text__
        result = result.replacingOccurrences(of: "\\*\\*([^\\*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        
        // 移除斜体标记 *text*（要在粗体之后处理）
        result = result.replacingOccurrences(of: "\\*([^\\*\\n]+)\\*", with: "$1", options: .regularExpression)
        
        // 移除行内代码标记 `text`
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        
        // 移除链接标记 [text](url) -> text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        
        // 移除图片标记 ![alt](url)
        result = result.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        
        // 按行处理标题、列表等需要行首匹配的格式
        let lines = result.components(separatedBy: "\n")
        let cleanedLines = lines.map { line -> String in
            var cleanedLine = line
            
            // 移除标题标记 # ## ### 等
            if let range = cleanedLine.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            
            // 移除引用标记 >
            if let range = cleanedLine.range(of: "^>\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            
            // 移除列表标记 - * +
            if let range = cleanedLine.range(of: "^[\\*\\-\\+]\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            
            // 移除有序列表标记 1. 2. 等
            if let range = cleanedLine.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            
            return cleanedLine
        }
        
        result = cleanedLines.joined(separator: "\n")
        
        return result
    }
    
    // ===== 解析图片生成待办信息 =====
    static func parseImageForTodo(image: UIImage, additionalContext: String = "") async throws -> TodoParseResult {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 获取当前时间和1小时后的时间作为示例
        let now = Date()
        let calendar = Calendar.current
        let oneHourLater = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let twoHoursLater = calendar.date(byAdding: .hour, value: 2, to: now) ?? now

        let exampleFormatter = DateFormatter()
        exampleFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        exampleFormatter.locale = Locale(identifier: "zh_CN")

        let currentTimeStr = exampleFormatter.string(from: now)
        let exampleStartTime = exampleFormatter.string(from: oneHourLater)
        let exampleEndTime = exampleFormatter.string(from: twoHoursLater)

        // 构建基础系统提示词
        var systemPrompt = """
        你是专业的OCR识别和内容提取专家。请仔细分析图片，精准提取待办事项信息。

        当前时间：\(currentTimeStr)
        """
        
        // 如果有用户补充说明，添加到提示词中
        if !additionalContext.isEmpty {
            systemPrompt += """
            
            
            用户补充说明：\(additionalContext)
            请结合这个补充说明来理解图片内容，提取更准确的待办事项。
            """
        }
        
        systemPrompt += """
        

        图片类型识别：
        1. 如果是聊天截图/对话记录：提取对话中提到的活动、计划、约定等核心事项
        2. 如果是日程表/日历：提取具体的日程安排
        3. 如果是通知/海报：提取活动名称、时间、地点等关键信息
        4. 如果是便签/备忘录：提取记录的任务内容

        提取要求：
        - title：核心事项，5-15字（如"去798艺术区逛逛"而不是"需要处理的待办事项"）
        - description：详细说明，包含地点、人物、具体安排等
        - 时间：图片中的明确时间，没有则按当前时间+1小时处理

        示例：
        聊天内容"下午去798艺术区逛逛呀？带小礼物会加分！"
        → title: "去798艺术区逛逛"
        → description: "下午去798艺术区游玩，记得带上小礼物表示诚意"

        返回JSON格式：
        {
          "title": "具体事项名称",
          "description": "详细描述",
          "startTime": "\(exampleStartTime)",
          "endTime": "\(exampleEndTime)",
          "hasTimeInfo": true/false
        }

        要求：
        - 只返回JSON，不带markdown代码块标记
        - title必须是图片中的具体内容，不能用通用词汇
        - 仔细阅读图片中的每个字，准确提取
        """
        
        // 压缩图片
        let resizedImage = resizeImage(image, maxSize: 2048)
        guard let imageData = resizedImage.jpegData(compressionQuality: 1.0) else {
            throw APIError.invalidResponse
        }
        let base64String = imageData.base64EncodedString()
        
        let contentArray: [[String: Any]] = [
            [
                "type": "text",
                "text": "请分析这张图片并提取待办事项信息"
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
            "temperature": 0.5,
            "max_tokens": 500,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("🔍 开始解析图片生成待办信息...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.emptyResponse
        }
        
        print("📥 收到AI响应: \(content)")
        
        // 清理可能的markdown代码块格式
        var cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除markdown代码块标记 ```json 和 ```
        if cleanedContent.hasPrefix("```") {
            // 移除开头的 ```json 或 ```
            if let firstNewline = cleanedContent.firstIndex(of: "\n") {
                cleanedContent = String(cleanedContent[cleanedContent.index(after: firstNewline)...])
            }
            // 移除结尾的 ```
            if cleanedContent.hasSuffix("```") {
                cleanedContent = String(cleanedContent.dropLast(3))
            }
            cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("🧹 清理后的JSON: \(cleanedContent)")
        
        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let title = result["title"] as? String,
              let description = result["description"] as? String,
              let startTimeStr = result["startTime"] as? String,
              let endTimeStr = result["endTime"] as? String else {
            print("⚠️ 无法解析AI返回的JSON，使用默认值")
            print("   原始内容: \(content)")
            print("   清理后内容: \(cleanedContent)")
            // 如果解析失败，返回默认值
            let now = Date()
            let calendar = Calendar.current
            let startTime = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
            let endTime = calendar.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
            
            return TodoParseResult(
                title: "待办事项",
                description: "从图片创建的待办事项",
                startTime: startTime,
                endTime: endTime,
                imageData: imageData
            )
        }
        
        // 解析时间字符串
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "zh_CN")
        
        guard let startTime = dateFormatter.date(from: startTimeStr),
              let endTime = dateFormatter.date(from: endTimeStr) else {
            print("⚠️ 时间格式解析失败，使用默认时间")
            let now = Date()
            let calendar = Calendar.current
            let defaultStart = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
            let defaultEnd = calendar.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart
            
            return TodoParseResult(
                title: title,
                description: description,
                startTime: defaultStart,
                endTime: defaultEnd,
                imageData: imageData
            )
        }
        
        print("✅ 解析成功: \(title)")
        print("   开始时间: \(startTimeStr)")
        print("   结束时间: \(endTimeStr)")
        
        return TodoParseResult(
            title: title,
            description: description,
            startTime: startTime,
            endTime: endTime,
            imageData: imageData
        )
    }

    // ===== 解析图片生成报销信息 =====
    static func parseImageForExpense(image: UIImage, additionalContext: String = "") async throws -> ExpenseParseResult {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        let currentTimeStr = formatter.string(from: now)

        // 构建基础系统提示词
        var systemPrompt = """
        你是专业的OCR和图片信息提取专家。请精准识别和提取报销相关信息。

        当前时间：\(currentTimeStr)
        """
        
        // 如果有用户补充说明，添加到提示词中
        if !additionalContext.isEmpty {
            systemPrompt += """
            
            
            用户补充说明：\(additionalContext)
            请结合这个补充说明来理解图片内容，提取更准确的报销信息。
            """
        }
        
        systemPrompt += """
        

        图片类型识别：
        1. 如果是发票：提取销售方名称、金额、开票日期
        2. 如果是收据/小票：提取商家名、消费金额、日期
        3. 如果是聊天截图：提取对话中提到的消费信息（如"花了50块买咖啡"）
        4. 如果是账单截图：提取商家、金额、时间

        提取规则：
        - title：商家/销售方完整名称，逐字识别，不要缩写
        - amount：准确金额（大小写互相验证）
        - category：餐饮/交通/住宿/办公/其他（根据商品类型判断）
        - occurredAt：消费时间（格式yyyy-MM-dd HH:mm:ss）

        示例：
        发票上"销售方：北京798艺术文化有限公司，金额：98.00元，日期：2025-11-11"
        → title: "北京798艺术文化有限公司"（完整准确，不能写成"798公司"）
        → amount: 98.0
        → category: "其他"

        返回JSON格式：
        {
          "title": "商家完整名称",
          "amount": 100.0,
          "category": "餐饮",
          "occurredAt": "\(currentTimeStr)"
        }

        要求：
        - 只返回JSON，不带markdown标记
        - 商家名称必须完整，逐字核对，避免错字
        - 如果是简体中文，不要自动转换成繁体
        """

        // 压缩图片
        let resizedImage = resizeImage(image, maxSize: 2048)
        guard let imageData = resizedImage.jpegData(compressionQuality: 1.0) else {
            throw APIError.invalidResponse
        }
        let base64String = imageData.base64EncodedString()
        let imageDataArray = [imageData]  // 单张图片转为数组

        let contentArray: [[String: Any]] = [
            [
                "type": "text",
                "text": "请分析这张图片并提取报销信息"
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
            "temperature": 0.3,  // 适中的temperature平衡准确性和灵活性
            "max_tokens": 500,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        print("🔍 开始解析图片生成报销信息...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.emptyResponse
        }

        print("📥 收到AI响应: \(content)")

        // 清理可能的markdown代码块格式
        var cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 移除markdown代码块标记
        if cleanedContent.hasPrefix("```") {
            if let firstNewline = cleanedContent.firstIndex(of: "\n") {
                cleanedContent = String(cleanedContent[cleanedContent.index(after: firstNewline)...])
            }
            if cleanedContent.hasSuffix("```") {
                cleanedContent = String(cleanedContent.dropLast(3))
            }
            cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("🧹 清理后的JSON: \(cleanedContent)")

        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let amount = result["amount"] as? Double,
              let title = result["title"] as? String,
              let occurredAtStr = result["occurredAt"] as? String else {
            print("⚠️ 无法解析AI返回的JSON，使用默认值")
            print("   原始内容: \(content)")
            print("   清理后内容: \(cleanedContent)")
            
            return ExpenseParseResult(
                amount: 0,
                title: "未知商家",
                category: "其他",
                occurredAt: now,
                notes: nil,
                imageData: imageDataArray
            )
        }

        let category = result["category"] as? String

        // 解析时间字符串
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "zh_CN")

        guard let occurredAt = dateFormatter.date(from: occurredAtStr) else {
            print("⚠️ 时间格式解析失败，使用当前时间")
            
            return ExpenseParseResult(
                amount: amount,
                title: title,
                category: category,
                occurredAt: now,
                notes: nil,
                imageData: imageDataArray
            )
        }

        print("✅ 解析成功: \(title) - ¥\(amount)")
        print("   类别: \(category ?? "未指定")")
        print("   发生时间: \(occurredAtStr)")

        return ExpenseParseResult(
            amount: amount,
            title: title,
            category: category,
            occurredAt: occurredAt,
            notes: nil,
            imageData: imageDataArray
        )
    }

    // ===== 解析图片生成人脉信息 =====
    static func parseImageForContact(image: UIImage, additionalContext: String = "") async throws -> ContactParseResult {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 构建基础系统提示词
        var systemPrompt = """
        你是专业的OCR和人脉信息提取专家。请精准识别和提取联系人信息。
        """
        
        // 如果有用户补充说明，添加到提示词中
        if !additionalContext.isEmpty {
            systemPrompt += """
            
            
            用户补充说明：\(additionalContext)
            请结合这个补充说明来理解图片内容，提取更准确的人脉信息。
            """
        }
        
        systemPrompt += """
        

        图片类型识别：
        1. 如果是名片：提取姓名、电话、公司、职位
        2. 如果是聊天截图：提取对话中提到的人物信息、爱好、关系等
        3. 如果是微信/社交媒体截图：提取昵称、个人介绍、兴趣爱好
        4. 如果是通讯录/联系人列表：提取姓名、电话、公司

        提取规则：
        - name：人物姓名（必填），如果是聊天记录，提取对话中提到的人名
        - phoneNumber：手机号码（11位数字）
        - company：公司全称，逐字识别
        - identity：身份/职位（如：总经理、产品经理、设计师等）
        - hobbies：兴趣爱好，从对话或介绍中提取
        - relationship：与我的关系（同事/朋友/客户/合作伙伴等）

        示例：
        名片内容"张明 产品总监 北京科技有限公司"
        → name: "张明"
        → phoneNumber: null
        → company: "北京科技有限公司"
        → identity: "产品总监"
        → hobbies: null
        → relationship: null

        返回JSON格式：
        {
          "name": "姓名",
          "phoneNumber": "手机号或null",
          "company": "公司名或null",
          "identity": "身份/职位或null",
          "hobbies": "兴趣爱好或null",
          "relationship": "关系或null"
        }

        要求：
        - 只返回JSON，不带markdown标记
        - 姓名必填，仔细从图片中提取
        - 没有的信息设为null
        - 电话号码必须是纯数字
        """

        // 压缩图片
        let resizedImage = resizeImage(image, maxSize: 2048)
        guard let imageData = resizedImage.jpegData(compressionQuality: 1.0) else {
            throw APIError.invalidResponse
        }
        let base64String = imageData.base64EncodedString()

        let contentArray: [[String: Any]] = [
            [
                "type": "text",
                "text": "请分析这张图片并提取联系人信息"
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
            "temperature": 0.5,
            "max_tokens": 500,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("🔍 开始解析图片生成人脉信息...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "HTTP Error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.invalidResponse
        }

        print("📝 AI返回的人脉信息: \(content)")

        // 清理可能的markdown代码块标记
        var cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedContent.hasPrefix("```json") {
            cleanedContent = cleanedContent.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedContent.hasPrefix("```") {
            cleanedContent = cleanedContent.replacingOccurrences(of: "```", with: "")
        }
        if cleanedContent.hasSuffix("```") {
            cleanedContent = String(cleanedContent.dropLast(3))
        }
        cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let name = result["name"] as? String else {
            print("⚠️ 无法解析AI返回的JSON，使用默认值")
            print("   原始内容: \(content)")
            print("   清理后内容: \(cleanedContent)")
            // 如果解析失败，返回默认值
            return ContactParseResult(
                name: "未命名联系人",
                phoneNumber: nil,
                company: nil,
                identity: nil,
                hobbies: nil,
                relationship: nil,
                avatarData: nil,
                imageData: imageData
            )
        }

        let phoneNumber = result["phoneNumber"] as? String
        let company = result["company"] as? String
        let identity = result["identity"] as? String
        let hobbies = result["hobbies"] as? String
        let relationship = result["relationship"] as? String

        print("✅ 解析成功: \(name)")
        if let phone = phoneNumber { print("   手机号: \(phone)") }
        if let comp = company { print("   公司: \(comp)") }
        if let iden = identity { print("   身份: \(iden)") }
        if let hob = hobbies { print("   兴趣: \(hob)") }
        if let rel = relationship { print("   关系: \(rel)") }

        return ContactParseResult(
            name: name,
            phoneNumber: phoneNumber,
            company: company,
            identity: identity,
            hobbies: hobbies,
            relationship: relationship,
            avatarData: nil,  // 暂不从图片中提取头像
            imageData: imageData
        )
    }

    // ===== 判断用户意图 =====
    static func detectUserIntent(text: String) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        你是一位专业的意图识别助手。请分析用户的文字内容，判断用户的意图。
        
        可能的意图类型：
        1. "todo" - 用户想创建待办事项（包含任务、提醒、日程、计划等）
        2. "contact" - 用户想添加/更新联系人信息（包含姓名、电话、公司等人脉信息）
        3. "expense" - 用户想记录报销/消费（包含金额、商家、消费记录等）
        4. "chat" - 普通聊天对话（询问问题、闲聊、咨询等）
        
        判断规则：
        - 如果提到"任务"、"待办"、"提醒"、"会议"、"日程"、"计划"、时间相关的事项 → todo
        - 如果提到人名、电话、公司、联系方式、认识某人 → contact
        - 如果提到金额、花费、报销、消费、买东西 → expense
        - 其他情况 → chat
        
        请只返回一个单词：todo、contact、expense 或 chat
        不要返回任何解释或其他内容。
        """
        
        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.3,
            "max_tokens": 10,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("🔍 开始判断用户意图...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.emptyResponse
        }
        
        let intent = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        print("✅ 用户意图: \(intent)")
        
        // 验证返回的意图是否有效
        if ["todo", "contact", "expense", "chat"].contains(intent) {
            return intent
        } else {
            print("⚠️ 未识别的意图，默认为chat")
            return "chat"
        }
    }
    
    // ===== 智能分析多张图片并聚合判断（新逻辑）=====
    static func analyzeMultipleImages(images: [UIImage]) async throws -> BatchParseResult {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let now = Date()
        let calendar = Calendar.current
        let oneHourLater = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let twoHoursLater = calendar.date(byAdding: .hour, value: 2, to: now) ?? now

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")

        let currentTimeStr = formatter.string(from: now)
        let exampleStartTime = formatter.string(from: oneHourLater)
        let exampleEndTime = formatter.string(from: twoHoursLater)

        let systemPrompt = """
        你是专业的多图片智能分析专家。请仔细分析所有图片，理解它们的内容和关系，然后聚合判断应该生成哪些事件。

        当前时间：\(currentTimeStr)

        核心规则：
        1. 先整体理解所有图片的内容和关联
        2. 判断这些图片是属于同一个事件的附件，还是不同的独立事件
        3. 聚合生成对应的事件

        场景示例：
        ✅ 多张图片属于同一事件（应该生成1个事件）：
           - 发票 + 行程单 → 生成1个报销，包含2张附件
             · 重要：标题必须使用发票中的"销售方"（服务商）名称，不能使用行程单的服务商
             · 金额使用发票中的金额
             · imageIndices包含两张图片的索引，如[0, 1]
           - 多张名片 → 生成1个联系人（如果是同一人）
           - 聊天截图讨论同一个活动 → 生成1个待办
           - 聊天截图讨论同一个人 → 生成1个联系人

        ✅ 多张图片属于不同事件（应该生成多个事件）：
           - 2张不同人的名片 → 生成2个联系人
           - 2个不同商家的发票 → 生成2个报销
           - 2个不同的活动通知 → 生成2个待办

        事件类型识别：
        - todo: 待办/日程
          · 聊天中约定时间、活动（如"周五晚上去798"）
          · 会议通知、活动安排
          
        - contact: 联系人/人脉
          · 名片照片
          · 聊天中讨论某人（性格、背景、兴趣爱好、联系方式）
          · 聊天中提到"认识了XX"、"介绍一下XX"等
          
        - expense: 报销/消费
          · 发票、收据、账单
          · 聊天中提到具体消费金额
          · 发票+行程单组合：必须合并为1个报销，标题使用发票的"销售方"名称，两个附件都要包含

        识别置信度判断：
        - high: 图片内容清晰明确，可以确定是某个类型（如清晰的名片、发票等）
        - medium: 图片内容模糊或需要推测（如模糊的截图、不完整的信息等）
        - low: 图片内容很不清楚，难以判断类型和内容
        
        返回JSON格式：
        {
          "confidence": "high",
          "todos": [
            {
              "title": "事项名称",
              "description": "详细描述",
              "startTime": "\(exampleStartTime)",
              "endTime": "\(exampleEndTime)",
              "imageIndices": [0]
            }
          ],
          "contacts": [
            {
              "name": "姓名",
              "phoneNumber": "手机号或null",
              "company": "公司或null",
              "identity": "身份/职位或null",
              "hobbies": "兴趣或null",
              "relationship": "关系或null",
              "imageIndices": [0]
            }
          ],
          "expenses": [
            {
              "title": "商家名称（发票+行程单时使用发票的销售方名称）",
              "amount": 100.0,
              "category": "餐饮",
              "occurredAt": "\(currentTimeStr)",
              "notes": "备注或null",
              "imageIndices": [0, 1]
            }
          ]
        }

        imageIndices说明：
        - 图片按发送顺序编号（从0开始）
        - 同一事件包含多张图片时，在imageIndices中列出所有相关图片的索引
        - 例如：发票是图0，行程单是图1 → imageIndices: [0, 1]

        要求：
        1. 只返回JSON，不带markdown标记
        2. 没有对应类型的事件时，该数组为空 []
        3. 仔细判断图片关联，合理聚合
        4. 商家名称、人名等要准确提取，不能编造
        """

        // 构建多图片内容
        var contentArray: [[String: Any]] = [
            [
                "type": "text",
                "text": "请分析这\(images.count)张图片，理解它们的内容和关系，聚合判断应该生成哪些事件"
            ]
        ]

        // 添加所有图片（索引只在 AI 返回的 imageIndices 中使用，这里无需本地使用 index）
        for image in images {
            let resizedImage = resizeImage(image, maxSize: 2048)
            guard let imageData = resizedImage.jpegData(compressionQuality: 1.0) else {
                continue
            }
            let base64String = imageData.base64EncodedString()
            
            contentArray.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]
            ])
        }

        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": contentArray]
        ]

        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.4,
            "max_tokens": 2000,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        print("🔍 开始智能分析\(images.count)张图片...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.emptyResponse
        }

        print("📥 收到AI分析结果: \(content)")

        // 清理markdown
        var cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedContent.hasPrefix("```") {
            if let firstNewline = cleanedContent.firstIndex(of: "\n") {
                cleanedContent = String(cleanedContent[cleanedContent.index(after: firstNewline)...])
            }
            if cleanedContent.hasSuffix("```") {
                cleanedContent = String(cleanedContent.dropLast(3))
            }
            cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("🧹 清理后的JSON: \(cleanedContent)")

        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("⚠️ 无法解析AI返回的JSON")
            throw APIError.emptyResponse
        }

        // 解析置信度（默认为 "high"）
        let confidence = result["confidence"] as? String ?? "high"
        print("📊 识别置信度: \(confidence)")

        // 解析待办
        var todos: [TodoParseResult] = []
        if let todosArray = result["todos"] as? [[String: Any]] {
            for todoDict in todosArray {
                guard let title = todoDict["title"] as? String,
                      let description = todoDict["description"] as? String,
                      let startTimeStr = todoDict["startTime"] as? String,
                      let endTimeStr = todoDict["endTime"] as? String,
                      let imageIndices = todoDict["imageIndices"] as? [Int] else {
                    continue
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                dateFormatter.locale = Locale(identifier: "zh_CN")
                
                guard let startTime = dateFormatter.date(from: startTimeStr),
                      let endTime = dateFormatter.date(from: endTimeStr) else {
                    continue
                }
                
                // 合并所有相关图片（待办使用第一张作为代表）
                let imageDataArray = combineImagesData(images: images, indices: imageIndices)
                let imageData = imageDataArray.first ?? Data()
                
                todos.append(TodoParseResult(
                    title: title,
                    description: description,
                    startTime: startTime,
                    endTime: endTime,
                    imageData: imageData
                ))
            }
        }

        // 解析联系人
        var contacts: [ContactParseResult] = []
        if let contactsArray = result["contacts"] as? [[String: Any]] {
            for contactDict in contactsArray {
                guard let name = contactDict["name"] as? String,
                      let imageIndices = contactDict["imageIndices"] as? [Int] else {
                    continue
                }
                
                let phoneNumber = contactDict["phoneNumber"] as? String
                let company = contactDict["company"] as? String
                let identity = contactDict["identity"] as? String
                let hobbies = contactDict["hobbies"] as? String
                let relationship = contactDict["relationship"] as? String
                
                // 合并所有相关图片（联系人使用第一张作为代表）
                let imageDataArray = combineImagesData(images: images, indices: imageIndices)
                let imageData = imageDataArray.first ?? Data()
                
                contacts.append(ContactParseResult(
                    name: name,
                    phoneNumber: phoneNumber,
                    company: company,
                    identity: identity,
                    hobbies: hobbies,
                    relationship: relationship,
                    avatarData: nil,
                    imageData: imageData
                ))
            }
        }

        // 解析报销
        var expenses: [ExpenseParseResult] = []
        if let expensesArray = result["expenses"] as? [[String: Any]] {
            for expenseDict in expensesArray {
                guard let title = expenseDict["title"] as? String,
                      let amount = expenseDict["amount"] as? Double,
                      let occurredAtStr = expenseDict["occurredAt"] as? String,
                      let imageIndices = expenseDict["imageIndices"] as? [Int] else {
                    continue
                }
                
                let category = expenseDict["category"] as? String
                let notes = expenseDict["notes"] as? String
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                dateFormatter.locale = Locale(identifier: "zh_CN")
                
                let occurredAt = dateFormatter.date(from: occurredAtStr) ?? now
                
                let imageData = combineImagesData(images: images, indices: imageIndices)
                
                expenses.append(ExpenseParseResult(
                    amount: amount,
                    title: title,
                    category: category,
                    occurredAt: occurredAt,
                    notes: notes,
                    imageData: imageData
                ))
            }
        }

        print("✅ 分析完成: \(todos.count)个待办, \(contacts.count)个联系人, \(expenses.count)个报销")

        return BatchParseResult(
            confidence: confidence,
            todos: todos,
            contacts: contacts,
            expenses: expenses
        )
    }
    
    // 辅助函数：合并多张图片的数据（返回所有图片的数据数组）
    private static func combineImagesData(images: [UIImage], indices: [Int]) -> [Data] {
        var imageDataArray: [Data] = []
        
        for index in indices {
            guard index >= 0, index < images.count else {
                continue
            }
            
            let resizedImage = resizeImage(images[index], maxSize: 2048)
            if let imageData = resizedImage.jpegData(compressionQuality: 1.0) {
                imageDataArray.append(imageData)
            }
        }
        
        return imageDataArray
    }
    
    // ===== 解析文字生成待办信息 =====
    static func parseTextForTodo(text: String) async throws -> TodoParseResult {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let now = Date()
        let calendar = Calendar.current
        let oneHourLater = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let twoHoursLater = calendar.date(byAdding: .hour, value: 2, to: now) ?? now

        let exampleFormatter = DateFormatter()
        exampleFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        exampleFormatter.locale = Locale(identifier: "zh_CN")

        let currentTimeStr = exampleFormatter.string(from: now)
        let exampleStartTime = exampleFormatter.string(from: oneHourLater)
        let exampleEndTime = exampleFormatter.string(from: twoHoursLater)

        let systemPrompt = """
        你是一位专业的待办事项助手。请分析用户的文字内容，提取出待办事项的关键信息。

        当前时间：\(currentTimeStr)

        要求：
        1. 提取事项名称（简短明确）
        2. 提取事项描述（详细内容）
        3. 提取开始时间（如果文字中有具体时间）
        4. 提取结束时间（如果文字中有具体时间）

        时间处理规则：
        - 如果文字中没有明确时间，开始时间设为当前时间1小时后，结束时间为开始时间后1小时
        - 如果只有日期没有时间，开始时间设为当天09:00，结束时间为10:00
        - 如果有具体时间，严格按照文字中的时间
        - 时间格式必须为：yyyy-MM-dd HH:mm:ss

        请以JSON格式返回，格式如下：
        {
          "title": "事项名称",
          "description": "事项详细描述",
          "startTime": "\(exampleStartTime)",
          "endTime": "\(exampleEndTime)",
          "hasTimeInfo": true/false
        }

        注意：
        - 只返回JSON，不要有任何其他文字
        - title要简短（10字以内），description可以详细
        """
        
        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.3,
            "max_tokens": 500,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("🔍 开始解析文字生成待办信息...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.emptyResponse
        }
        
        print("📥 收到AI响应: \(content)")
        
        // 清理可能的markdown代码块格式
        var cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanedContent.hasPrefix("```") {
            if let firstNewline = cleanedContent.firstIndex(of: "\n") {
                cleanedContent = String(cleanedContent[cleanedContent.index(after: firstNewline)...])
            }
            if cleanedContent.hasSuffix("```") {
                cleanedContent = String(cleanedContent.dropLast(3))
            }
            cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("🧹 清理后的JSON: \(cleanedContent)")
        
        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let title = result["title"] as? String,
              let description = result["description"] as? String,
              let startTimeStr = result["startTime"] as? String,
              let endTimeStr = result["endTime"] as? String else {
            print("⚠️ 无法解析AI返回的JSON，使用默认值")
            let now = Date()
            let calendar = Calendar.current
            let startTime = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
            let endTime = calendar.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
            
            return TodoParseResult(
                title: "待办事项",
                description: text,
                startTime: startTime,
                endTime: endTime,
                imageData: Data()
            )
        }
        
        // 解析时间字符串
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "zh_CN")
        
        guard let startTime = dateFormatter.date(from: startTimeStr),
              let endTime = dateFormatter.date(from: endTimeStr) else {
            print("⚠️ 时间格式解析失败，使用默认时间")
            let now = Date()
            let calendar = Calendar.current
            let defaultStart = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
            let defaultEnd = calendar.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart
            
            return TodoParseResult(
                title: title,
                description: description,
                startTime: defaultStart,
                endTime: defaultEnd,
                imageData: Data()
            )
        }
        
        print("✅ 解析成功: \(title)")
        
        return TodoParseResult(
            title: title,
            description: description,
            startTime: startTime,
            endTime: endTime,
            imageData: Data()
        )
    }
    
    // ===== 解析文字生成报销信息 =====
    static func parseTextForExpense(text: String) async throws -> ExpenseParseResult {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        let currentTimeStr = formatter.string(from: now)

        let systemPrompt = """
        你是专业的报销助手。分析用户的文字内容，提取报销信息。

        当前时间：\(currentTimeStr)

        识别要求：
        1. title: 商家或消费地点名称
        2. amount: 金额（如果没有明确金额，设为0）
        3. category: 类别（餐饮、交通、住宿、办公、其他）
        4. occurredAt: 发生时间（格式yyyy-MM-dd HH:mm:ss，如果没有时间信息，使用当前时间）

        返回JSON格式：
        {
          "title": "商家名称",
          "amount": 100.0,
          "category": "餐饮",
          "occurredAt": "\(currentTimeStr)",
          "notes": "备注信息或null"
        }

        注意：
        - 只返回JSON，不要其他内容
        """

        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]

        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.3,
            "max_tokens": 500,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        print("🔍 开始解析文字生成报销信息...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.emptyResponse
        }

        print("📥 收到AI响应: \(content)")

        // 清理markdown
        var cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanedContent.hasPrefix("```") {
            if let firstNewline = cleanedContent.firstIndex(of: "\n") {
                cleanedContent = String(cleanedContent[cleanedContent.index(after: firstNewline)...])
            }
            if cleanedContent.hasSuffix("```") {
                cleanedContent = String(cleanedContent.dropLast(3))
            }
            cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("🧹 清理后的JSON: \(cleanedContent)")

        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let amount = result["amount"] as? Double,
              let title = result["title"] as? String,
              let occurredAtStr = result["occurredAt"] as? String else {
            print("⚠️ 无法解析AI返回的JSON，使用默认值")
            
            return ExpenseParseResult(
                amount: 0,
                title: "报销项目",
                category: "其他",
                occurredAt: now,
                notes: text,
                imageData: []  // 文字解析没有图片，返回空数组
            )
        }

        let category = result["category"] as? String
        let notes = result["notes"] as? String

        // 解析时间字符串
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "zh_CN")

        guard let occurredAt = dateFormatter.date(from: occurredAtStr) else {
            print("⚠️ 时间格式解析失败，使用当前时间")
            
            return ExpenseParseResult(
                amount: amount,
                title: title,
                category: category,
                occurredAt: now,
                notes: notes,
                imageData: []  // 文字解析没有图片，返回空数组
            )
        }

        print("✅ 解析成功: \(title) - ¥\(amount)")

        return ExpenseParseResult(
            amount: amount,
            title: title,
            category: category,
            occurredAt: occurredAt,
            notes: notes,
            imageData: []  // 文字解析没有图片，返回空数组
        )
    }
    
    // ===== 解析文字生成人脉信息 =====
    static func parseTextForContact(text: String) async throws -> ContactParseResult {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        你是一位专业的人脉管理助手。请分析用户的文字内容，提取出联系人的关键信息。

        要求：
        1. 提取姓名（必填）
        2. 提取手机号（如果有）
        3. 提取公司/组织（如果有）
        4. 提取身份/职位（如：总经理、产品经理、设计师等，如果有）
        5. 提取兴趣爱好（如果有）
        6. 提取与我的关系（如：同事、朋友、客户等）

        请以JSON格式返回：
        {
          "name": "姓名",
          "phoneNumber": "手机号或null",
          "company": "公司名称或null",
          "identity": "身份/职位或null",
          "hobbies": "兴趣爱好或null",
          "relationship": "与我关系或null"
        }

        注意：
        - 只返回JSON，不要有任何其他文字
        - 姓名是必填项，其他都是可选的
        """

        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]

        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.3,
            "max_tokens": 500,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "HTTP Error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.invalidResponse
        }

        print("📝 AI返回的人脉信息: \(content)")

        // 清理markdown
        var cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedContent.hasPrefix("```json") {
            cleanedContent = cleanedContent.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedContent.hasPrefix("```") {
            cleanedContent = cleanedContent.replacingOccurrences(of: "```", with: "")
        }
        if cleanedContent.hasSuffix("```") {
            cleanedContent = String(cleanedContent.dropLast(3))
        }
        cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let name = result["name"] as? String else {
            print("⚠️ 无法解析AI返回的JSON，使用默认值")
            
            return ContactParseResult(
                name: "联系人",
                phoneNumber: nil,
                company: nil,
                identity: nil,
                hobbies: nil,
                relationship: nil,
                avatarData: nil,
                imageData: Data()
            )
        }

        let phoneNumber = result["phoneNumber"] as? String
        let company = result["company"] as? String
        let identity = result["identity"] as? String
        let hobbies = result["hobbies"] as? String
        let relationship = result["relationship"] as? String

        print("✅ 解析成功: \(name)")

        return ContactParseResult(
            name: name,
            phoneNumber: phoneNumber,
            company: company,
            identity: identity,
            hobbies: hobbies,
            relationship: relationship,
            avatarData: nil,
            imageData: Data()
        )
    }

    // ===== 音频转文字 =====
    static func transcribeAudio(audioURL: URL) async throws -> String {
        // 阿里云通义千问的语音识别API
        let apiURL = "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
        
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // 创建multipart/form-data请求
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // 读取音频文件数据
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw APIError.invalidResponse
        }
        
        var body = Data()
        
        // 添加model参数
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("paraformer-v2\r\n".data(using: .utf8)!)
        
        // 添加file_urls参数（使用base64编码）
        let base64Audio = audioData.base64EncodedString()
        let audioFileName = audioURL.lastPathComponent
        let audioExt = audioURL.pathExtension.lowercased()
        
        // 构建data URL
        let mimeType: String
        switch audioExt {
        case "mp3": mimeType = "audio/mpeg"
        case "wav": mimeType = "audio/wav"
        case "m4a": mimeType = "audio/mp4"
        case "aac": mimeType = "audio/aac"
        default: mimeType = "audio/mpeg"
        }
        
        let dataURL = "data:\(mimeType);base64,\(base64Audio)"
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file_urls\"\r\n\r\n".data(using: .utf8)!)
        body.append("[\"\(dataURL)\"]\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("🎤 开始音频识别...")
        print("   文件: \(audioFileName)")
        print("   大小: \(String(format: "%.1f", Double(audioData.count) / 1024.0)) KB")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("⚠️ API错误: \(errorMessage)")
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        print("📥 API响应: \(String(data: data, encoding: .utf8) ?? "")")
        
        // 通义千问ASR API返回格式
        if let output = json?["output"] as? [String: Any],
           let results = output["results"] as? [[String: Any]],
           let firstResult = results.first,
           let transcription = firstResult["transcription"] as? [String: Any],
           let text = transcription["text"] as? String {
            print("✅ 识别成功: \(text)")
            return text
        }
        
        // 如果解析失败，返回错误
        print("⚠️ 无法解析识别结果")
        throw APIError.emptyResponse
    }
    
    // ===== 使用 omni-turbo 进行音频转文字（会议录音专用）=====
    static func transcribeAudioWithOmniTurbo(audioURL: URL) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 读取音频文件并转为base64
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw APIError.invalidResponse
        }
        let base64Audio = audioData.base64EncodedString()
        
        // 确定音频格式
        let audioExt = audioURL.pathExtension.lowercased()
        let audioFormat: String
        switch audioExt {
        case "mp3": audioFormat = "mp3"
        case "wav": audioFormat = "wav"
        case "m4a": audioFormat = "m4a"
        case "aac": audioFormat = "aac"
        default: audioFormat = "wav"
        }
        
        // 系统提示词：要求转写并优化会议录音
        let systemPrompt = """
        你是一位专业的会议记录助手。请将用户提供的音频转换为文字，并进行优化处理。
        
        要求：
        1. 准确转写音频内容，保留所有重要信息
        2. 自动添加标点符号，使文本更易读
        3. 修正明显的语音识别错误
        4. 合理分段，使内容结构清晰
        5. 保持原意，不要添加或删除内容
        6. 如果是会议录音，可以适当整理发言顺序和逻辑
        
        请直接输出优化后的文本，不要添加任何说明或标记。
        """
        
        // 构建消息列表
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // 添加音频输入（使用 input_audio 格式，符合阿里云文档）
        apiMessages.append([
            "role": "user",
            "content": [
                [
                    "type": "input_audio",
                    "input_audio": [
                        "data": "data:;base64,\(base64Audio)",
                        "format": audioFormat
                    ]
                ],
                [
                    "type": "text",
                    "text": "请转写这段音频并整理成会议记录"
                ]
            ]
        ])
        
        let payload: [String: Any] = [
            "model": omniTurboModel,
            "messages": apiMessages,
            "temperature": 0.3,
            "max_tokens": 4000,
            "stream": true,  // omni-turbo 必须使用流式调用
            "modalities": ["text"]  // 只输出文本
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("🎤 开始使用 omni-turbo 转写音频...")
        print("   文件: \(audioURL.lastPathComponent)")
        print("   大小: \(String(format: "%.1f", Double(audioData.count) / 1024.0)) KB")
        print("   模型: \(omniTurboModel)")
        
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line
            }
            print("⚠️ API错误: \(errorBody)")
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // 流式接收响应
        var fullText = ""
        
        for try await line in asyncBytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                if jsonString == "[DONE]" {
                    print("✅ 转写完成，文本长度: \(fullText.count)")
                    break
                }
                
                if let jsonData = jsonString.data(using: .utf8) {
                    do {
                        let streamResponse = try JSONDecoder().decode(StreamResponse.self, from: jsonData)
                        
                        if let content = streamResponse.choices.first?.delta.content, !content.isEmpty {
                            fullText += content
                        }
                    } catch {
                        print("⚠️ 解析流式响应失败: \(error)")
                    }
                }
            }
        }
        
        guard !fullText.isEmpty else {
            throw APIError.emptyResponse
        }
        
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // ===== 语音对话（Qwen-Omni）：直接语音输入输出 =====
    static func voiceChat(
        audioURL: URL,
        messages: [ChatMessage],
        mode: AppMode,
        onTextChunk: @escaping (String) async -> Void,
        onAudioComplete: @escaping (Data) async -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        do {
            var request = URLRequest(url: URL(string: apiURL)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // 系统提示词
            let systemPrompt = mode == .work ?
                """
                你是圆圆，一位知性、温柔、理性的秘书型助理。在语音对话中，请用自然、从容的方式回应。
                
                对话方式：
                - 用日常口语表达，但保持清晰、有条理，像在办公室里和同事面对面交流
                - 避免「首先、其次」等过于书面的表达，也不要卖萌或使用大量「~」
                - 语气稳定、温和，让人感觉被支持、被照顾，而不是被哄
                """ :
                """
                你是圆圆，一位知性、温柔、理性的秘书型伙伴。在语音对话中，请用温柔但理性的方式回应。
                
                对话方式：
                - 像关系很好的秘书在旁边低声聊天，自然放松但不过度随意
                - 先简短回应情绪，再冷静地帮助梳理思路和下一步可以做什么
                - 不使用夸张语气词或撒娇语气，多用平静、真诚的语气
                """
            
            // 读取音频文件并转为base64
            guard let audioData = try? Data(contentsOf: audioURL) else {
                throw APIError.invalidResponse
            }
            let base64Audio = audioData.base64EncodedString()
            
            // 构建消息列表
            var apiMessages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt]
            ]
            
            // 添加历史消息（只取最近1条纯文字消息，避免请求体过大）
            // 语音对话场景下，不包含图片消息
            let recentMessages = messages
                .filter { !$0.isGreeting && $0.images.isEmpty && !$0.content.isEmpty }
                .suffix(1)
            
            for msg in recentMessages {
                let role = msg.role == .user ? "user" : "assistant"
                apiMessages.append(["role": role, "content": msg.content])
            }
            
            // 添加当前音频输入（使用 input_audio 格式）
            apiMessages.append([
                "role": "user",
                "content": [
                    [
                        "type": "input_audio",
                        "input_audio": [
                            "data": "data:;base64,\(base64Audio)",
                            "format": "m4a"
                        ]
                    ]
                ]
            ])
            
            let payload: [String: Any] = [
                "model": omniModel,
                "messages": apiMessages,
                "temperature": mode == .work ? 0.7 : 0.9,
                "max_tokens": 2000,
                "stream": true,
                "modalities": ["text", "audio"],  // 同时输出文字和音频
                "audio": [
                    "voice": "female",  // 女声
                    "format": "pcm"     // PCM 格式
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            // 打印请求详情（用于调试）
            let payloadSize = request.httpBody?.count ?? 0
            print("🎤 发起语音对话...")
            print("   模型: \(omniModel)")
            print("   请求体大小: \(String(format: "%.1f", Double(payloadSize) / 1024.0)) KB")
            print("   音频大小: \(String(format: "%.1f", Double(audioData.count) / 1024.0)) KB")
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                var errorBody = ""
                for try await line in asyncBytes.lines {
                    errorBody += line
                }
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            
            var fullText = ""
            var audioChunks: [String] = []
            
            // 流式接收响应
            for try await line in asyncBytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    if jsonString == "[DONE]" {
                        print("✅ 语音对话完成")
                        
                        // 合并所有音频片段并解码
                        if !audioChunks.isEmpty {
                            let fullBase64 = audioChunks.joined()
                            if let audioData = Data(base64Encoded: fullBase64) {
                                await onAudioComplete(audioData)
                            }
                        }
                        break
                    }
                    
                    if let jsonData = jsonString.data(using: .utf8) {
                        do {
                            let streamResponse = try JSONDecoder().decode(StreamResponse.self, from: jsonData)
                            
                            if let delta = streamResponse.choices.first?.delta {
                                // 接收文字内容
                                if let content = delta.content, !content.isEmpty {
                                    fullText += content
                                    await onTextChunk(content)
                                }
                                
                                // 接收音频数据
                                if let audioData = delta.audio?.data, !audioData.isEmpty {
                                    audioChunks.append(audioData)
                                }
                            }
                        } catch {
                            print("⚠️ 解析流式响应失败: \(error)")
                        }
                    }
                }
            }
            
        } catch {
            print("[语音对话错误] \(error)")
            await MainActor.run {
                onError(error)
            }
        }
    }
    
    // 辅助函数：缩放图片到指定最大尺寸
    private static func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        
        // 如果图片已经够小，直接返回
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }
        
        // 计算缩放比例
        let ratio: CGFloat
        if size.width > size.height {
            ratio = maxSize / size.width
        } else {
            ratio = maxSize / size.height
        }
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        // 使用高质量的图片上下文进行缩放
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? image
    }
}

// 待办解析结果
struct TodoParseResult {
    let title: String
    let description: String
    let startTime: Date
    let endTime: Date
    let imageData: Data
}

// 人脉解析结果
struct ContactParseResult {
    let name: String
    let phoneNumber: String?
    let company: String?
    let identity: String?
    let hobbies: String?
    let relationship: String?
    let avatarData: Data?
    let imageData: Data
}

// 报销解析结果
struct ExpenseParseResult {
    let amount: Double
    let title: String
    let category: String?
    let occurredAt: Date
    let notes: String?
    let imageData: [Data]  // 支持多张图片
}

// 批量解析结果（新增）
struct BatchParseResult {
    let confidence: String  // "high", "medium", "low"
    let todos: [TodoParseResult]
    let contacts: [ContactParseResult]
    let expenses: [ExpenseParseResult]
}

// 图片内容类型
enum ImageContentType {
    case todo       // 待办事项
    case contact    // 人脉信息
    case expense    // 报销信息
    case uncertain  // 无法确定
}

// 流式响应结构（Qwen-Omni专用）
struct StreamResponse: Codable {
    let choices: [StreamChoice]
    
    struct StreamChoice: Codable {
        let delta: StreamDelta
    }
    
    struct StreamDelta: Codable {
        let content: String?
        let audio: AudioData?
    }
    
    struct AudioData: Codable {
        let data: String?
    }
}

