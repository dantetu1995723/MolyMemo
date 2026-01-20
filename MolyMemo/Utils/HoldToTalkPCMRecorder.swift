import Foundation
@preconcurrency import AVFoundation

/// 按住说话：直接采集麦克风 PCM（统一输出 16k/16bit/mono 的 Int16 PCM bytes）
final class HoldToTalkPCMRecorder: ObservableObject {
    enum RecorderError: LocalizedError {
        case micPermissionDenied
        case cannotCreateConverter
        case engineStartFailed

        var errorDescription: String? {
            switch self {
            case .micPermissionDenied: return "麦克风权限未授权"
            case .cannotCreateConverter: return "无法创建音频转换器"
            case .engineStartFailed: return "音频引擎启动失败"
            }
        }
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var audioLevel: Float = 0

    private let audioQueue = DispatchQueue(label: "com.molymemo.holdtotalk.pcm")
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    // 仅在 audioQueue 内读写，避免与音频 tap 线程抢数据
    private var pcmData = Data()
    private var bytesPerFrame: Int = 2 // int16 mono
    /// 仅在 audioQueue 访问：用于决定是否接受/处理 tap 的音频数据。
    /// 不能用 @Published 的 isRecording 做跨线程判定，否则 stop() 先置 false 会导致"尾巴"被丢。
    private var captureActive: Bool = false

    // 轻量自动增益（AGC）：让小声说话更容易被后端识别
    // - 仅在 audioQueue 访问
    private var agcGain: Float = 1.0
    private let agcMaxGain: Float = 6.0
    private let agcSmoothing: Float = 0.15 // 越大越"敏感"，越小越稳定

    // AudioSession 退场延迟：避免"刚松手就立刻第二段录音"时重复 setActive(true/false) 导致卡顿/音浪慢半拍
    private var pendingDeactivateWorkItem: DispatchWorkItem?
    private let sessionDeactivateDelay: TimeInterval = 0.6
    
    // 预热状态：减少首次录音的启动延迟
    private var isSessionWarmedUp: Bool = false
    private var lastSessionConfigTime: Date?

    // MARK: - Main-thread publishing helpers
    // SwiftUI 要求 @Published 的变更必须在主线程发布，否则会出现紫色运行时报警。
    private func publishIsRecording(_ value: Bool) {
        if Thread.isMainThread {
            isRecording = value
        } else {
            // 关键：不要用 main.sync 阻塞音频采集启动（主线程可能在滚动/动画中很忙）
            DispatchQueue.main.async { [weak self] in
                self?.isRecording = value
            }
        }
    }

    private func publishAudioLevel(_ value: Float) {
        if Thread.isMainThread {
            audioLevel = value
        } else {
            // 同上：避免阻塞音频线程
            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = value
            }
        }
    }

