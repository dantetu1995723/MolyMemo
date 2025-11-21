import Foundation
import AVFoundation
import Speech
import ActivityKit
import SwiftData
import UIKit

// 实时录音管理器 - 同时录音和实时转写
class LiveRecordingManager: ObservableObject {
    static let shared = LiveRecordingManager()
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recognizedText = ""
    @Published var recordingDuration: TimeInterval = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var audioURL: URL?
    
    // Speech 识别器
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Live Activity
    private var activity: Activity<MeetingRecordingAttributes>?
    
    // 保存 ModelContext 的回调
    var modelContextProvider: (() -> ModelContext?)?
    
    private init() {
        // 监听app状态变化，确保后台录音正常
        setupBackgroundHandling()
    }
    
    // 开始录音
    func startRecording() {
        print("🎤 准备开始录音...")
        
        // 请求权限
        requestPermissions { [weak self] granted in
            guard granted else {
                print("❌ 权限被拒绝")
                return
            }
            
            self?.setupRecording()
        }
    }
    
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        // 请求麦克风权限
        AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
            guard micGranted else {
                completion(false)
                return
            }
            
            // 请求语音识别权限
            SFSpeechRecognizer.requestAuthorization { authStatus in
                DispatchQueue.main.async {
                    completion(authStatus == .authorized)
                }
            }
        }
    }
    
    private func setupRecording() {
        // 配置音频会话 - 支持后台录音
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("❌ 音频会话配置失败: \(error)")
            return
        }
        
        // 准备录音文件（统一存放在 MeetingRecordings 文件夹）
        let recordingsFolder = ensureRecordingsFolder()
        audioURL = recordingsFolder.appendingPathComponent("meeting_\(Int(Date().timeIntervalSince1970)).wav")
        
        guard let audioURL = audioURL else { return }
        
        // 配置录音设置（WAV 格式，便于后续处理）
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            // 创建录音器
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            
            // 重置状态
            isRecording = true
            recognizedText = ""
            recordingDuration = 0
            
            // 启动计时器 - 使用 common 模式确保后台继续运行
            recordingTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.recordingDuration += 0.5
                self.updateLiveActivity()
            }
            RunLoop.current.add(recordingTimer!, forMode: .common)
            
            // 启动实时语音识别
            startSpeechRecognition()
            
            // 启动 Live Activity
            startLiveActivity()
            
            print("✅ 录音已启动: \(audioURL.lastPathComponent)")
        } catch {
            print("❌ 录音启动失败: \(error)")
        }
    }
    
    // 启动实时语音识别
    private func startSpeechRecognition() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ 语音识别器不可用")
            return
        }
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ 无法创建识别请求")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
        }
        
        // 配置音频引擎
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            print("✅ 音频引擎已启动")
        } catch {
            print("❌ 启动音频引擎失败: \(error)")
            return
        }
        
        // 开始识别
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.recognizedText = text
                    self.updateLiveActivity()
                }
            }
            
            if let error = error {
                let nsError = error as NSError
                if nsError.code != 301 {  // 忽略取消错误
                    print("❌ 语音识别错误: \(error)")
                }
            }
        }
    }
    
    // 暂停录音
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        
        print("⏸️ 暂停录音...")
        isPaused = true
        
        // 暂停录音器
        audioRecorder?.pause()
        recordingTimer?.invalidate()
        
        // 暂停音频引擎
        audioEngine.pause()
        
        // 更新 Live Activity
        updateLiveActivity()
        
        print("✅ 录音已暂停")
    }
    
    // 继续录音
    func resumeRecording() {
        guard isRecording && isPaused else { return }
        
        print("▶️ 继续录音...")
        isPaused = false
        
        // 继续录音器
        audioRecorder?.record()
        
        // 重新启动计时器 - 使用 common 模式确保后台继续运行
        recordingTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingDuration += 0.5
            self.updateLiveActivity()
        }
        RunLoop.current.add(recordingTimer!, forMode: .common)
        
        // 继续音频引擎
        do {
            try audioEngine.start()
        } catch {
            print("❌ 继续音频引擎失败: \(error)")
        }
        
        // 更新 Live Activity
        updateLiveActivity()
        
        print("✅ 录音已继续")
    }
    
    // 停止录音
    func stopRecording(modelContext: ModelContext? = nil) {
        print("🛑 停止录音...")
        
        guard isRecording else { return }
        
        isRecording = false
        isPaused = false
        
        // 停止录音器
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        
        // 停止音频引擎
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // 保存到会议纪要（尝试从参数或回调获取 ModelContext）
        let context = modelContext ?? modelContextProvider?()
        saveToMeeting(modelContext: context)
        
        // 结束 Live Activity
        endLiveActivity()
        
        print("✅ 录音已停止")
    }
    
    // 保存到会议纪要
    private func saveToMeeting(modelContext: ModelContext?) {
        guard let audioURL = audioURL,
              let modelContext = modelContext else {
            print("❌ 无法保存会议纪要")
            return
        }
        
        let meeting = Meeting(
            title: "会议录音 - \(formatDate(Date()))",
            content: recognizedText,
            audioFilePath: audioURL.path,
            createdAt: Date(),
            duration: recordingDuration
        )
        
        modelContext.insert(meeting)
        
        do {
            try modelContext.save()
            print("✅ 会议纪要已保存")
        } catch {
            print("❌ 保存失败: \(error)")
        }
    }
    
    // MARK: - Live Activity 管理
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activity 未启用")
            return
        }
        
        let attributes = MeetingRecordingAttributes(meetingTitle: "会议录音")
        let contentState = MeetingRecordingAttributes.ContentState(
            transcribedText: "开始录音...",
            duration: 0,
            isRecording: true,
            isPaused: false
        )
        
        do {
            // 创建 ActivityContent，设置高优先级保持展开状态
            let activityContent = ActivityContent(
                state: contentState,
                staleDate: nil,
                relevanceScore: 100.0  // 最高优先级，保持展开状态
            )
            
            activity = try Activity<MeetingRecordingAttributes>.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
            print("✅ Live Activity 已启动（展开模式）")
        } catch {
            print("❌ Live Activity 启动失败: \(error)")
        }
    }
    
    private func updateLiveActivity() {
        guard let activity = activity else { return }
        
        let contentState = MeetingRecordingAttributes.ContentState(
            transcribedText: recognizedText.isEmpty ? "等待说话..." : recognizedText,
            duration: recordingDuration,
            isRecording: isRecording,
            isPaused: isPaused
        )
        
        Task { @MainActor in
            // 创建 ActivityContent，设置高优先级保持展开状态
            let activityContent = ActivityContent(
                state: contentState,
                staleDate: nil,
                relevanceScore: 100.0  // 保持最高优先级
            )
            await activity.update(activityContent)
        }
    }
    
    private func endLiveActivity() {
        guard let activity = activity else { return }
        
        let finalState = MeetingRecordingAttributes.ContentState(
            transcribedText: recognizedText,
            duration: recordingDuration,
            isRecording: false,
            isPaused: false
        )
        
        Task {
            await activity.end(using: finalState, dismissalPolicy: .after(.now + 3))
            print("✅ Live Activity 已结束")
        }
        
        self.activity = nil
    }
    
    // MARK: - 后台处理
    
    private func setupBackgroundHandling() {
        // 监听app进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // 监听app进入前台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        // 监听app即将终止
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // 监听音频中断
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidEnterBackground() {
        print("📱 App进入后台，确保录音继续...")
        
        guard isRecording else { return }
        
        // 确保音频会话保持活跃
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ 后台音频会话激活失败: \(error)")
        }
        
        // 立即更新Live Activity
        updateLiveActivity()
    }
    
    @objc private func handleAppWillEnterForeground() {
        print("📱 App回到前台")
        
        // 更新Live Activity状态
        if isRecording {
            updateLiveActivity()
        }
    }
    
    @objc private func handleAppWillTerminate() {
        print("🚨 App即将终止，自动保存录音")
        
        // 如果正在录音，立即停止并保存
        if isRecording {
            // 获取 ModelContext
            let context = modelContextProvider?()
            
            // 同步停止录音（因为时间紧迫）
            isRecording = false
            isPaused = false
            
            // 停止录音器
            audioRecorder?.stop()
            recordingTimer?.invalidate()
            
            // 停止音频引擎
            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            
            // 保存到数据库
            saveToMeeting(modelContext: context)
            
            // 结束 Live Activity
            if let activity = activity {
                let finalState = MeetingRecordingAttributes.ContentState(
                    transcribedText: recognizedText,
                    duration: recordingDuration,
                    isRecording: false,
                    isPaused: false
                )
                
                Task {
                    await activity.end(using: finalState, dismissalPolicy: .immediate)
                }
            }
            
            print("✅ 录音已自动保存（App终止）")
        }
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("⚠️ 音频中断开始")
            if isRecording && !isPaused {
                pauseRecording()
            }
            
        case .ended:
            print("✅ 音频中断结束")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && isPaused {
                    resumeRecording()
                }
            }
            
        @unknown default:
            break
        }
    }
    
    // MARK: - 辅助方法
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: date)
    }
    
    private func ensureRecordingsFolder() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsURL.appendingPathComponent("MeetingRecordings", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                print("❌ 创建录音目录失败: \(error)")
            }
        }
        
        return folderURL
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

