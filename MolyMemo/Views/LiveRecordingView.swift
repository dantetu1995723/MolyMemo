import SwiftUI
import SwiftData

// 实时录音视图 - 在后台显示最小化界面
struct LiveRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var recordingManager = LiveRecordingManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    // 点击背景不关闭，避免误触
                }
            
            VStack {
                Spacer()
                
                // 录音卡片
                VStack(spacing: 16) {
                    // 头部：标题和关闭按钮
                    HStack {
                        Text("会议录音")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.85))
                        
                        Spacer()
                        
                        Button(action: {
                            recordingManager.stopRecording(modelContext: modelContext)
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Color.black.opacity(0.3))
                        }
                    }
                    
                    // 录音时长
                    HStack(spacing: 12) {
                        // 动画录音图标
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "waveform")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.red)
                                .symbolEffect(.variableColor.iterative, isActive: recordingManager.isRecording)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDuration(recordingManager.recordingDuration))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .monospacedDigit()
                            
                            Text("录音中...")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Divider()
                    
                    // 实时转写文字
                    ScrollView {
                        if recordingManager.recognizedText.isEmpty {
                            Text("等待说话...")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        } else {
                            Text(recordingManager.recognizedText)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(.primary)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // 停止按钮
                    Button(action: {
                        recordingManager.stopRecording(modelContext: modelContext)
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("停止录音")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.red)
                                .shadow(color: Color.red.opacity(0.4), radius: 12, x: 0, y: 6)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // 设置 ModelContext 提供器
            recordingManager.modelContextProvider = { [modelContext] in
                return modelContext
            }
            
            // 如果还没开始录音，现在开始
            if !recordingManager.isRecording {
                recordingManager.startRecording()
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

