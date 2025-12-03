import Foundation

// 专门用于纯文本对话的 qwen-plus 服务 - 支持联网搜索
class QwenMaxService {
    static let apiKey = "sk-141e3f6730b5449fb614e2888afd6c69"
    static let model = "qwen-plus-latest"
    static let apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    
    // 流式发送消息（纯文本对话）
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
            
            let systemPrompt = mode == .work ?
                """
                你是圆圆，一位知性、温柔、理性的秘书型助理。
                
                说话克制、有条理、有温度，不撒娇、不卖萌，也尽量不用「~」这类夸张语气词。
                回答时先给出清晰结论，再用简洁的理由和可执行建议支持结论，避免长篇堆砌和套路化表达。
                
                当用户询问实时信息或需要最新数据时，使用联网搜索获取结果，再用冷静、专业但温和的语气说明给用户。
                """ :
                """
                你是圆圆，一位知性、温柔、理性的秘书型伙伴。
                
                语气平和细腻，不矫情、不卖萌，不过度热情；先接住用户情绪，再用清晰的结构帮对方分析和整理思路。
                回答时优先给用户可以直接执行的建议，少用列表条目，更多像自然对话一样完整表达。
                
                当用户询问与现实世界、当前时间相关的问题时，使用联网搜索获取准确答案，再用温柔理性的方式转述给用户。
                """
            
            // 构建消息列表 - 只保留最近2-3轮对话（约4-6条消息）
            var apiMessages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt]
            ]

            // 过滤掉问候语，然后只取最近2-3轮对话（约4-6条消息）
            let filteredMessages = messages.filter { !$0.isGreeting }
            let recentMessages = Array(filteredMessages.suffix(6))  // 最多保留最近6条消息（约3轮对话）

            for msg in recentMessages {
                let role = msg.role == .user ? "user" : "assistant"

                // qwen-max 不支持图片，所以只发送文本内容
                // 如果消息有图片但没有文字，添加一个占位符说明
                var textContent = msg.content
                if !msg.images.isEmpty && msg.content.isEmpty {
                    textContent = "[用户发送了图片]"
                }

                apiMessages.append([
                    "role": role,
                    "content": textContent
                ])
            }
            
            let payload: [String: Any] = [
                "model": model,
                "messages": apiMessages,
                "temperature": mode == .work ? 0.7 : 0.9,
                "max_tokens": 2000,
                "stream": true,
                "enable_search": true  // qwen-plus 使用 enable_search 参数启用联网搜索
            ]

            // 调试输出
            print("\n========== 📤 qwen-plus API Request ==========")
            print("模型: \(model)")
            print("API URL: \(apiURL)")
            print("消息数量: \(apiMessages.count)")
            print("联网搜索: 已启用 (enable_search: true)")
            print("stream: true")
            print("过滤后的消息历史（共\(filteredMessages.count)条），实际发送最近\(recentMessages.count)条：")
            for (index, msg) in recentMessages.enumerated() {
                let roleStr = msg.role == .user ? "👤 User" : "🤖 Agent"
                print("[\(index)] \(roleStr): \(msg.content.prefix(50))...")
            }
            print("完整 payload:")
            if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let payloadString = String(data: payloadData, encoding: .utf8) {
                print(payloadString)
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
                print("❌ qwen-plus API 错误: \(httpResponse.statusCode)")
                print("错误详情: \(errorBody)")
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            var fullContent = ""

            print("📡 开始接收流式响应（qwen-plus）...")

            for try await line in asyncBytes.lines {
                guard !line.isEmpty, line.hasPrefix("data: ") else { continue }

                let jsonString = String(line.dropFirst(6))
                guard jsonString != "[DONE]" else {
                    print("✅ qwen-plus 流式响应结束")
                    break
                }

                guard let jsonData = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let delta = firstChoice["delta"] as? [String: Any],
                      let content = delta["content"] as? String else {
                    continue
                }

                fullContent += content
            }

            print("✅ qwen-plus 响应完成，总长度: \(fullContent.count)")
            print("📄 完整内容: \(fullContent)")
            
            // 清理 markdown 格式标记
            let cleanedContent = removeMarkdownFormatting(fullContent)
            await onComplete(cleanedContent)
            
        } catch {
            print("❌ qwen-plus API 调用失败: \(error)")
            onError(error)
        }
    }
    
    // 生成会议纪要
    static func generateMeetingSummary(transcription: String) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        你是专业的会议纪要助手，请将录音转写文字整理成简洁的会议纪要。
        
        格式要求（总分结构）：
        
        1️⃣ 开头总述（1-2句话）
        概括会议主题和核心内容
        
        2️⃣ 详细要点（用 • 列举）
        • 每个要点独立成行，简明扼要
        • 包含讨论的关键内容、决策、行动项等
        • 保持自然流畅，避免"首先、其次"等套路表达
        • 如有多个议题，可用空行分隔，但不需要额外标题
        
        3️⃣ 结尾总结（1-2句话）
        总结核心结论和后续安排
        
        示例：
        
        本次会议讨论了产品迭代方案，明确了下阶段的功能优先级和时间节点。
        
        • 产品功能优先级：用户登录优化、支付流程简化、数据看板升级
        • 技术架构需要重构底层接口，预计两周完成
        • 设计团队提出简化交互流程，减少操作步骤
        • 市场部建议增加用户反馈渠道
        • 测试周期压缩至一周，加强自动化覆盖
        
        各团队将按计划推进，每周同步进度确保按时交付。
        
        重要：
        - 不要使用 markdown 格式（**粗体**、## 标题等）
        - 直接用 • 作为列表标记
        - 保持简洁，避免冗余表达
        """
        
        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "请将以下会议录音转写文字整理成会议纪要：\n\n\(transcription)"]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 2000,
            "stream": false,
            "enable_search": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("📝 开始生成会议纪要...")
        print("   转写文字长度: \(transcription.count)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ qwen-max API 错误: \(httpResponse.statusCode)")
            print("错误详情: \(errorMessage)")
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
        
        // 清理 markdown 格式
        let cleanedContent = removeMarkdownFormatting(content)
        print("✅ 会议纪要生成完成，长度: \(cleanedContent.count)")
        
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
}

