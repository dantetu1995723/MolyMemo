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
    private let audioQueue = DispatchQueue(label: "com.molymemo.speech.audio")
    // 会话配置/激活状态，避免每次重复配置导致卡顿
    private var isSessionConfigured = false
    private var isSessionActive = false
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var shouldAcceptUpdates = false  // 是否接受识别回调的更新
    /// stop 后短暂继续接收最终结果（final），避免“松手瞬间漏字”
    private var isStopping = false
    /// 防止 stopRecording 的延迟清理误伤后续 startRecording（例如录音动画期间）
    /// - 每次 startRecording 都会递增
    /// - stopRecording 的延迟清理只对当时的 generation 生效
    private var sessionGeneration: Int = 0
    
    // 平滑处理参数
    private var smoothedLevel: Float = 0
    private let smoothingFactor: Float = 0.3  // 0~1, 越小越平滑，越大越敏感
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    break
                case .denied, .restricted, .notDetermined:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    func startRecording(onTextUpdate: @escaping (String) -> Void) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            return
        }
        
        // 停止之前的任务
        stopRecording()
        
        // 提前在主线程更新状态，让 UI 立即反馈
        DispatchQueue.main.async {
            self.isRecording = true
            self.shouldAcceptUpdates = true
            self.isStopping = false
        }
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            // 新会话：使旧 stop 的延迟清理失效
            self.sessionGeneration &+= 1
            let _ = self.sessionGeneration
            
            let audioSession = AVAudioSession.sharedInstance()
            do {
                if !self.isSessionConfigured {
                    // 使用 playAndRecord，并优先选择更适合“语音”的模式来提升识别灵敏度/稳定性；
                    // 若系统/路由不支持则回退 measurement。
                    do {
                        try audioSession.setCategory(
                            .playAndRecord,
                            mode: .spokenAudio,
                            options: [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker]
                        )
                    } catch {
                        try audioSession.setCategory(
                            .playAndRecord,
                            mode: .measurement,
                            options: [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker]
                        )
                    }
                    // 尽量让输入格式稳定（不强依赖，但能减少 route/format 抖动）
                    try? audioSession.setPreferredSampleRate(48_000)
                    try? audioSession.setPreferredInputNumberOfChannels(1)
                    try? audioSession.setPreferredIOBufferDuration(0.005)
                    self.isSessionConfigured = true
                }
                if !self.isSessionActive {
                    // notifyOthersOnDeactivation 只应在 setActive(false) 时使用；用于激活会导致底层报错/状态异常
                    try audioSession.setActive(true)
                    self.isSessionActive = true
                }

                // 尽可能提升录音灵敏度（系统允许才生效；不支持时静默跳过）
                // 1) 尝试拉高麦克风输入增益
                if audioSession.isInputGainSettable {
                    try? audioSession.setInputGain(1.0)
                }
                // 2) 若当前不是蓝牙通话麦克风，优先使用内置麦克风（频响/动态范围更好）
                if #available(iOS 13.0, *) {
                    let isBluetoothHFP = audioSession.currentRoute.inputs.contains { $0.portType == .bluetoothHFP }
                    if !isBluetoothHFP, let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                        try? audioSession.setPreferredInput(builtInMic)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.shouldAcceptUpdates = false
                }
                return
            }
            
            // 创建识别请求
            self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = self.recognitionRequest else {
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
            // 更偏“口述/语音输入”的任务提示：通常能更积极地产出可用转写
            recognitionRequest.taskHint = .dictation
            if #available(iOS 13.0, *) {
                recognitionRequest.requiresOnDeviceRecognition = false
            }
            
            let inputNode = self.audioEngine.inputNode
            let bus = 0
            
            // 防御：如果上一次未正常清理，先移除旧 tap
            inputNode.removeTap(onBus: bus)
            
            // 关键修复：
            // 某些真机路由/会话瞬间，outputFormat 可能出现 sampleRate/channelCount 无效（0），
            // 传入 installTap 会触发底层 precondition 崩溃。
            // - 优先使用 inputFormat
            // - 若格式仍不合法，则传 nil，让系统使用 tap point 的有效格式
            let inputFormat = inputNode.inputFormat(forBus: bus)
            let isValidFormat = inputFormat.sampleRate > 0 && inputFormat.channelCount > 0
            let tapFormat: AVAudioFormat? = isValidFormat ? inputFormat : nil
            
            // 更高刷新率：更跟手（512 在 48kHz 下约 10ms）
            inputNode.installTap(onBus: bus, bufferSize: 512, format: tapFormat) { [weak self] buffer, _ in
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
            } catch {
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.shouldAcceptUpdates = false
                }
                return
            }
            
            self.recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result, (self.shouldAcceptUpdates || (self.isStopping && result.isFinal)) {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.recognizedText = text
                        onTextUpdate(text)
                    }
                    // 收到 final 后即可结束 stopping 状态（防止 stop 后无限接收）
                    if result.isFinal {
                        self.isStopping = false
                    }
                }
                
                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == 301 || nsError.domain == "kLSRErrorDomain" && error.localizedDescription.contains("canceled") {
                        return
                    }
                    
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
        
        // 更灵敏的能量映射（真机小声起音也能驱动 UI）：
        // - 更低噪声底（soft gate），而不是直接归零
        // - 非线性增强低电平（让 UI “更跟手”）
        // - 上升更快、下降略快，兼顾响应与抖动
        let noiseFloor: Float = 0.012
        let normalized = max(0, rawLevel - noiseFloor) / max(0.0001, 1 - noiseFloor)
        let gained = min(normalized * 5.5, 1.0)
        let shaped = pow(gained, 0.55) // 提升小声段的可见度
        
        let attack: Float = 0.75   // 上升更快
        let release: Float = 0.50  // 下降也比较快（收音停顿能及时反馈）
        let k = shaped > smoothedLevel ? attack : release
        smoothedLevel = smoothedLevel + (shaped - smoothedLevel) * k
        
        return max(0, min(smoothedLevel, 1.0))
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0
            self.smoothedLevel = 0
            // 不要立刻关掉 shouldAcceptUpdates：final 结果可能在 endAudio 之后回调
            // 这里用 isStopping 控制只接收 final，避免 stop 后 UI 乱跳
            self.isStopping = true
        }
        
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let genAtStop = self.sessionGeneration
            let requestToStop = self.recognitionRequest
            let taskToStop = self.recognitionTask
            
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
            }
            
            self.recognitionRequest?.endAudio()
            
            // 延迟清理：只清理“这一次 stop 对应的会话”，避免误伤后续新 start（会话切换/动画期间很容易触发）
            self.audioQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                taskToStop?.finish()
                
                // 如果这 0.3s 内又 start 了新会话，这里就不要动新的 request/task
                guard self.sessionGeneration == genAtStop else { return }
                
                if self.recognitionRequest === requestToStop {
                    self.recognitionRequest = nil
                }
                if self.recognitionTask === taskToStop {
                    self.recognitionTask = nil
                }
                // 到这里彻底停止：不再接受后续回调
                DispatchQueue.main.async {
                    self.shouldAcceptUpdates = false
                    self.isStopping = false
                }
            }

            // 关键修复：停止语音识别后要收回 AudioSession，
            // 否则会长期占用 playAndRecord/measurement 导致其它播放（会议详情）音质发闷、卡顿、甚至 setCategory 报 -50。
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                self.isSessionActive = false
                self.isSessionConfigured = false
                #if DEBUG
                #endif
            } catch {
                #if DEBUG
                #endif
            }
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
        request.taskHint = .dictation
        
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

