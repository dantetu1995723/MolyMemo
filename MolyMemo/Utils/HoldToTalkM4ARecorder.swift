import Foundation
import AVFoundation

/// 按住说话专用：录 m4a + 提供简单音量（0~1）
@MainActor
final class HoldToTalkM4ARecorder: ObservableObject {
    enum RecorderError: Error {
        case micPermissionDenied
        case cannotCreateRecorder
        case noRecordingFile
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var audioLevel: Float = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var outputURL: URL?

    /// 录音进行中时可用于调试确认是否真的写文件
    var currentFileURL: URL? { outputURL }

    func start() async throws {
        if isRecording {
            _ = stop(deleteFile: false)
        }

        let micGranted = await requestMicPermission()
        guard micGranted else { throw RecorderError.micPermissionDenied }

        try configureAudioSessionForRecording()

        let url = try makeOutputURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 48_000
        ]

        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        r.prepareToRecord()
        guard r.record() else { throw RecorderError.cannotCreateRecorder }

        recorder = r
        outputURL = url
        isRecording = true
        audioLevel = 0

        print("[HoldToTalk] 🎙️ start m4a recording -> \(url.path)")

        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateMeter()
        }
        RunLoop.main.add(meterTimer!, forMode: .common)
    }

    /// - Returns: 录音文件 URL（若存在）
    func stop(deleteFile: Bool) -> URL? {
        meterTimer?.invalidate()
        meterTimer = nil

        if recorder?.isRecording == true {
            recorder?.stop()
        }
        recorder = nil
        isRecording = false
        audioLevel = 0

        let url = outputURL
        outputURL = nil

        // 收回 AudioSession，避免占用导致后续播放音质异常
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // ignore
        }

        if deleteFile, let url {
            try? FileManager.default.removeItem(at: url)
            print("[HoldToTalk] 🧹 deleted recording file -> \(url.lastPathComponent)")
            return nil
        }
        if let url {
            print("[HoldToTalk] 🛑 stop m4a recording -> \(url.lastPathComponent)")
        } else {
            print("[HoldToTalk] 🛑 stop m4a recording (no file url)")
        }
        return url
    }

    private func updateMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        // averagePower: [-160, 0]
        let p = recorder.averagePower(forChannel: 0)
        let normalized = pow(10, p / 20) // 0~1
        // 轻微放大，UI 更跟手
        let boosted = min(max(normalized * 3.0, 0), 1)
        audioLevel = boosted
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
        do {
            // spokenAudio：更适合语音；失败则回退 measurement
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
            try audioSession.setActive(true)
        } catch {
            throw error
        }
    }

    private func makeOutputURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HoldToTalkRecordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("hold_to_talk_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString).m4a")
    }
}


