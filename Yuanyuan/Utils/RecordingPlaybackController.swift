import Foundation
import Combine

/// 录音播放控制器（全局唯一），用于让"卡片快速播放"和"详情页播放控制"共享同一播放状态。
@MainActor
final class RecordingPlaybackController: ObservableObject {
    static let shared = RecordingPlaybackController()

    @Published private(set) var currentMeetingId: UUID? = nil
    @Published private(set) var currentURL: URL? = nil

    let player: AudioPlayer
    private var cancellable: AnyCancellable?

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
        guard let path = meeting.audioPath, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func url(for meeting: MeetingCard) -> URL? {
        guard let path = meeting.audioPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    func isCurrent(meeting: MeetingCard) -> Bool {
        currentMeetingId == meeting.id
    }

    func togglePlay(meeting: MeetingCard) {
        guard let url = url(for: meeting),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return
        }

        if isCurrent(meeting: meeting) {
            if player.isPlaying {
                player.pause()
            } else {
                player.resume()
            }
            return
        }

        currentMeetingId = meeting.id
        currentURL = url
        player.play(url: url)
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
}


