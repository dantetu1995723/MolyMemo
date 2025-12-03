import Foundation
import AVFoundation

class QwenASRService {
    static let apiKey = "sk-141e3f6730b5449fb614e2888afd6c69"
    static let model = "qwen3-asr-flash-filetrans"  // 最新通义千问3 ASR模型（异步）
    static let apiURL = "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"  // ASR API
    
    // 录音文件识别 - 使用最新通义千问3 ASR（异步模式）
    static func transcribeAudio(fileURL: URL, progressHandler: ((String, Float) -> Void)? = nil) async throws -> String {
        print("🎤 [QwenASR] 开始转换录音文件（异步模式）")
        print("   文件路径: \(fileURL.path)")
        print("   文件名: \(fileURL.lastPathComponent)")
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("❌ [QwenASR] 文件不存在: \(fileURL.path)")
            throw ASRError.recordingFailed
        }
        
        // 第一步：上传音频到OSS
        progressHandler?("正在上传音频...", 0.0)
        print("☁️ [QwenASR] 步骤1: 上传音频到OSS")
        
        let ossFileURL = try await OSSUploadService.uploadAudioFile(fileURL: fileURL) { progress in
            progressHandler?("正在上传音频...", progress * 0.2)  // 上传占20%进度
        }
        
        print("✅ [QwenASR] OSS上传完成")
        print("   URL: \(ossFileURL)")
        
        // 使用 defer 确保转写完成后删除OSS文件
        defer {
            Task {
                if let objectKey = OSSUploadService.extractObjectKey(from: ossFileURL) {
                    try? await OSSUploadService.deleteFile(objectKey: objectKey)
                    print("🗑️ [QwenASR] 已删除OSS临时文件")
                }
            }
        }
        
        // 第二步：提交异步转写任务
        progressHandler?("正在提交转写任务...", 0.2)
        print("🔄 [QwenASR] 步骤2: 提交异步转写任务")
        
        let taskId = try await submitTranscriptionTask(fileURL: ossFileURL)
        print("✅ [QwenASR] 任务提交成功，task_id: \(taskId)")
        
        // 第三步：轮询任务状态
        progressHandler?("正在识别音频...", 0.3)
        print("🔄 [QwenASR] 步骤3: 等待转写完成...")
        
        let text = try await pollTaskResult(taskId: taskId, progressHandler: progressHandler)
        
        print("✅ [QwenASR] 识别成功！")
        print("   文字长度: \(text.count) 字符")
        print("   预览: \(text.prefix(100))...")
        
        progressHandler?("识别完成", 1.0)
        
