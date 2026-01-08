import Foundation
@preconcurrency import AVFoundation

/// 按住说话：直接采集麦克风 PCM（统一输出 16k/16bit/mono 的 Int16 PCM bytes）
@MainActor
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

    private var pcmData = Data()
    private var bytesPerFrame: Int = 2 // int16 mono

    func start() async throws {
        if isRecording {
            _ = stop(discard: false)
        }

        let granted = await requestMicPermission()
        guard granted else { throw RecorderError.micPermissionDenied }

        try configureAudioSessionForRecording()

        pcmData = Data()
        audioLevel = 0

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

        isRecording = true
        print("[HoldToTalk] 🎙️ start PCM engine capture (in=\(inFormat.sampleRate)Hz ch=\(inFormat.channelCount))")

        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // 计算音量（用输入 buffer 更实时）
            let level = Self.computeLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }

            // 转成 16k/int16/mono 并 append 到内存
            self.audioQueue.async { [weak self] in
                guard let self else { return }
                guard self.isRecording else { return }
                guard let converter = self.converter else { return }

                outBuffer.frameLength = 0
                var error: NSError?
                let status = converter.convert(to: outBuffer, error: &error) { _, outStatus -> AVAudioBuffer? in
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
                self.pcmData.append(Data(bytes: p, count: byteCount))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            isRecording = false
            throw RecorderError.engineStartFailed
        }
    }

    /// - Returns: 16k/16bit/mono PCM bytes（Int16 little-endian）
    func stop(discard: Bool) -> Data {
        let wasRecording = isRecording
        isRecording = false
        audioLevel = 0

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

        let bytes = pcmData
        pcmData = Data()

        if wasRecording {
            if discard {
                print("[HoldToTalk] 🛑 stop PCM capture (discard)")
            } else {
                print("[HoldToTalk] 🛑 stop PCM capture bytes=\(bytes.count)")
            }
        }

        return discard ? Data() : bytes
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
        do {
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
            try? audioSession.setPreferredSampleRate(48_000)
            try? audioSession.setPreferredInputNumberOfChannels(1)
            try? audioSession.setPreferredIOBufferDuration(0.01)
            try audioSession.setActive(true)
        } catch {
            throw error
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
            let noiseFloor: Float = 0.012
            let normalized = max(0, raw - noiseFloor) / max(0.0001, 1 - noiseFloor)
            let gained = min(normalized * 5.5, 1.0)
            return pow(gained, 0.55)
        }
        return 0
    }
}


