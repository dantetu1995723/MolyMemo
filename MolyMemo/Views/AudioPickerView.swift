import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// 音频文件选择器
struct AudioPickerView: View {
    @Environment(\.dismiss) var dismiss
    let onAudioSelected: (URL, String, TimeInterval) -> Void
    
    var body: some View {
        AudioDocumentPicker(
            contentTypes: [
                .audio,
                .mp3,
                .wav,
                .aiff,
                UTType(filenameExtension: "m4a") ?? .audio,
                UTType(filenameExtension: "aac") ?? .audio
            ],
            onComplete: { urls in
                
                if let url = urls.first {
                    // 获取音频文件信息（使用异步 API 获取时长）
                    let fileName = url.lastPathComponent
                    
                    Task {
                        let duration = await getAudioDuration(url: url)
                        
                        
                        await MainActor.run {
                            onAudioSelected(url, fileName, duration)
                            dismiss()
                        }
                        
                    }
                } else {
                    dismiss()
                }
            }
        )
    }
    
    // 获取音频时长
    private func getAudioDuration(url: URL) async -> TimeInterval {
        let audioAsset = AVURLAsset(url: url)
        guard let durationTime = try? await audioAsset.load(.duration) else {
            return 0
        }

        let seconds = CMTimeGetSeconds(durationTime)
        
        // 如果duration无效，返回0
        if seconds.isNaN || seconds.isInfinite {
            return 0
        }
        
        return seconds
    }
}

// 系统文档选择器包装器（音频专用）
struct AudioDocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onComplete: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: ([URL]) -> Void
        
        init(onComplete: @escaping ([URL]) -> Void) {
            self.onComplete = onComplete
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete([])
        }
    }
}

