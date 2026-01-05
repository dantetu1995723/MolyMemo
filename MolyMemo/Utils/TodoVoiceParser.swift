import Foundation

// 待办事项语音解析结果
struct TodoVoiceParseResult {
    var title: String?
    var taskDescription: String?
    var startTime: Date?
    var endTime: Date?
    var reminderTime: Date?
    var syncToCalendar: Bool?
}

// 待办事项语音解析服务
class TodoVoiceParser {
    enum ParserError: LocalizedError {
        case emptyResponse
        case invalidJSON
        
        var errorDescription: String? {
            switch self {
            case .emptyResponse: return "解析失败：后端返回空内容"
            case .invalidJSON: return "解析失败：未返回有效 JSON"
            }
        }
    }
    
    /// 解析语音指令，提取待办事项字段
    /// - Parameters:
    ///   - voiceText: 语音识别的文字
    ///   - existingTodo: 当前待办事项的现有数据（用于增量更新）
    /// - Returns: 解析结果，只包含需要更新的字段
    static func parseVoiceCommand(
        voiceText: String,
        existingTitle: String = "",
        existingDescription: String = "",
        existingStartTime: Date? = nil,
        existingEndTime: Date? = nil,
        existingReminderTime: Date? = nil,
        existingSyncToCalendar: Bool = true
    ) async throws -> TodoVoiceParseResult {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        let currentTimeStr = formatter.string(from: now)
        
        // 格式化现有时间信息
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.locale = Locale(identifier: "zh_CN")
        
        let existingStartStr = existingStartTime.map { dateFormatter.string(from: $0) } ?? "无"
        let existingEndStr = existingEndTime.map { dateFormatter.string(from: $0) } ?? "无"
        let existingReminderStr = existingReminderTime.map { dateFormatter.string(from: $0) } ?? "无"
        
        let instruction = """
        你是专业的待办事项助手。分析用户的语音指令，提取待办事项的各个字段。
        
        当前时间：\(currentTimeStr)
        
        现有待办信息：
        - 标题：\(existingTitle.isEmpty ? "无" : existingTitle)
        - 描述：\(existingDescription.isEmpty ? "无" : existingDescription)
        - 开始时间：\(existingStartStr)
        - 结束时间：\(existingEndStr)
        - 提醒时间：\(existingReminderStr)
        - 同步到日历：\(existingSyncToCalendar ? "是" : "否")
        
        识别规则：
        1. title：待办事项的标题/名称
        2. taskDescription：详细描述或备注
        3. startTime：开始时间（格式：yyyy-MM-dd HH:mm，相对时间如"今天下午2点"、"明天上午9点"等要转换为具体时间）
        4. endTime：结束时间（格式同上）
        5. reminderTime：提醒时间（格式同上）
        6. syncToCalendar：是否同步到日历
        
        时间解析规则：
        - "今天"、"今天下午"、"今天2点" → 转换为今天的日期和时间
        - "明天"、"明天上午"、"明天9点" → 转换为明天的日期和时间
        - "后天" → 转换为后天的日期和时间
        - "下周一"、"下周二"等 → 转换为下一个周几的日期
        - "11月13日"、"11月13日下午2点" → 转换为具体日期和时间
        - "下午2点"、"14:00" → 如果已有日期，使用该日期；否则使用今天
        - "2小时后"、"1小时后" → 从当前时间计算
        - 提醒时间支持相对时间表达：
          * "开始时间前一小时"、"开始时间前1小时" → 如果已有开始时间，计算为开始时间减去1小时；如果没有开始时间，先解析开始时间再计算
          * "开始时间前30分钟"、"开始时间前半小时" → 开始时间减去30分钟
          * "开始时间前15分钟" → 开始时间减去15分钟
          * "开始时间前两小时" → 开始时间减去2小时
          * 如果用户说"开始时间前X提醒我"，需要根据开始时间计算具体的提醒时间
        
        返回JSON格式（只返回需要更新的字段，如果某个字段没有提到，设为null）：
        {
          "title": "标题或null",
          "taskDescription": "描述或null",
          "startTime": "yyyy-MM-dd HH:mm或null",
          "endTime": "yyyy-MM-dd HH:mm或null",
          "reminderTime": "yyyy-MM-dd HH:mm或null",
          "syncToCalendar": true/false/null
        }
        
        要求：
        - 只返回JSON，不要其他内容
        - 根据现有待办信息和用户的新语音内容，智能判断需要更新的字段
        - 对于title和taskDescription：
          * **title规则**：简洁明了，提取核心事件，不包含过多细节
            - 好的示例："跟李娜去望京酒吧喝酒"、"天津到北京南"、"和小龙逛十刹海"
            - 格式：主要动作 + 关键人物/地点（如果有的话）
            - 不要在title中包含：具体时间（已有时间字段）、车次号、座位号等细节信息
            - title长度控制在20字以内
          
          * **taskDescription规则**：详细记录所有补充信息和细节
            - 包含：具体的时间描述、地点细节、人物信息、车次/航班号、座位号、注意事项、背景说明等
            - 示例输入："明天下午5:00我要跟李娜去望京酒吧喝酒，然后你明天下午2:00提醒一下我。"
              * title: "跟李娜去望京酒吧喝酒"
              * taskDescription: "明天下午5:00我要跟李娜去望京酒吧喝酒。"
            
            - 示例输入："11月8日周六，从天津前往北京南的行程，车次C2252，17:03从天津出发，17:38到达北京南。二等座，过道07车07C号。"
              * title: "天津到北京南"
              * taskDescription: "11月8日周六，车次C2252，17:03从天津出发，17:38到达北京南。二等座，过道07车07C号。"
            
            - 示例输入："今天晚上10:00去上海，出差行程。"
              * title: "去上海出差"
              * taskDescription: "今天晚上10:00去上海的出差行程。"
            
            - 示例输入："改为今天晚上10:00到达上海，出差行程，需要准备工作报告，预计明天上午开会。"
              * title: "去上海出差"
              * taskDescription: "今天晚上10:00到达上海，出差行程。需要准备工作报告，预计明天上午开会。"
          
          * **核心原则**：
            - title：简洁、核心、易读，让人快速知道是什么事
            - taskDescription：详细、完整，包含用户提供的所有具体信息
            - 用户说的时间、地点、人物等详细信息都放在taskDescription中
            - 不要担心taskDescription太长，宁可详细也不要省略信息
          
          * 对比现有内容和用户新说的内容，判断用户是想修改、替换还是追加
          * 如果用户明确说要修改/改成/改为/替换，则返回新的完整内容
          * 如果用户明确说要添加/补充/追加，则返回要添加的内容（前端会处理追加）
          * **重要**：确保title和taskDescription的内容一致，不能矛盾。如果title说"去上海"，taskDescription不能说"去北京"
        
        - 对于时间字段：将相对时间转换为具体时间字符串（格式：yyyy-MM-dd HH:mm）
          * 对于相对提醒时间（如"开始时间前一小时"），需要先确定开始时间，然后计算提醒时间
          * 如果用户说"开始时间前X提醒我"但还没有开始时间，需要先解析开始时间，再计算提醒时间
        
        - 只返回需要更新的字段，没有提到的字段设为null
        """


        let prompt = """
        \(instruction)

        用户语音：
        \(voiceText)
        """
        
        let content = try await BackendAIService.generateText(prompt: prompt, mode: .work)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParserError.emptyResponse }
        
        
        // 清理markdown代码块
        var cleanedContent = trimmed
        if cleanedContent.hasPrefix("```") {
            if let firstNewline = cleanedContent.firstIndex(of: "\n") {
                cleanedContent = String(cleanedContent[cleanedContent.index(after: firstNewline)...])
            }
            if cleanedContent.hasSuffix("```") {
                cleanedContent = String(cleanedContent.dropLast(3))
            }
            cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 提取 JSON（兼容模型偶尔加的解释文字）
        if let s = cleanedContent.range(of: "{"),
           let e = cleanedContent.range(of: "}", options: .backwards),
           s.lowerBound < e.upperBound {
            cleanedContent = String(cleanedContent[s.lowerBound..<e.upperBound])
        }
        
        // 解析JSON结果
        guard let jsonData = cleanedContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ParserError.invalidJSON
        }
        
        // 解析各个字段
        var parseResult = TodoVoiceParseResult()
        
        if let title = result["title"] as? String, !title.isEmpty {
            parseResult.title = title
        }
        
        if let taskDescription = result["taskDescription"] as? String, !taskDescription.isEmpty {
            parseResult.taskDescription = taskDescription
        }
        
        if let syncToCalendar = result["syncToCalendar"] as? Bool {
            parseResult.syncToCalendar = syncToCalendar
        }
        
        // 解析时间字段
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        timeFormatter.locale = Locale(identifier: "zh_CN")
        
        if let startTimeStr = result["startTime"] as? String, !startTimeStr.isEmpty {
            if let startTime = timeFormatter.date(from: startTimeStr) {
                parseResult.startTime = startTime
            }
        }
        
        if let endTimeStr = result["endTime"] as? String, !endTimeStr.isEmpty {
            if let endTime = timeFormatter.date(from: endTimeStr) {
                parseResult.endTime = endTime
            }
        }
        
        if let reminderTimeStr = result["reminderTime"] as? String, !reminderTimeStr.isEmpty {
            if let reminderTime = timeFormatter.date(from: reminderTimeStr) {
                parseResult.reminderTime = reminderTime
            }
        }
        
        
        return parseResult
    }
}

