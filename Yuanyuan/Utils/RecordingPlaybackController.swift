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
        if let path = meeting.audioPath, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return true
        }
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
        if let path = meeting.audioPath, !path.isEmpty {
            let u = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        if let remote = meeting.audioRemoteURL, let cached = remoteCache[remote] {
            return cached
        }
        return nil
    }

    func isCurrent(meeting: MeetingCard) -> Bool {
        currentMeetingId == meeting.id
    }

    func togglePlay(meeting: MeetingCard) {
        // 当前正在播同一条：切换 pause/resume
        if isCurrent(meeting: meeting), url(for: meeting) != nil {
            if player.isPlaying { player.pause() } else { player.resume() }
            return
        }

        // 1) 先尝试本地路径/缓存
        if let u = url(for: meeting) {
            currentMeetingId = meeting.id
            currentURL = u
            player.play(url: u)
            return
        }

        // 2) 无本地文件：尝试下载远程原始录音再播放
        guard let remote = meeting.audioRemoteURL,
              let remoteURL = resolveRemoteURL(from: remote)
        else {
            return
        }

        currentMeetingId = meeting.id
        guard !isDownloading else { return }
        isDownloading = true

        Task {
            do {
                let local = try await downloadToTemp(remoteURL: remoteURL)
                await MainActor.run {
                    self.remoteCache[remote] = local
                    self.isDownloading = false
                    self.currentURL = local
                    self.player.play(url: local)
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    print("⚠️ [RecordingPlaybackController] 下载录音失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        player.stop()
        currentMeetingId = nil
        currentURL = nil
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

        print("🌐 [RecordingPlaybackController] 下载录音: \(remoteURL.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            print("⚠️ [RecordingPlaybackController] 下载状态码: \(http.statusCode)")
            throw URLError(.badServerResponse)
        }

        let ext = remoteURL.pathExtension.isEmpty ? "m4a" : remoteURL.pathExtension
        let fileName = "yuanyuan_meeting_audio_\(abs(remoteURL.absoluteString.hashValue)).\(ext)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // 已存在直接复用
        if FileManager.default.fileExists(atPath: fileURL.path) { return fileURL }

        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private func resolveRemoteURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) 已是完整 URL
        if let u = URL(string: trimmed), u.scheme != nil { return u }

        // 2) 相对路径：拼 baseURL
        let baseCandidate = BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseCandidate.isEmpty ? "http://192.168.106.108:8000" : baseCandidate
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return URL(string: normalizedBase + path)
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