        return text
    }
    
    // 提交异步转写任务（修正版：使用file_url而不是file_urls）
    private static func submitTranscriptionTask(fileURL: String) async throws -> String {
        guard let url = URL(string: apiURL) else {
            throw ASRError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")  // 启用异步模式
        
        // 构建请求体 - 根据官方文档，使用file_url（单数）
        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                "file_url": fileURL  // ✨ 注意：是file_url不是file_urls！
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("📤 [QwenASR] 提交任务到: \(apiURL)")
        print("   音频URL: \(fileURL)")
        print("   请求体: \(requestBody)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ASRError.invalidResponse
        }
        
        print("📥 [QwenASR] 提交响应状态码: \(httpResponse.statusCode)")
        
        if let responseText = String(data: data, encoding: .utf8) {
            print("📥 [QwenASR] 提交响应: \(responseText)")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ASRError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        // 获取task_id - 根据文档应该在output.task_id
        guard let output = json["output"] as? [String: Any],
              let taskId = output["task_id"] as? String else {
            print("❌ [QwenASR] 无法获取task_id")
            print("   完整响应: \(json)")
            throw ASRError.invalidResponse
        }
        
        return taskId
    }
    
    // 轮询任务结果
    private static func pollTaskResult(taskId: String, progressHandler: ((String, Float) -> Void)?) async throws -> String {
        let maxRetries = 60  // 最多轮询60次（3分钟）
        let retryInterval: UInt64 = 3_000_000_000  // 3秒
        
        for attempt in 1...maxRetries {
            print("🔄 [QwenASR] 轮询任务状态 (\(attempt)/\(maxRetries))...")
            
            // 查询任务状态
            let queryURL = "https://dashscope.aliyuncs.com/api/v1/tasks/\(taskId)"
            guard let url = URL(string: queryURL) else {
                throw ASRError.invalidResponse
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ASRError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: errorText)
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            guard let output = json["output"] as? [String: Any],
                  let taskStatus = output["task_status"] as? String else {
                throw ASRError.invalidResponse
            }
            
            print("   状态: \(taskStatus)")
            
            // 更新进度（30%-90%）
            let progress = 0.3 + Float(attempt) / Float(maxRetries) * 0.6
            progressHandler?("识别中...", progress)
            
            if taskStatus == "SUCCEEDED" {
                // 任务完成，解析结果
                print("✅ [QwenASR] 任务完成，解析结果...")
                print("   output keys: \(output.keys.joined(separator: ", "))")
                
                // 方式1: 检查result对象（新版API返回格式）
                if let result = output["result"] as? [String: Any] {
                    print("   找到result对象: \(result.keys.joined(separator: ", "))")
                    
                    // 如果有transcription_url，需要下载
                    if let transcriptionURL = result["transcription_url"] as? String {
                        print("   发现transcription_url，开始下载...")
                        return try await downloadTranscription(url: transcriptionURL)
                    }
                    
                    // 如果直接有text字段
                    if let text = result["text"] as? String, !text.isEmpty {
                        print("   从result.text获取: \(text.prefix(50))...")
                        return text
                    }
                }
                
                // 方式2: 检查results数组（旧版API返回格式）
                if let results = output["results"] as? [[String: Any]],
                   let firstResult = results.first {
                    print("   找到results数组")
                    
                    // 提取文本
                    if let transcription = firstResult["transcription"] as? [String: Any],
                       let text = transcription["text"] as? String, !text.isEmpty {
                        print("   从results[0].transcription.text获取: \(text.prefix(50))...")
                        return text
                    }
                    
                    if let text = firstResult["text"] as? String, !text.isEmpty {
                        print("   从results[0].text获取: \(text.prefix(50))...")
                        return text
                    }
                }
                
                // 方式3: 直接从output获取text
                if let text = output["text"] as? String, !text.isEmpty {
                    print("   从output.text获取: \(text.prefix(50))...")
                    return text
                }
                
                print("❌ [QwenASR] 无法从任何位置获取转写结果")
                print("   完整output: \(output)")
                throw ASRError.emptyResponse
                
            } else if taskStatus == "FAILED" {
                let errorMessage = output["message"] as? String ?? "任务失败"
                print("❌ [QwenASR] 转写任务失败: \(errorMessage)")
                throw ASRError.httpError(statusCode: 500, message: errorMessage)
            } else if taskStatus == "PENDING" || taskStatus == "RUNNING" {
                // 继续等待
                try await Task.sleep(nanoseconds: retryInterval)
                continue
            } else {
                print("⚠️ [QwenASR] 未知任务状态: \(taskStatus)")
                try await Task.sleep(nanoseconds: retryInterval)
                continue
            }
        }
        
        throw ASRError.httpError(statusCode: 408, message: "转写超时")
    }
    
    // 下载转写结果文件
    private static func downloadTranscription(url: String) async throws -> String {
        // 修复：将http改为https以满足iOS ATS要求
        var secureURL = url
        if url.hasPrefix("http://") {
            secureURL = url.replacingOccurrences(of: "http://", with: "https://")
            print("🔒 [QwenASR] 自动转换为HTTPS: \(secureURL)")
        }
        
        guard let resultURL = URL(string: secureURL) else {
            throw ASRError.invalidResponse
        }
        
        print("📥 [QwenASR] 下载转写结果: \(secureURL)")
        
        let (data, response) = try await URLSession.shared.data(from: resultURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ASRError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "下载转写结果失败")
        }
        
        print("   下载成功，大小: \(data.count) bytes")
        
        // 解析JSON结果
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        print("   JSON结构: \(json.keys.joined(separator: ", "))")
        
        // 方式1: transcripts数组（最新API格式）
        if let transcripts = json["transcripts"] as? [[String: Any]],
           let firstTranscript = transcripts.first {
            print("   找到transcripts数组")
            
            // 从transcript.text获取完整文本
            if let text = firstTranscript["text"] as? String, !text.isEmpty {
                print("   从transcripts[0].text提取: \(text.prefix(50))...")
                return text
            }
            
            // 或者从sentences拼接
            if let sentences = firstTranscript["sentences"] as? [[String: Any]] {
                let combinedText = sentences.compactMap { $0["text"] as? String }.joined()
                if !combinedText.isEmpty {
                    print("   从sentences拼接文本: \(combinedText.prefix(50))...")
                    return combinedText
                }
            }
        }
        
        // 方式2: transcription.text
        if let transcription = json["transcription"] as? [String: Any],
           let text = transcription["text"] as? String, !text.isEmpty {
            print("   从transcription.text提取: \(text.prefix(50))...")
            return text
        }
        
        // 方式3: 直接text字段
        if let text = json["text"] as? String, !text.isEmpty {
            print("   从text提取: \(text.prefix(50))...")
            return text
        }
        
        // 方式4: 如果是纯文本
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            // 如果不是JSON，可能是纯文本
            if !text.hasPrefix("{") && !text.hasPrefix("[") {
                print("   作为纯文本提取: \(text.prefix(50))...")
                return text
            }
        }
        
        print("❌ [QwenASR] 无法从下载的结果中提取文本")
        print("   JSON: \(json)")
        throw ASRError.emptyResponse
    }
    
    // 使用QwenAPI优化识别文本（添加标点、修正错字、分段）
    static func optimizeTranscription(_ text: String) async throws -> String {
        print("🔄 [QwenASR] 开始优化识别文本...")
        let optimized = try await QwenAPIService.optimizeSpeechText(text)
        print("✅ [QwenASR] 文本优化完成")
        return optimized
    }
}

// ASR错误类型
enum ASRError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyResponse
    case recordingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .httpError(let statusCode, let message):
            return "请求失败 (\(statusCode)): \(message)"
        case .emptyResponse:
            return "识别结果为空"
        case .recordingFailed:
            return "录音失败"
        }
    }
}

