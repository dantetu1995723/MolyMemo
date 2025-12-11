import Foundation
import Speech
import AVFoundation

// 为 AVAssetExportSession 提供一个简单的包装类型，标记为 @unchecked Sendable，
// 避免直接为系统类型扩展 Sendable 带来的警告。
private final class ExportSessionBox: @unchecked Sendable {
    let exporter: AVAssetExportSession
    
    init(_ exporter: AVAssetExportSession) {
        self.exporter = exporter
    }
}

class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var audioLevel: Float = 0.0
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    // 独立音频队列，避免主线程被音频会话/引擎阻塞
    private let audioQueue = DispatchQueue(label: "com.yuanyuan.speech.audio")
    // 会话配置/激活状态，避免每次重复配置导致卡顿
    private var isSessionConfigured = false
    private var isSessionActive = false
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var shouldAcceptUpdates = false  // 是否接受识别回调的更新
    
    // 平滑处理参数
    private var smoothedLevel: Float = 0
    private let smoothingFactor: Float = 0.3  // 0~1, 越小越平滑，越大越敏感
    
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
        
        // 提前在主线程更新状态，让 UI 立即反馈
        DispatchQueue.main.async {
            self.isRecording = true
            self.shouldAcceptUpdates = true
        }
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            let audioSession = AVAudioSession.sharedInstance()
            do {
                if !self.isSessionConfigured {
                    try audioSession.setCategory(.record, mode: .default, options: .duckOthers)
                    self.isSessionConfigured = true
                }
                if !self.isSessionActive {
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    self.isSessionActive = true
                }
            } catch {
                print("❌ 音频会话配置失败: \(error)")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.shouldAcceptUpdates = false
                }
                return
            }
            
            // 创建识别请求
            self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = self.recognitionRequest else {
                print("❌ 无法创建识别请求")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.shouldAcceptUpdates = false
                }
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            if #available(iOS 16.0, *) {
                recognitionRequest.addsPunctuation = true
            }
            if #available(iOS 13.0, *) {
                recognitionRequest.requiresOnDeviceRecognition = false
            }
            
            let inputNode = self.audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                recognitionRequest.append(buffer)
                
                guard let self = self else { return }
                let level = self.calculateAudioLevel(buffer: buffer)
                DispatchQueue.main.async {
                    self.audioLevel = level
                }
            }
            
            self.audioEngine.prepare()
            
            do {
                try self.audioEngine.start()
                print("🎤 开始录音")
            } catch {
                print("❌ 启动音频引擎失败: \(error)")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.shouldAcceptUpdates = false
                }
                return
            }
            
            self.recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result, self.shouldAcceptUpdates {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.recognizedText = text
                        onTextUpdate(text)
                    }
                }
                
                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == 301 || nsError.domain == "kLSRErrorDomain" && error.localizedDescription.contains("canceled") {
                        return
                    }
                    
                    print("❌ 语音识别错误: \(error)")
                    self.stopRecording()
                }
            }
        }
    }
    
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return smoothedLevel }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return smoothedLevel }
        
        // 计算峰值和RMS的混合值
        var sum: Float = 0
        var peak: Float = 0
        
        // 全量采样以获得最精确的结果
        for i in 0..<frames {
            let sample = abs(channelData[i])
            sum += sample * sample
            if sample > peak {
                peak = sample
            }
        }
        
        let rms = sqrt(sum / Float(frames))
        
        // 混合RMS和峰值
        let rawLevel = rms * 0.6 + peak * 0.4
        
        // 提高噪声门限，过滤环境噪音（说话时一般 > 0.03）
        let gatedLevel = rawLevel < 0.025 ? 0 : rawLevel
        
        // 线性放大，不要太激进
        let amplifiedLevel = gatedLevel * 3.0
        
        // 限制在0~1范围
        let clampedLevel = min(amplifiedLevel, 1.0)
        
        // 平滑处理：上升快，下降快（让静音时快速归零）
        if clampedLevel > smoothedLevel {
            smoothedLevel = smoothedLevel + (clampedLevel - smoothedLevel) * 0.5
        } else {
            // 下降更快，让静音检测更灵敏
            smoothedLevel = smoothedLevel + (clampedLevel - smoothedLevel) * 0.4
        }
        
        return smoothedLevel
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0
            self.smoothedLevel = 0
            self.shouldAcceptUpdates = false
        }
        
        print("🛑 停止录音")
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
            }
            
            self.recognitionRequest?.endAudio()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.recognitionRequest = nil
                self?.recognitionTask?.finish()
                self?.recognitionTask = nil
            }
            
            // 保持会话活跃，避免下次重新激活导致延迟
            // 仅在 app 退出录音场景时（如后台/退出）再统一收回
        }
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
        
        // 使用新的异步属性加载 duration，兼容旧系统
        let durationTime: CMTime
        if #available(iOS 16.0, *) {
            durationTime = try await asset.load(.duration)
        } else {
            durationTime = asset.duration
        }
        
        let totalSeconds = CMTimeGetSeconds(durationTime)
        
        // 如果总时长本身不长，就按整段识别即可
        if totalSeconds.isNaN || totalSeconds <= segmentDuration {
            return try await transcribeAudioFile(audioURL: audioURL)
        }
        
        let timescale = durationTime.timescale == 0 ? CMTimeScale(NSEC_PER_SEC) : durationTime.timescale
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
            
            let outputURL = tempDir.appendingPathComponent("\(baseName)_part_\(index).m4a")
            // 清理旧文件
            try? FileManager.default.removeItem(at: outputURL)
            
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                continue
            }
            
            exporter.timeRange = timeRange
            
            if #available(iOS 18.0, *) {
                // iOS 18 及以上使用新的异步导出 API，避免废弃警告
                try await exporter.export(to: outputURL, as: .m4a)
            } else {
                exporter.outputURL = outputURL
                exporter.outputFileType = .m4a
                
                let exporterBox = ExportSessionBox(exporter)
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    exporterBox.exporter.exportAsynchronously {
                        let exporter = exporterBox.exporter
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

