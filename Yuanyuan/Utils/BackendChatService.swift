import Foundation
import UIKit

/// 自有后端聊天服务：
/// - `/api/v1/chat/...`：按你们示例的 `content: [...]` 格式（非流式）
/// - 其他：按 OpenAI 兼容 `chat/completions` + SSE 流式解析
final class BackendChatService {
    private init() {}
    
    static func sendMessageStream(
        messages: [ChatMessage],
        mode: AppMode,
        onComplete: @escaping (String) async -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        do {
            guard let url = BackendChatConfig.endpointURL() else {
                throw BackendChatError.invalidConfig("后端 baseURL/path 无效")
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            applyDefaultHeaders(to: &request)
            
            let token = BackendChatConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            // system prompt：尽量复用现有风格，避免切后端后“人格”漂移
            let systemPrompt = mode == .work
            ? "你是圆圆，一位知性、温柔、理性的秘书型助理。说话克制、有条理，先给清晰结论，再补充简明理由和可执行建议，不撒娇、不卖萌。"
            : "你是圆圆，一位知性、温柔、理性的秘书型伙伴。先理解并接住用户情绪，再用理性、结构化的方式分析问题和给出建议，不使用夸张语气词或撒娇说法。"
            
            // 过滤问候 + 仅发送最近几轮，控制 token
            let filtered = messages.filter { !$0.isGreeting }
            switch BackendChatConfig.requestFormat {
            case .contentV1:
                // 你贴的示例：只发送一组 content（以最新的用户输入为主）
                let lastUser = filtered.last(where: { $0.role == .user })
                let contentPayload = buildContentV1Payload(userMessage: lastUser, systemPrompt: systemPrompt)
                request.httpBody = try JSONSerialization.data(withJSONObject: contentPayload)
                
                #if DEBUG
                print("\n========== 📤 Backend Chat Request (contentV1) ==========")
                print("URL: \(url.absoluteString)")
                debugPrintHeaders(request)
                debugPrintBody(request)
                print("========================================================\n")
                #endif
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendChatError.invalidResponse
                }
                guard httpResponse.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    #if DEBUG
                    print("\n========== ❌ Backend Chat Response (contentV1) ==========")
                    print("Status: \(httpResponse.statusCode)")
                    debugPrintHTTPHeaders(httpResponse)
                    print("Body(\(body.count)):")
                    print(truncate(body, limit: 1200))
                    print("========================================================\n")
                    #endif
                    throw BackendChatError.httpError(statusCode: httpResponse.statusCode, message: body)
                }
                
                #if DEBUG
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("\n========== 📥 Backend Chat Response (contentV1) ==========")
                print("Status: \(httpResponse.statusCode)")
                debugPrintHTTPHeaders(httpResponse)
                print("Body(\(raw.count)):")
                print(truncate(raw, limit: 1200))
                debugPrintJSONKeys(data)
                print("========================================================\n")
                #endif
                
                let text = extractTextFromResponseData(data)
                let cleaned = removeMarkdownFormatting(text).trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty { throw BackendChatError.emptyResponse }
                
                #if DEBUG
                print("✅ [BackendChat] parsedText(\(cleaned.count)) preview: \(truncate(cleaned, limit: 200))")
                #endif
                await onComplete(cleaned)
                
            case .openAICompatible:
                let recentMessages = Array(filtered.suffix(6))
                
                var apiMessages: [[String: Any]] = [
                    ["role": "system", "content": systemPrompt]
                ]
                
                for msg in recentMessages {
                    let role = (msg.role == .user) ? "user" : "assistant"
                    
                    if !msg.images.isEmpty {
                        // OpenAI 兼容多模态 content: [ {type:text},{type:image_url}... ]
                        var contentArray: [[String: Any]] = []
                        if !msg.content.isEmpty {
                            contentArray.append(["type": "text", "text": msg.content])
                        }
                        
                        for image in msg.images {
                            let resized = resizeImage(image, maxSize: 2048)
                            guard let data = resized.jpegData(compressionQuality: 0.95) else { continue }
                            let base64 = data.base64EncodedString()
                            contentArray.append([
                                "type": "image_url",
                                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                            ])
                        }
                        
                        apiMessages.append(["role": role, "content": contentArray])
                    } else {
                        apiMessages.append(["role": role, "content": msg.content])
                    }
                }
                
                var payload: [String: Any] = [
                    "messages": apiMessages,
                    "stream": true
                ]
                
                let model = BackendChatConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
                if !model.isEmpty { payload["model"] = model }
                
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                #if DEBUG
                print("\n========== 📤 Backend Chat Request (OpenAI SSE) ==========")
                print("URL: \(url.absoluteString)")
                print("stream: true")
                print("messages: \(apiMessages.count)")
                if !model.isEmpty { print("model: \(model)") }
                debugPrintHeaders(request)
                debugPrintBody(request)
                print("=========================================================\n")
                #endif
                
                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendChatError.invalidResponse
                }
                
                guard httpResponse.statusCode == 200 else {
                    var errorBody = ""
                    for try await line in asyncBytes.lines { errorBody += line }
                    throw BackendChatError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
                }
                
                var fullContent = ""
                
                for try await line in asyncBytes.lines {
                    if Task.isCancelled { break }
                    guard !line.isEmpty else { continue }
                    
                    // SSE 标准：data: {...} / data: [DONE]
                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6))
                        if jsonString == "[DONE]" { break }
                        
