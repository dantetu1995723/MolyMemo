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

    // MARK: - Main-thread publishing helpers
    // SwiftUI 要求 @Published 的变更必须在主线程发布，否则会出现紫色运行时报警。
    private func publishIsRecording(_ value: Bool) {
        if Thread.isMainThread {
            isRecording = value
        } else {
            DispatchQueue.main.sync {
                self.isRecording = value
            }
        }
    }

    private func publishAudioLevel(_ value: Float) {
        if Thread.isMainThread {
            audioLevel = value
        } else {
            DispatchQueue.main.sync {
                self.audioLevel = value
            }
        }
    }

    func start() async throws {
        if isRecording {
            _ = stop(discard: false)
        }

        let granted = await requestMicPermission()
        guard granted else { throw RecorderError.micPermissionDenied }

        try configureAudioSessionForRecording()

        pcmData = Data()
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
        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            // 1) 计算音量（用输入 buffer 更实时），回到主线程更新 UI
            let level = Self.computeLevel(buffer: buffer)
            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }

            // 2) 转成 16k/int16/mono，并把 bytes 追加到内存（追加操作放到串行队列，避免数据竞争）
            q.async { [weak self] in
                guard let self else { return }
                guard self.isRecording else { return }
                guard let converter = self.converter else { return }

                outBuffer.frameLength = 0
                var error: NSError?
                // 关键：AVAudioConverter 在一次 convert() 过程中可能会多次调用 inputBlock 拉取输入。
                // 如果我们每次都返回同一个 buffer，会导致同一段音频被“重复喂入”，听起来像回声/重影。
                // 正确做法：对“单个输入 buffer 的转换”，只提供一次输入，后续返回 endOfStream。
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
                let bytes = Data(bytes: p, count: byteCount)
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
        // 先把对外状态切回“非录音”，且必须在主线程发布（否则 SwiftUI 报警）
        publishIsRecording(false)
        publishAudioLevel(0)

        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        converter = nil

        // 收回 AudioSession
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // ignore
        }

        // 等待音频队列把尾巴收干净，避免“最后一段”丢失
        let bytes: Data = audioQueue.sync {
            let out = pcmData
            pcmData = Data()
            return out
        }

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
        // 极简“通话式”配置（接近系统电话的体验）：
        // - 必须使用 playAndRecord + voiceChat 才有系统的语音处理（AEC/NS/AGC）
        // - 不开启 defaultToSpeaker：默认走听筒（receiver），避免外放回灌造成回声
        // - 为了最大化消除回声，这里不启用蓝牙通话（allowBluetoothHFP），强制用内置麦克风+听筒
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers])

        // 强制走听筒（不是扬声器）
        try audioSession.overrideOutputAudioPort(.none)

        // 尽量固定用内置麦克风（避免蓝牙/多路由导致的“侧音/回声”体感）
        if #available(iOS 13.0, *) {
            if let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? audioSession.setPreferredInput(builtInMic)
            }
        }

        try? audioSession.setPreferredSampleRate(48_000)
        try? audioSession.setPreferredInputNumberOfChannels(1)
        try? audioSession.setPreferredIOBufferDuration(0.01)
        try audioSession.setActive(true)
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
            // 增加增益：小声更容易“起波形”，大声仍会被 clamp 到 1.0
            let gained = min(normalized * 6.8, 1.0)
            return pow(gained, 0.55)
        }
        return 0
    }
}


