import Foundation
import AVFoundation

// 音频播放管理器
class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentURL: URL? = nil
    
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    
    override init() {
        super.init()
        configureAudioSessionForPlayback()
    }
    
    // 配置音频会话（播放高质量优先）
    private func configureAudioSessionForPlayback() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 关键点：每次播放前要把 session 拉回 playback（否则可能被录音/通话模式残留影响，导致闷/卡顿）
            if #available(iOS 10.0, *) {
                // 注意：notifyOthersOnDeactivation 只应在 setActive(false) 时使用；
                // playback 下也不要随意叠加不适用的 option，否则可能触发 OSStatus -50
                try audioSession.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            } else {
                try audioSession.setCategory(.playback, mode: .default)
            }
            try audioSession.setActive(true)
            
            #if DEBUG
            let route = audioSession.currentRoute.outputs.map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ", ")
            print("🔊 [AudioPlayer] AudioSession ready category=\(audioSession.category.rawValue) mode=\(audioSession.mode.rawValue) route=[\(route)]")
            #endif
        } catch {
            print("⚠️ [AudioPlayer] 音频会话配置失败: \(error)")
            #if DEBUG
            let ns = error as NSError
            print("⚠️ [AudioPlayer] error domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            #endif
        }
    }
    
    // 从 URL 播放音频
    func play(url: URL) {
        stop()
        // 防止其它模块改写 AudioSession，导致播放音质异常
        configureAudioSessionForPlayback()
        
        do {
            #if DEBUG
            print("🎵 [AudioPlayer] play(url): \(url.absoluteString)")
            print("🎵 [AudioPlayer] isFileURL=\(url.isFileURL) exists=\(FileManager.default.fileExists(atPath: url.path))")
            #endif
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()
            currentURL = url
            
            isPlaying = true
            
            // 启动进度计时器
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }
            
            print("🔊 开始播放音频，时长: \(String(format: "%.1f", duration))秒")
        } catch {
            print("⚠️ [AudioPlayer] 音频播放失败: \(error)")
            #if DEBUG
            print("⚠️ [AudioPlayer] url=\(url.absoluteString)")
            #endif
        }
    }
    
    // 从 Data 播放音频
    func play(data: Data) {
        stop()
        configureAudioSessionForPlayback()
        
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()
            currentURL = nil
            
            isPlaying = true
            
            // 启动进度计时器
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }
            
            print("🔊 开始播放音频，时长: \(String(format: "%.1f", duration))秒")
        } catch {
            print("⚠️ 音频播放失败: \(error)")
        }
    }
    
    // 停止播放
    func stop() {
        audioPlayer?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        isPlaying = false
        currentTime = 0
        duration = 0
        currentURL = nil
    }
    
    // 暂停播放
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    // 恢复播放
    func resume() {
        guard audioPlayer != nil else { return }
        configureAudioSessionForPlayback()
        audioPlayer?.play()
        isPlaying = true
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0
        }
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
        let clamped = max(0, min(time, audioPlayer.duration))
        audioPlayer.currentTime = clamped
        currentTime = clamped
    }
    
    // 格式化时间
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.playbackTimer?.invalidate()
            self?.playbackTimer = nil
            print("🔊 音频播放完成")
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            print("⚠️ 音频解码错误: \(error)")
        }
    }
}

