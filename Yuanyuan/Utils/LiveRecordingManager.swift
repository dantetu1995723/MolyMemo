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

    // Widget/快捷指令场景：可以只在后台做转写，但不把文本推到 UI（灵动岛/Live Activity）
    private var publishTranscriptionToUI: Bool = true
    
    // 保存 ModelContext 的回调
    var modelContextProvider: (() -> ModelContext?)?
    
    private init() {
        // 监听app状态变化，确保后台录音正常
        setupBackgroundHandling()
        // 启动时清理所有残留的Live Activity
        cleanupStaleActivities()
    }
    
    // 开始录音
    /// - Parameter publishTranscriptionToUI: 是否在 Live Activity / 灵动岛显示实时转写文本（默认 true）。
    func startRecording(publishTranscriptionToUI: Bool = true) {
        print("🎤 准备开始录音...")
        self.publishTranscriptionToUI = publishTranscriptionToUI
        
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
        // 请求麦克风权限（iOS 17 及以上使用 AVAudioApplication）
        let requestMicPermission: (@escaping (Bool) -> Void) -> Void = { handler in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    handler(granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    handler(granted)
                }
            }
        }

        requestMicPermission { micGranted in
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
            let options: AVAudioSession.CategoryOptions = [
                .defaultToSpeaker,
                .allowBluetoothA2DP,
                .mixWithOthers
            ]
            try audioSession.setCategory(.playAndRecord, mode: .default, options: options)
            try audioSession.setActive(true)
        } catch {
            print("❌ 音频会话配置失败: \(error)")
            return
        }
        
        // 准备录音文件（统一存放在 MeetingRecordings 文件夹）
        let recordingsFolder = ensureRecordingsFolder()
        audioURL = recordingsFolder.appendingPathComponent("meeting_\(Int(Date().timeIntervalSince1970)).m4a")
        
        guard let audioURL = audioURL else { return }
        
        // 配置录音设置（m4a AAC 格式，高质量压缩）
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
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
        print("🛑 ========== 停止录音 ==========")
        
        guard isRecording else { 
            print("⚠️ 当前没有在录音，跳过")
            return 
        }
        
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

        // 关键修复：停止录音后收回 AudioSession，避免后续播放音质异常/配置失败（OSStatus -50）
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            #if DEBUG
            print("🔇 [LiveRecordingManager] AudioSession deactivated")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [LiveRecordingManager] AudioSession deactivate failed: \(error)")
            #endif
        }
        
        print("🎙️ 录音已停止，准备上传到后端...")
        
        // 调用后端API生成会议纪要
        uploadToBackend()
        
        // 结束 Live Activity（内部已包含“已完成”状态展示和延迟逻辑）
        endLiveActivity()
        endLiveActivity()
        
        print("✅ ========== 停止录音完成 ==========\n")
    }
    
    /// 通知主App上传音频到后端生成会议纪要
    /// 注意：这里只发送通知，实际的后端调用由主App处理（因为Widget Extension无法访问MeetingMinutesService）
    private func uploadToBackend() {
        guard let audioURL = audioURL else {
            print("❌ [uploadToBackend] 没有音频文件URL")
            return
        }
        
        let title = "Moly录音 - \(formatDate(Date()))"
        let date = Date()
        let duration = recordingDuration
        let audioPath = audioURL.path
        
        print("📤 ========== 准备上传到后端 ==========")
        print("📤 [uploadToBackend] 音频路径: \(audioPath)")
        print("📤 [uploadToBackend] 标题: \(title)")
        print("📤 [uploadToBackend] 时长: \(duration)秒")
        
        // 发送通知，让主App处理后端上传
        // RecordingNeedsUpload: 主App会监听这个通知并调用MeetingMinutesService
        let meetingData: [String: Any] = [
            "title": title,
            "date": date,
            "duration": duration,
            "audioPath": audioPath,
            "needsBackendUpload": true  // 标记需要后端上传
        ]
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("RecordingNeedsUpload"),
                object: nil,
                userInfo: meetingData
            )
            print("📤 [uploadToBackend] 已发送上传请求通知到主App")
        }
        
        print("📤 ========== 通知已发送 ==========\n")
    }
    
    // MARK: - Live Activity 管理
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activity 未启用")
            return
        }
        
        let attributes = MeetingRecordingAttributes(meetingTitle: "Moly录音")
        let contentState = MeetingRecordingAttributes.ContentState(
            transcribedText: publishTranscriptionToUI ? "开始录音..." : "",
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
            transcribedText: {
                guard publishTranscriptionToUI else { return "" }
                return recognizedText.isEmpty ? "等待说话..." : recognizedText
            }(),
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
        
        // 捕获当前的 activity 引用
        let currentActivity = activity
        
        Task {
            // 1. 立即更新到“已完成”状态，灵动岛会根据 Widget 逻辑显示绿色勾选和完成文案
            let updateContent = ActivityContent(
                state: finalState,
                staleDate: nil,
                relevanceScore: 100.0
            )
            await currentActivity.update(updateContent)
            print("✨ 灵动岛已切换至“已完成”状态")
            
            // 2. 停留 2.5 秒，让用户有充足的时间感受到录音已经成功结束并保存
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            
            // 3. 正式告知系统结束 Activity
            // dismissalPolicy 设置为 immediate 因为我们已经在上面主动停留过了
            // 如果是在锁屏界面，系统会根据其策略决定是否继续保留小部件
            if #available(iOS 16.2, *) {
                await currentActivity.end(updateContent, dismissalPolicy: .after(.now + 1.0))
            } else {
                await currentActivity.end(dismissalPolicy: .after(.now + 1.0))
            }
            print("✅ Live Activity 已平滑消失")
        }
        
        // 置空实例，防止重复操作
        self.activity = nil
    }
    
    // 立即强制结束Live Activity（用于App终止时）
    private func endLiveActivityImmediately() {
        guard let activity = activity else { 
            // 没有activity实例，尝试清理所有活动的Activity
            cleanupStaleActivities()
            return
        }
        
        let finalState = MeetingRecordingAttributes.ContentState(
            transcribedText: recognizedText,
            duration: recordingDuration,
            isRecording: false,
            isPaused: false
        )
        
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(
                    state: finalState,
                    staleDate: nil,
                    relevanceScore: 100.0
                )
                await activity.end(content, dismissalPolicy: .immediate)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        self.activity = nil
        print("✅ Live Activity 已立即结束")
    }
    
    // 清理所有残留的Live Activity
    private func cleanupStaleActivities() {
        print("🧹 检查并清理残留的Live Activity...")
        
        Task { @MainActor in
            let activities = Activity<MeetingRecordingAttributes>.activities
            guard !activities.isEmpty else {
                print("   没有残留的Activity")
                return
            }
            
            print("   发现 \(activities.count) 个残留的Activity，开始清理...")
            for activity in activities {
                let finalState = MeetingRecordingAttributes.ContentState(
                    transcribedText: "",
                    duration: 0,
                    isRecording: false,
                    isPaused: false
                )
                if #available(iOS 16.2, *) {
                    let content = ActivityContent(
                        state: finalState,
                        staleDate: nil,
                        relevanceScore: 100.0
                    )
                    await activity.end(content, dismissalPolicy: .immediate)
                } else {
                    await activity.end(dismissalPolicy: .immediate)
                }
                print("   ✅ 已清理一个残留Activity")
            }
            print("✅ 所有残留Activity已清理完成")
        }
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
        
        // 监听来自Widget的暂停命令
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePauseFromWidget),
            name: NSNotification.Name("PauseRecordingFromWidget"),
            object: nil
        )
        
        // 监听来自Widget的继续命令
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResumeFromWidget),
            name: NSNotification.Name("ResumeRecordingFromWidget"),
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
        print("🚨 App即将终止")
        
        // 如果正在录音，立即停止（但无法上传到后端，因为app即将终止）
        if isRecording {
            print("⚠️ [handleAppWillTerminate] 录音正在进行中，强制停止...")
            print("⚠️ [handleAppWillTerminate] 注意：App终止时无法异步上传，录音文件已保存在本地")
            print("⚠️ [handleAppWillTerminate] 音频文件: \(audioURL?.path ?? "nil")")
            
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
            
            // 同步结束 Live Activity（使用信号量等待完成）
            if let activity = activity {
                let finalState = MeetingRecordingAttributes.ContentState(
                    transcribedText: recognizedText,
                    duration: recordingDuration,
                    isRecording: false,
                    isPaused: false
                )
                
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await activity.end(using: finalState, dismissalPolicy: .immediate)
                    semaphore.signal()
                }
                // 最多等待0.5秒
                _ = semaphore.wait(timeout: .now() + 0.5)
                self.activity = nil
                print("✅ Live Activity 已强制结束")
            }
            
            print("✅ 录音已停止（App终止，未上传后端）")
        } else {
            // 即使没在录音，也要清理可能残留的Activity
            endLiveActivityImmediately()
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
    
    @objc private func handlePauseFromWidget() {
        print("⏸️ 收到来自Widget的暂停命令")
        DispatchQueue.main.async { [weak self] in
            self?.pauseRecording()
        }
    }
    
    @objc private func handleResumeFromWidget() {
        print("▶️ 收到来自Widget的继续命令")
        DispatchQueue.main.async { [weak self] in
            self?.resumeRecording()
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