                        if let jsonData = jsonString.data(using: .utf8),
                           let chunk = extractContentChunk(from: jsonData) {
                            fullContent += chunk
                        }
                    } else {
                        if let data = line.data(using: .utf8),
                           let chunk = extractContentChunk(from: data) {
                            fullContent += chunk
                        }
                    }
                }
                
                let cleaned = removeMarkdownFormatting(fullContent).trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty { throw BackendChatError.emptyResponse }
                
                #if DEBUG
                print("✅ [BackendChat] parsedText(\(cleaned.count)) preview: \(truncate(cleaned, limit: 200))")
                #endif
                await onComplete(cleaned)
            }
        } catch {
            await MainActor.run {
                onError(error)
            }
        }
    }
    
    // MARK: - Parsing
    
    private static func extractContentChunk(from jsonData: Data) -> String? {
        // 先走 JSONSerialization，容错高
        guard
            let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first
        else { return nil }
        
        // streaming delta
        if
            let delta = first["delta"] as? [String: Any],
            let content = delta["content"] as? String,
            !content.isEmpty
        {
            return content
        }
        
        // non-streaming message (有些后端会混用)
        if
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.isEmpty
        {
            return content
        }
        
        return nil
    }

    private static func extractTextFromResponseData(_ data: Data) -> String {
        // 尽量容错：优先从 JSON 常见字段提取，否则 fallback 到原始文本
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let content = obj["content"] as? String { return content }
            if let text = obj["text"] as? String { return text }
            if let answer = obj["answer"] as? String { return answer }
            if let dataObj = obj["data"] as? [String: Any] {
                if let content = dataObj["content"] as? String { return content }
                if let text = dataObj["text"] as? String { return text }
                if let answer = dataObj["answer"] as? String { return answer }
            }
            // 兼容 OpenAI 非流式
            if let choices = obj["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Utils
    
    private static func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxSize else { return image }
        
        let scale = maxSize / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    private static func buildContentV1Payload(userMessage: ChatMessage?, systemPrompt: String) -> [String: Any] {
        var content: [[String: Any]] = []
        
        // 按示例：text
        let text = userMessage?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            content.append([
                "type": "text",
                "text": text
            ])
        } else {
            // 如果只有图片，没有文字，也补一句占位，避免后端判空
            if let images = userMessage?.images, !images.isEmpty {
                content.append([
                    "type": "text",
                    "text": "请分析这张图片"
                ])
            }
        }
        
        // shortcut（可选）
        let shortcut = BackendChatConfig.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shortcut.isEmpty {
            content.append([
                "type": "shortcut",
                "shortcut": ["shortcut": shortcut]
            ])
        }
        
        // image_url（当前 ChatMessage 只支持图片，所以先落地图片）
        if let images = userMessage?.images, !images.isEmpty {
            for image in images {
                let resized = resizeImage(image, maxSize: 2048)
                guard let data = resized.jpegData(compressionQuality: 0.95) else { continue }
                let base64 = data.base64EncodedString()
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                ])
            }
        }
        
        // 你们示例还支持 audio/video/file；目前 App 的 ChatMessage 没有这些输入源，后续需要的话再补数据通道
        
        // 注意：示例里没有 system 字段，这里先不发 systemPrompt，避免后端不认识字段导致报错
        _ = systemPrompt
        
        return ["content": content]
    }
    
    private static func applyDefaultHeaders(to request: inout URLRequest) {
        // 这些 header 你示例里都带了：即使为空也带上，尽量兼容后端校验
        request.setValue(defaultSessionId(), forHTTPHeaderField: "X-Session-Id")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-App-Id")
        request.setValue(appVersionString(), forHTTPHeaderField: "X-App-Version")
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-OS-Type")
        request.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-OS-Version")
        
        // 地理信息：当前工程未接入定位，先留空
        request.setValue("", forHTTPHeaderField: "X-Longitude")
        request.setValue("", forHTTPHeaderField: "X-Latitude")
        request.setValue("", forHTTPHeaderField: "X-Address")
        request.setValue("", forHTTPHeaderField: "X-City")
        request.setValue("", forHTTPHeaderField: "X-Country")
    }
    
    // MARK: - Debug helpers
    
    #if DEBUG
    private static func debugPrintHeaders(_ request: URLRequest) {
        print("Headers:")
        let headers = request.allHTTPHeaderFields ?? [:]
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
            if k.lowercased() == "authorization" {
                print("  \(k): Bearer ***")
            } else {
                print("  \(k): \(v)")
            }
        }
    }
    
    private static func debugPrintBody(_ request: URLRequest) {
        guard let body = request.httpBody, !body.isEmpty else {
            print("Body: <empty>")
            return
        }
        let str = String(data: body, encoding: .utf8) ?? ""
        let redacted = redactBase64(str)
        print("Body(\(str.count)):")
        print(truncate(redacted, limit: 1200))
    }
    
    private static func debugPrintHTTPHeaders(_ response: HTTPURLResponse) {
        print("Response headers:")
        for (kAny, vAny) in response.allHeaderFields {
            let k = String(describing: kAny)
            let v = String(describing: vAny)
            print("  \(k): \(v)")
        }
    }
    
    private static func debugPrintJSONKeys(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        if let dict = obj as? [String: Any] {
            print("JSON keys: \(dict.keys.sorted())")
            if let inner = dict["data"] as? [String: Any] {
                print("JSON data.* keys: \(inner.keys.sorted())")
            }
        }
    }
    
    private static func truncate(_ s: String, limit: Int) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + " ...<truncated>"
    }
    
    private static func redactBase64(_ s: String) -> String {
        // 把 data:*;base64,xxxxx 大段替换掉，避免控制台爆炸
        // 覆盖 image/audio/video/file 常见 data uri
        let pattern = "data:[^\\s\\\"]+;base64,[A-Za-z0-9+/=]+"
        return s.replacingOccurrences(of: pattern, with: "data:*;base64,***", options: .regularExpression)
    }
    #endif
    
    private static func appVersionString() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if short.isEmpty { return build }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }
    
    private static func defaultSessionId() -> String {
        let key = "backend_chat_session_id"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    
    /// 复用 QwenMaxService 的清理逻辑（保持输出一致），这里做最小实现以免跨文件依赖
    private static func removeMarkdownFormatting(_ text: String) -> String {
        var result = text
        
        result = result.replacingOccurrences(of: "```[a-zA-Z]*\\n", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "```", with: "")
        result = result.replacingOccurrences(of: "\\*\\*([^\\*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*([^\\*\\n]+)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        
        let lines = result.components(separatedBy: "\n")
        let cleanedLines = lines.map { line -> String in
            var cleanedLine = line
            if let range = cleanedLine.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            if let range = cleanedLine.range(of: "^>\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            if let range = cleanedLine.range(of: "^[\\*\\-\\+]\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            if let range = cleanedLine.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                cleanedLine.removeSubrange(range)
            }
            return cleanedLine
        }
        
        return cleanedLines.joined(separator: "\n")
    }
}

enum BackendChatError: LocalizedError {
    case invalidConfig(String)
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidConfig(let msg):
            return "后端配置有误：\(msg)"
        case .invalidResponse:
            return "服务器响应无效"
        case .httpError(let statusCode, let message):
            return "请求失败 (\(statusCode)): \(message)"
        case .emptyResponse:
            return "服务器返回空内容"
        }
    }
}