    func start() async throws {
        if isRecording {
            _ = stop(discard: false)
        }

        // 若刚 stop 过：取消 AudioSession 延迟退场，保证二次录音立刻起
        if let item = pendingDeactivateWorkItem {
            item.cancel()
            pendingDeactivateWorkItem = nil
        }

        let granted = await requestMicPermission()
        guard granted else { throw RecorderError.micPermissionDenied }

        try configureAudioSessionForRecording()

        // 在音频队列里切到"接收数据"态，避免与 tap 的异步写入竞争
        audioQueue.sync {
            pcmData = Data()
            captureActive = true
            agcGain = 1.0
        }
        // @Published 更新回到主线程，避免 SwiftUI 报警
        publishAudioLevel(0)

        let inputNode = engine.inputNode
        let bus = 0
        inputNode.removeTap(onBus: bus)

        let inFormat = inputNode.inputFormat(forBus: bus)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false) else {
            throw RecorderError.cannotCreateConverter
        }
        guard let conv = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw RecorderError.cannotCreateConverter
        }
        converter = conv
        bytesPerFrame = MemoryLayout<Int16>.size // mono

        let outFrameCapacity: AVAudioFrameCount = 2048
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrameCapacity) else {
            throw RecorderError.cannotCreateConverter
        }

        publishIsRecording(true)
        print("[HoldToTalk] 🎙️ start PCM engine capture (in=\(inFormat.sampleRate)Hz ch=\(inFormat.channelCount))")

        // 捕获必要对象，避免在 @Sendable 闭包里直接触碰 main-actor 状态
        let q = audioQueue
        // 使用更小的 bufferSize（512 而非 1024）以获得更快的回调频率，减少延迟
        inputNode.installTap(onBus: bus, bufferSize: 512, format: inFormat) { [weak self] buffer, _ in
            // 1) 计算音量（用输入 buffer 更实时），回到主线程更新 UI
            let level = Self.computeLevel(buffer: buffer)
            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }

            // 2) 转成 16k/int16/mono，并把 bytes 追加到内存（追加操作放到串行队列，避免数据竞争）
            q.async { [weak self] in
                guard let self else { return }
                guard self.captureActive else { return }
                guard let converter = self.converter else { return }

                outBuffer.frameLength = 0
                var error: NSError?
                // 关键：AVAudioConverter 在一次 convert() 过程中可能会多次调用 inputBlock 拉取输入。
                // 如果我们每次都返回同一个 buffer，会导致同一段音频被"重复喂入"，听起来像回声/重影。
                // 正确做法：对"单个输入 buffer 的转换"，只提供一次输入，后续返回 endOfStream。
                var didProvideInput = false
                converter.reset() // 避免跨 buffer 的内部状态残留（更确定的单段转换）
                let status = converter.convert(to: outBuffer, error: &error) { _, outStatus -> AVAudioBuffer? in
                    if didProvideInput {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    didProvideInput = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                if let error {
                    print("[HoldToTalk] ❌ PCM convert error -> \(error.domain)(\(error.code)) \(error.localizedDescription)")
                    return
                }
                guard status == .haveData, outBuffer.frameLength > 0 else { return }
                guard let p = outBuffer.int16ChannelData?[0] else { return }
                let byteCount = Int(outBuffer.frameLength) * self.bytesPerFrame
                let frames = Int(outBuffer.frameLength)
                let bytes = self.applyAutoGainIfNeeded(samples: p, frames: frames)
                self.pcmData.append(bytes)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            publishIsRecording(false)
            throw RecorderError.engineStartFailed
        }
    }

    /// - Returns: 16k/16bit/mono PCM bytes（Int16 little-endian）
    func stop(discard: Bool) -> Data {
        let wasRecording = isRecording
        // 先把对外状态切回"非录音"（UI 需要立刻恢复），但不要影响音频队列里"尾巴"处理。
        publishIsRecording(false)
        publishAudioLevel(0)

        // 先停引擎/移除 tap：阻止新 buffer 进入队列
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)

        // 等待音频队列把已经排队的转换任务跑完，再一次性收口数据。
        // 这一步是"松手尾部不吞字"的关键。
        let bytes: Data = audioQueue.sync {
            captureActive = false
            let out = pcmData
            pcmData = Data()
            return out
        }

        // 转换器不再需要（放到队列 drain 之后再清空，避免 queued task 读到 nil）
        converter = nil

        // AudioSession 延迟退场：如果用户马上开始下一段录音，就避免频繁 setActive(true/false)
        pendingDeactivateWorkItem?.cancel()
        let item = DispatchWorkItem {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                // ignore
            }
        }
        pendingDeactivateWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionDeactivateDelay, execute: item)

        if wasRecording {
            if discard {
                print("[HoldToTalk] 🛑 stop PCM capture (discard)")
            } else {
                print("[HoldToTalk] 🛑 stop PCM capture bytes=\(bytes.count)")
            }
        }

        return discard ? Data() : bytes
    }

    /// 录音过程中取出当前已缓存的 PCM bytes，并清空内部缓存（用于流式发送）。
    /// - Returns: 16k/16bit/mono PCM bytes（Int16 little-endian）
    func drainPCMBytes() -> Data {
        audioQueue.sync {
            let out = pcmData
            pcmData = Data()
            return out
        }
    }

    // MARK: - Helpers

    /// 把 Int16 PCM 做轻量自动增益并限幅，提升小声说话的可识别性。
    /// - Important: 仅在 audioQueue 调用
    private func applyAutoGainIfNeeded(samples: UnsafePointer<Int16>, frames: Int) -> Data {
        guard frames > 0 else { return Data() }

        var peak: Int32 = 0
        for i in 0..<frames {
            let v = Int32(samples[i])
            let a = v >= 0 ? v : -v
            if a > peak { peak = a }
        }

        // 近似静音：不做增益，避免把底噪放大
        if peak < 200 {
            return Data(bytes: samples, count: frames * bytesPerFrame)
        }

        // 基于峰值的分段增益：简单、稳定、CPU 低
        let desired: Float = {
            if peak < 1_000 { return 6.0 }
            if peak < 2_000 { return 4.0 }
            if peak < 4_000 { return 3.0 }
            if peak < 8_000 { return 2.0 }
            if peak < 12_000 { return 1.6 }
            return 1.0
        }()

        let clippedDesired = min(max(desired, 1.0), agcMaxGain)
        agcGain = agcGain * (1 - agcSmoothing) + clippedDesired * agcSmoothing

        let gain = agcGain
        var out = Data(count: frames * bytesPerFrame)
        out.withUnsafeMutableBytes { rawBuf in
            guard let dst = rawBuf.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<frames {
                let v = Float(samples[i]) * gain
                let clamped = max(-32768.0, min(32767.0, v))
                dst[i] = Int16(clamped)
            }
        }
        return out
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func configureAudioSessionForRecording() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        // 检查是否需要完整配置：如果最近刚配置过且 session 仍处于预期状态，跳过耗时的 setCategory
        let needsFullConfig: Bool = {
            // 首次或超过 2 秒未配置：需要完整配置
            guard isSessionWarmedUp,
                  let lastTime = lastSessionConfigTime,
                  Date().timeIntervalSince(lastTime) < 2.0 else {
                return true
            }
            // 检查当前状态是否已经是我们需要的
            let currentCategory = audioSession.category
            let currentMode = audioSession.mode
            return currentCategory != .playAndRecord || currentMode != .voiceChat
        }()
        
        if needsFullConfig {
            // 极简"通话式"配置（接近系统电话的体验）：
            // - 必须使用 playAndRecord + voiceChat 才有系统的语音处理（AEC/NS/AGC）
            // - 不开启 defaultToSpeaker：默认走听筒（receiver），避免外放回灌造成回声
            // - 为了最大化消除回声，这里不启用蓝牙通话（allowBluetoothHFP），强制用内置麦克风+听筒
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers])

            // 强制走听筒（不是扬声器）
            try audioSession.overrideOutputAudioPort(.none)

            // 尽量固定用内置麦克风（避免蓝牙/多路由导致的"侧音/回声"体感）
            if #available(iOS 13.0, *) {
                if let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try? audioSession.setPreferredInput(builtInMic)
                }
            }

            try? audioSession.setPreferredSampleRate(48_000)
            try? audioSession.setPreferredInputNumberOfChannels(1)
        }
        
        // IO Buffer Duration 设置更小以减少延迟（5ms vs 10ms）
        // 注意：太小可能导致某些设备 CPU 压力增大，5ms 是比较好的平衡点
        try? audioSession.setPreferredIOBufferDuration(0.005)
        try audioSession.setActive(true)
        
        isSessionWarmedUp = true
        lastSessionConfigTime = Date()
    }
    
    /// 预热 AudioSession：在进入聊天界面时调用，减少首次录音的启动延迟
    func warmUpSession() {
        // 如果已经预热过且时间不长，跳过
        if isSessionWarmedUp, let lastTime = lastSessionConfigTime, Date().timeIntervalSince(lastTime) < 5.0 {
            return
        }
        
        Task.detached(priority: .background) {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                // 只做 category 配置，不做 setActive（避免影响其他音频）
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers])
                try? audioSession.setPreferredSampleRate(48_000)
                try? audioSession.setPreferredInputNumberOfChannels(1)
                try? audioSession.setPreferredIOBufferDuration(0.005)
                await MainActor.run {
                    self.isSessionWarmedUp = true
                    self.lastSessionConfigTime = Date()
                }
                print("[HoldToTalk] AudioSession warmed up")
            } catch {
                // ignore
            }
        }
    }

    private static func computeLevel(buffer: AVAudioPCMBuffer) -> Float {
        // 优先 floatChannelData；没有就退化
        if let ch = buffer.floatChannelData?[0] {
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return 0 }
            var sum: Float = 0
            var peak: Float = 0
            for i in 0..<frames {
                let s = abs(ch[i])
                sum += s * s
                peak = max(peak, s)
            }
            let rms = sqrt(sum / Float(frames))
            let raw = rms * 0.6 + peak * 0.4
            // 放宽小声门限：让更小声也能驱动 UI（不影响实际 PCM 数据）
            let noiseFloor: Float = 0.008
            let normalized = max(0, raw - noiseFloor) / max(0.0001, 1 - noiseFloor)
            // 增加增益：小声更容易"起波形"，大声仍会被 clamp 到 1.0
            let gained = min(normalized * 6.8, 1.0)
            return pow(gained, 0.55)
        }
        return 0
    }
}
