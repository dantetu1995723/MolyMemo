import SwiftUI
import PhotosUI

// 简化的图片选择器 - 选择后直接发送
struct ImagePickerView: View {
    @Environment(\.dismiss) var dismiss
    let onImagesSelected: ([UIImage]) -> Void
    
    var body: some View {
        SystemPhotosPicker(onComplete: { images in
            if !images.isEmpty {
                onImagesSelected(images)
            } else {
            }
            dismiss()
        })
    }
}

// 系统PHPicker包装器 - 简化版
struct SystemPhotosPicker: UIViewControllerRepresentable {
    let onComplete: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 9
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([UIImage]) -> Void
        
        init(onComplete: @escaping ([UIImage]) -> Void) {
            self.onComplete = onComplete
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            
            guard !results.isEmpty else {
                onComplete([])
                return
            }
            
            Task {
                var loadedImages: [UIImage] = []
                
                for result in results {
                    let provider = result.itemProvider
                    
                    if provider.canLoadObject(ofClass: UIImage.self) {
                        
                        do {
                            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
                                provider.loadObject(ofClass: UIImage.self) { object, error in
                                    if let error = error {
                                        continuation.resume(throwing: error)
                                    } else if let image = object as? UIImage {
                                        continuation.resume(returning: image)
                                    } else {
                                        continuation.resume(throwing: NSError(domain: "ImagePicker", code: -1))
                                    }
                                }
                            }
                            
                            loadedImages.append(image)
                        } catch {
                        }
                    }
                }
                
                await MainActor.run {
                    onComplete(loadedImages)
                }
            }
        }
    }
}
