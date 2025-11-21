import Foundation
import Speech
import AVFoundation

class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var shouldAcceptUpdates = false  // 是否接受识别回调的更新
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ 语音识别权限已授权")
                case .denied, .restricted, .notDetermined:
                    print("❌ 语音识别权限未授权")
                @unknown default:
                    break
                }
            }
        }
    }
    
    func startRecording(onTextUpdate: @escaping (String) -> Void) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ 语音识别器不可用")
            return
        }
        
        // 停止之前的任务
        stopRecording()
        
        // 配置音频会话
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 使用标准的录音配置，简单可靠
            try audioSession.setCategory(.record, mode: .default, options: .duckOthers)
            // 激活音频会话
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ 音频会话配置失败: \(error)")
            return
        }
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ 无法创建识别请求")
            return
        }
        
        // 启用实时识别结果
        recognitionRequest.shouldReportPartialResults = true
        // 添加上下文信息以提高识别准确度
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true  // 自动添加标点符号
        }
        // 使用设备端识别（如果可用），提高隐私性和速度
        if #available(iOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false  // 先尝试云端，获得更好的准确度
        }
        
        // 配置音频引擎
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 使用更大的缓冲区（4096）以获得更好的音频质量和连续性
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            shouldAcceptUpdates = true  // 开始接受更新
            print("🎤 开始录音")
        } catch {
            print("❌ 启动音频引擎失败: \(error)")
            return
        }
        
        // 开始识别
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            // 只在允许更新时处理识别结果
            if let result = result, self.shouldAcceptUpdates {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.recognizedText = text
                    onTextUpdate(text)
                }
            }
            
            if let error = error {
                // Code 301 是手动停止录音的正常错误，不需要打印
                let nsError = error as NSError
                if nsError.code == 301 || nsError.domain == "kLSRErrorDomain" && error.localizedDescription.contains("canceled") {
                    // 正常的停止录音操作，忽略
                    return
                }
                
                // 其他错误才打印并停止
                print("❌ 语音识别错误: \(error)")
                self.stopRecording()
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        shouldAcceptUpdates = false  // 立即停止接受更新，防止后续回调覆盖已识别的文字
        
        print("🛑 停止录音")
        
        // 先停止音频引擎和移除tap
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // 结束音频输入
        recognitionRequest?.endAudio()
        
        // 延迟清理识别任务
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.recognitionRequest = nil
            self?.recognitionTask?.finish()
            self?.recognitionTask = nil
        }
        
        // 重置音频会话
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    // 识别录音文件（使用苹果原始框架，整段）
    static func transcribeAudioFile(audioURL: URL) async throws -> String {
        // 请求权限
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard authStatus == .authorized else {
            throw NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }
        
        // 创建识别器
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizer", code: -2, userInfo: [NSLocalizedDescriptionKey: "语音识别器不可用"])
        }
        
        // 创建文件识别请求
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false  // 文件识别不需要部分结果
        
        // 启用标点符号（iOS 16+）
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // 执行识别
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    let nsError = error as NSError
                    // 忽略取消错误（code 301）
                    if nsError.code == 301 {
                        return
                    }
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    // 文件识别时，shouldReportPartialResults=false，所以通常只有一次回调且isFinal=true
                    if result.isFinal || !text.isEmpty {
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(returning: text)
                        }
                    }
                }
            }
        }
    }
    
    /// 分段识别录音文件，避免一次性识别过长音频导致苹果服务报错
    /// - Parameters:
    ///   - audioURL: 原始录音文件
    ///   - segmentDuration: 每段最长时长（秒），默认 5 分钟
    static func transcribeAudioFileInSegments(
        audioURL: URL,
        segmentDuration: TimeInterval = 5 * 60
    ) async throws -> String {
        let asset = AVURLAsset(url: audioURL)
        let totalSeconds = CMTimeGetSeconds(asset.duration)
        
        // 如果总时长本身不长，就按整段识别即可
        if totalSeconds.isNaN || totalSeconds <= segmentDuration {
            return try await transcribeAudioFile(audioURL: audioURL)
        }
        
        let timescale = asset.duration.timescale == 0 ? CMTimeScale(NSEC_PER_SEC) : asset.duration.timescale
        let segmentCount = Int(ceil(totalSeconds / segmentDuration))
        var allText: [String] = []
        let tempDir = FileManager.default.temporaryDirectory
        let baseName = audioURL.deletingPathExtension().lastPathComponent
        
        for index in 0..<segmentCount {
            let start = Double(index) * segmentDuration
            if start >= totalSeconds { break }
            
            let remaining = totalSeconds - start
            let currentDuration = min(segmentDuration, remaining)
            
            let startTime = CMTime(seconds: start, preferredTimescale: timescale)
            let durationTime = CMTime(seconds: currentDuration, preferredTimescale: timescale)
            let timeRange = CMTimeRange(start: startTime, duration: durationTime)
            
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                continue
            }
            
            let outputURL = tempDir.appendingPathComponent("\(baseName)_part_\(index).m4a")
            // 清理旧文件
            try? FileManager.default.removeItem(at: outputURL)
            
            exporter.outputURL = outputURL
            exporter.outputFileType = .m4a
            exporter.timeRange = timeRange
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume()
                    case .failed, .cancelled:
                        let error = exporter.error ?? NSError(domain: "SpeechRecognizer", code: -3, userInfo: [NSLocalizedDescriptionKey: "音频分段导出失败"])
                        continuation.resume(throwing: error)
                    default:
                        // 其他状态理论上不会在回调里出现，这里兜底
                        let error = NSError(domain: "SpeechRecognizer", code: -4, userInfo: [NSLocalizedDescriptionKey: "未知导出状态"])
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // 对当前片段做识别
            let text = try await transcribeAudioFile(audioURL: outputURL)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText.append(text)
            }
            
            // 清理临时文件
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let merged = allText.joined(separator: "\n")
        if merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(domain: "SpeechRecognizer", code: -5, userInfo: [NSLocalizedDescriptionKey: "分段识别结果为空"])
        }
        return merged
    }
}

