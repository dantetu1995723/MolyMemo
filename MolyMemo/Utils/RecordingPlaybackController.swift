import Foundation
import Combine
import UIKit

/// 录音播放控制器（全局唯一），用于让"卡片快速播放"和"详情页播放控制"共享同一播放状态。
@MainActor
final class RecordingPlaybackController: ObservableObject {
    static let shared = RecordingPlaybackController()

    @Published private(set) var currentMeetingId: UUID? = nil
    @Published private(set) var currentURL: URL? = nil
    @Published private(set) var isDownloading: Bool = false

    let player: AudioPlayer
    private var cancellable: AnyCancellable?
    private var remoteCache: [String: URL] = [:] // remoteURL -> local temp file URL
    private var downloadTask: Task<Void, Never>? = nil

    private init(player: AudioPlayer = AudioPlayer()) {
        self.player = player
        // 转发 AudioPlayer 的变化通知，使 SwiftUI 视图能感知 currentTime/isPlaying 等变化
        cancellable = player.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isPlaying: Bool { player.isPlaying }
    var currentTime: TimeInterval { player.currentTime }
    var duration: TimeInterval { player.duration }

    func canPlay(meeting: MeetingCard) -> Bool {
        // 1) 本地音频：若存在则直接可播（避免必须进详情页才能播）
        if let path = meeting.audioPath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
        }

        // 2) 远程音频：检查缓存/远程URL
        if let remote = meeting.audioRemoteURL, remoteCache[remote] != nil {
            return true
        }
        // 远程链接存在：允许点击播放（点击后会自动下载到本地再播）
        if let remote = meeting.audioRemoteURL,
           !remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           resolveRemoteURL(from: remote) != nil {
            return true
        }
        return false
    }

    func url(for meeting: MeetingCard) -> URL? {
        // 1) 本地音频优先
        if let path = meeting.audioPath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // 2) 远程缓存
        if let remote = meeting.audioRemoteURL, let cached = remoteCache[remote] {
            return cached
        }
        return nil
    }

    func isCurrent(meeting: MeetingCard) -> Bool {
        currentMeetingId == meeting.id
    }

    func togglePlay(meeting: MeetingCard) {
        #if DEBUG
        #endif
        // 当前正在播同一条：切换 pause/resume
        if isCurrent(meeting: meeting), url(for: meeting) != nil {
            if player.isPlaying { player.pause() } else { player.resume() }
            return
        }

        // 1) 先尝试本地/缓存 URL
        if let u = url(for: meeting) {
            #if DEBUG
            #endif
            currentMeetingId = meeting.id
            currentURL = u
            player.play(url: u)
            return
        }

        // 2) 无缓存：从远程下载后播放
        guard let remote = meeting.audioRemoteURL,
              let remoteURL = resolveRemoteURL(from: remote)
        else {
            #if DEBUG
            #endif
            return
        }

        currentMeetingId = meeting.id
        guard !isDownloading else { return }
        isDownloading = true

        downloadTask?.cancel()
        downloadTask = Task {
            do {
                #if DEBUG
                #endif
                let local = try await downloadToTemp(remoteURL: remoteURL)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.remoteCache[remote] = local
                    self.isDownloading = false
                    self.currentURL = local
                    self.player.play(url: local)
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.isDownloading = false
                }
            }
        }
    }

    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        player.stop()
        currentMeetingId = nil
        currentURL = nil
    }

    /// 预下载远程音频到缓存（不播放），用于“POST 完生成成功后，一口气把下载也做掉”
    func prefetch(meeting: MeetingCard) {
        // 本地已存在就不需要预下载
        if let local = url(for: meeting), local.isFileURL {
            #if DEBUG
            #endif
            return
        }
        guard let remote = meeting.audioRemoteURL,
              !remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              remoteCache[remote] == nil,
              let remoteURL = resolveRemoteURL(from: remote)
        else {
            #if DEBUG
            #endif
            return
        }

        Task {
            do {
                #if DEBUG
                #endif
                let local = try await downloadToTemp(remoteURL: remoteURL)
                await MainActor.run {
                    self.remoteCache[remote] = local
                }
                #if DEBUG
                #endif
            } catch {
                #if DEBUG
                #endif
            }
        }
    }

    func seek(to time: TimeInterval) {
        player.seek(to: time)
    }

    func skip(by delta: TimeInterval) {
        seek(to: player.currentTime + delta)
    }

    // MARK: - Remote download
    private func downloadToTemp(remoteURL: URL) async throws -> URL {
        var request = URLRequest(url: remoteURL, timeoutInterval: 60)
        request.httpMethod = "GET"
        applyDownloadHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            #if DEBUG
            #endif
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let ext = remoteURL.pathExtension.isEmpty ? "m4a" : remoteURL.pathExtension
        let fileName = "yuanyuan_meeting_audio_\(abs(remoteURL.absoluteString.hashValue)).\(ext)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // 已存在直接复用
        if FileManager.default.fileExists(atPath: fileURL.path) {
            #if DEBUG
            #endif
            return fileURL
        }

        #if DEBUG
        #endif
        try data.write(to: fileURL, options: [.atomic])
        #if DEBUG
        #endif
        return fileURL
    }

    private func resolveRemoteURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) 已是完整 URL
        if let u = URL(string: trimmed), u.scheme != nil {
            #if DEBUG
            #endif
            return u
        }

        // 2) 相对路径：拼 baseURL
        let baseCandidate = BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseCandidate.isEmpty ? BackendChatConfig.defaultBaseURL : baseCandidate
        let normalizedBase = BackendChatConfig.normalizeBaseURL(base)
        let path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        let final = normalizedBase + path
        #if DEBUG
        #endif
        return URL(string: final)
    }

    private func applyDownloadHeaders(to request: inout URLRequest) {
        // 尽量与聊天/会议接口保持一致的 header（很多后端会用 session header 校验下载权限）
        let sessionId = BackendChatConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessionId.isEmpty {
            request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        } else if
            let fromDefaults = UserDefaults.standard.string(forKey: "yuanyuan_auth_session_id")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !fromDefaults.isEmpty
        {
            request.setValue(fromDefaults, forHTTPHeaderField: "X-Session-Id")
        }

        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-App-Id")
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        request.setValue(appVersion.isEmpty ? "" : "\(appVersion) (\(build))", forHTTPHeaderField: "X-App-Version")
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "", forHTTPHeaderField: "X-Device-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-OS-Type")
        request.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-OS-Version")

        request.setValue("", forHTTPHeaderField: "X-Longitude")
        request.setValue("", forHTTPHeaderField: "X-Latitude")
        request.setValue("", forHTTPHeaderField: "X-Address")
        request.setValue("", forHTTPHeaderField: "X-City")
        request.setValue("", forHTTPHeaderField: "X-Country")
    }
}


