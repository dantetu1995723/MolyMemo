import SwiftUI

/// 聊天室里的“会议纪要录音中”卡片（复用 LiveRecordingManager 的同一套录音通路）
struct ChatMeetingRecordingCardView: View {
    @ObservedObject var recordingManager: LiveRecordingManager = .shared
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("录音纪要 | 录制中...")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black.opacity(0.8))

                    Text(formatDuration(recordingManager.recordingDuration))
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.4))
                        .monospacedDigit()
                }
                Spacer()
            }

            // 波纹展示区（复用会议纪要页的简易波纹）
            SimpleWaveformView(audioPower: 0.5)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            Button(action: {
                HapticFeedback.medium()
                onStop()
            }) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("录音纪要录制中")
        .accessibilityValue(formatDuration(recordingManager.recordingDuration))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

