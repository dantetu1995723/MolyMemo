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
    /// 用户点击“开始录音”后到真正开始录音之间的过渡态，用来让 UI 立刻响应，避免主线程被初始化工作卡住
    @Published var isStartingRecording = false
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
    // 上传生成后，是否写入“聊天室会议卡片”（生成中 -> 完成/失败）
    private var uploadToChat: Bool = true
    // 上传生成后，是否通知会议列表页插入/更新“占位条目”
    private var updateMeetingList: Bool = false
    
    // 保存 ModelContext 的回调
    var modelContextProvider: (() -> ModelContext?)?
    
    private init() {
        // 监听app状态变化，确保后台录音正常
        setupBackgroundHandling()
        // 启动时清理所有残留的Live Activity
        cleanupStaleActivities()
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    private func hasMicrophonePermission() -> Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }

    private func hasSpeechPermission() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    // 开始录音
    /// - Parameter publishTranscriptionToUI: 是否在 Live Activity / 灵动岛显示实时转写文本（默认 true）。
    /// - Parameter uploadToChat: 是否在聊天室生成会议卡片（默认 true）。
    /// - Parameter updateMeetingList: 是否在会议列表页插入/更新占位条目（默认 false）。
    func startRecording(publishTranscriptionToUI: Bool = true, uploadToChat: Bool = true, updateMeetingList: Bool = false) {
        self.publishTranscriptionToUI = publishTranscriptionToUI
        self.uploadToChat = uploadToChat
        self.updateMeetingList = updateMeetingList
        print("[RecordingFlow] 🎙️ startRecording publishToUI=\(publishTranscriptionToUI)")

        // 先让 UI 进入“启动中”，避免用户感觉点了没反应
        runOnMain { [weak self] in
            guard let self else { return }
            if self.isRecording { return }
            self.isStartingRecording = true
        }
        
        // 快路径：权限都已有时，不走系统弹窗链路，直接开始初始化
        if hasMicrophonePermission(), hasSpeechPermission() {
            setupRecordingAsync()
            return
        }

        // 请求权限（可能触发系统弹窗）
        requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                print("[RecordingFlow] ❌ startRecording permission denied")
                self.runOnMain { self.isStartingRecording = false }
                return
            }
            self.setupRecordingAsync()
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
    
    /// 把耗时初始化尽量挪到后台，主线程只做“立刻刷新 UI”
    private func setupRecordingAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.setupRecordingInBackground()
        }
    }

    private func setupRecordingInBackground() {
        // 配置音频会话 - 支持后台录音（放后台，避免主线程卡顿）
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
            print("[RecordingFlow] ❌ setupRecording audioSession failed -> \(error.localizedDescription)")
            runOnMain { [weak self] in self?.isStartingRecording = false }
            return
        }

        // 准备录音文件（统一存放在 MeetingRecordings 文件夹）
        let recordingsFolder = ensureRecordingsFolder()
        let newAudioURL = recordingsFolder.appendingPathComponent("meeting_\(Int(Date().timeIntervalSince1970)).m4a")
        print("[RecordingFlow] 📁 recording file = \(newAudioURL.path)")

        // 配置录音设置（m4a AAC 格式，高质量压缩）
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        do {
            let recorder = try AVAudioRecorder(url: newAudioURL, settings: settings)
            recorder.record()
            print("[RecordingFlow] ✅ AVAudioRecorder started (m4a/AAC 44.1k 1ch)")

            // 主线程：立刻刷新 UI（按钮/列表）
            runOnMain { [weak self] in
                guard let self else { return }
                self.audioURL = newAudioURL
                self.audioRecorder = recorder
                self.isRecording = true
                self.isStartingRecording = false
                self.isPaused = false
                self.recognizedText = ""
                self.recordingDuration = 0

                // 启动计时器放主线程 runloop，避免后台 runloop 不运行
                self.recordingTimer?.invalidate()
                self.recordingTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.recordingDuration += 0.5
                }
                RunLoop.main.add(self.recordingTimer!, forMode: .common)
            }

            // 语音识别/Live Activity 延后启动，优先让 UI 先“动起来”
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.startSpeechRecognition()
                self?.startLiveActivity()
            }
        } catch {
            print("[RecordingFlow] ❌ AVAudioRecorder create/start failed -> \(error.localizedDescription)")
            runOnMain { [weak self] in self?.isStartingRecording = false }
        }
    }
    
    // 启动实时语音识别
    private func startSpeechRecognition() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            return
        }
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
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
        } catch {
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
                }
            }
        }
    }
    
    // 暂停录音
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        
        isPaused = true
        print("[RecordingFlow] ⏸️ pauseRecording")
        
        // 暂停录音器
        audioRecorder?.pause()
        recordingTimer?.invalidate()
        
        // 暂停音频引擎
        audioEngine.pause()
        
        // 更新 Live Activity
        updateLiveActivity()
        
    }
    
    // 继续录音
    func resumeRecording() {
        guard isRecording && isPaused else { return }
        
        isPaused = false
        print("[RecordingFlow] ▶️ resumeRecording")
        
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
        }
        
        // 更新 Live Activity
        updateLiveActivity()
        
    }
    
    // 停止录音
    func stopRecording(modelContext: ModelContext? = nil) {
        // SwiftUI/ObservableObject 的状态更新必须在主线程
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording(modelContext: modelContext)
            }
            return
        }
        
        guard isRecording else { 
            return 
        }
        // 注意：recordingDuration 是 UI 计时器驱动（0.5s 一跳），用于展示即可；
        // 真实时长以 AVAudioRecorder.currentTime 为准，避免短录音被误判为 0/过短导致直接丢弃，从而“没有生成卡片”。
        let recorderSeconds = audioRecorder?.currentTime ?? 0
        let measuredDuration = max(recorderSeconds, recordingDuration)
        print("[RecordingFlow] 🛑 stopRecording duration=\(measuredDuration)s (ui=\(recordingDuration)s, rec=\(recorderSeconds)s) recognizedTextLen=\(recognizedText.count)")

        // ⚡️ 关键：主线程只做“立刻切 UI + 立刻发通知”，重清理放后台，避免停止按钮点击后卡顿
        let finalDuration = measuredDuration
        let finalAudioURL = audioURL

        isStartingRecording = false
        isRecording = false
        isPaused = false

        // 先停录音器并终止计时（尽快 flush 文件，确保后续读取完整）
        audioRecorder?.stop()
        recordingTimer?.invalidate()

        // ✅ 立刻通知主 App 进入“上传/生成”流程：
        // - 不再用“时长阈值”决定要不要生成卡片（用户停止就应生成：成功/失败都要给结果）
        // - 若文件缺失/无效，也会发通知，让上层生成“失败卡片”而不是静默消失
        postRecordingNeedsUpload(audioURL: finalAudioURL, duration: finalDuration)

        // 后台做耗时清理，避免阻塞 UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.cleanupAfterStop()
            DispatchQueue.main.async {
                // 结束 Live Activity（内部包含展示与延迟逻辑）
                self?.endLiveActivity()
            }
        }
    }

    /// 停止录音后的资源清理（放后台执行，避免 UI 卡顿）
    private func cleanupAfterStop() {
        // 停止音频引擎（语音识别用）
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // 收回 AudioSession，避免后续播放异常
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[RecordingFlow] ⚠️ audioSession deactivate failed -> \(error.localizedDescription)")
        }
    }
    
    /// 通知主App上传音频到后端生成会议纪要
    /// 注意：这里只发送通知，实际的后端调用由主App处理（因为Widget Extension无法访问MeetingMinutesService）
    private func uploadToBackend() {
        postRecordingNeedsUpload(audioURL: audioURL, duration: recordingDuration)
    }

    private func postRecordingNeedsUpload(audioURL: URL?, duration: TimeInterval) {
        let audioPath = audioURL?.path ?? ""
        print("[RecordingFlow] ☁️ notify backend upload audioPath=\(audioPath)")

        let title = "Moly录音 - \(formatDate(Date()))"
        let date = Date()

        let meetingData: [String: Any] = [
            "title": title,
            "date": date,
            "duration": duration,
            "audioPath": audioPath,
            "needsBackendUpload": true,
            // 新字段（更清晰）
            "uploadToChat": uploadToChat,
            "updateMeetingList": updateMeetingList,
            // 旧字段：继续写入以兼容历史监听逻辑（含外部 Extension/老版本）
            "suppressChatCard": !uploadToChat
        ]

        // NotificationCenter 的 publisher 默认在“发送线程”回调；为了避免 SwiftUI 状态在后台更新，强制在主线程发送
        if Thread.isMainThread {
            NotificationCenter.default.post(
                name: NSNotification.Name("RecordingNeedsUpload"),
                object: nil,
                userInfo: meetingData
            )
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RecordingNeedsUpload"),
                    object: nil,
                    userInfo: meetingData
                )
            }
        }
    }
    
    // MARK: - Live Activity 管理
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        
        let attributes = MeetingRecordingAttributes(meetingTitle: "Moly录音")
        let contentState = MeetingRecordingAttributes.ContentState(
            transcribedText: isPaused ? "已暂停" : "录音中",
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
        } catch {
        }
    }
    
    private func updateLiveActivity() {
        guard let activity = activity else { return }
        
        let contentState = MeetingRecordingAttributes.ContentState(
            transcribedText: {
                // 灵动岛不再展示实时转写/计时，固定文案即可
                return isPaused ? "已暂停" : "录音中"
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
            transcribedText: "录音中",
            duration: recordingDuration,
            isRecording: false,
            isPaused: false
        )
        
        // 捕获当前的 activity 引用
        let currentActivity = activity
        
        Task {
            // 点击停止后立刻结束灵动岛/Live Activity（不再停留/不展示计时完成态）
            if #available(iOS 16.2, *) {
                let content = ActivityContent(
                    state: finalState,
                    staleDate: nil,
                    relevanceScore: 100.0
                )
                await currentActivity.end(content, dismissalPolicy: .immediate)
            } else {
                await currentActivity.end(dismissalPolicy: .immediate)
            }
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
    }
    
    // 清理所有残留的Live Activity
    private func cleanupStaleActivities() {
        
        Task { @MainActor in
            let activities = Activity<MeetingRecordingAttributes>.activities
            guard !activities.isEmpty else {
                return
            }
            
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
            }
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
        
        guard isRecording else { return }
        
        // 确保音频会话保持活跃
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
        }
        
        // 立即更新Live Activity
        updateLiveActivity()
    }
    
    @objc private func handleAppWillEnterForeground() {
        
        // 更新Live Activity状态
        if isRecording {
            updateLiveActivity()
        }
    }
    
    @objc private func handleAppWillTerminate() {
        
        // 如果正在录音，立即停止（但无法上传到后端，因为app即将终止）
        if isRecording {
            
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
                    // iOS 16.2+ 推荐使用 end(_ content:dismissalPolicy:)；这里统一走 ActivityContent，避免废弃警告
                    let content = ActivityContent(
                        state: finalState,
                        staleDate: nil,
                        relevanceScore: 100.0
                    )
                    await activity.end(content, dismissalPolicy: .immediate)
                    semaphore.signal()
                }
                // 最多等待0.5秒
                _ = semaphore.wait(timeout: .now() + 0.5)
                self.activity = nil
            }
            
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
            if isRecording && !isPaused {
                pauseRecording()
            }
            
        case .ended:
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
        DispatchQueue.main.async { [weak self] in
            self?.pauseRecording()
        }
    }
    
    @objc private func handleResumeFromWidget() {
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
        // 统一后端接入：录音文件不应持久化在 Documents，改用临时目录（可被系统回收，且会在启动时清理）。
        let baseURL = FileManager.default.temporaryDirectory
        let folderURL = baseURL.appendingPathComponent("MeetingRecordings", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
            }
        }
        
        return folderURL
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

