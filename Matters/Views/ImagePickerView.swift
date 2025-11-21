import SwiftUI
import PhotosUI

// 简化的图片选择器 - 选择后直接发送
struct ImagePickerView: View {
    @Environment(\.dismiss) var dismiss
    let onImagesSelected: ([UIImage]) -> Void
    
    var body: some View {
        SystemPhotosPicker(onComplete: { images in
            print("\n========== 📸 图片选择完成 ==========")
            print("选择数量: \(images.count)")
            if !images.isEmpty {
                print("准备回调发送...")
                onImagesSelected(images)
                print("回调已触发")
            } else {
                print("用户取消选择")
            }
            dismiss()
            print("======================================\n")
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
            
            print("📷 PHPicker 选择了 \(results.count) 个结果")
            
            guard !results.isEmpty else {
                print("📷 用户取消选择")
                onComplete([])
                return
            }
            
            Task {
                var loadedImages: [UIImage] = []
                
                for (index, result) in results.enumerated() {
                    let provider = result.itemProvider
                    
                    if provider.canLoadObject(ofClass: UIImage.self) {
                        print("📷 正在加载图片 \(index + 1)/\(results.count)...")
                        
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
                            
                            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                                let sizeInKB = Double(jpegData.count) / 1024.0
                                print("✅ 图片 \(index + 1) 加载成功")
                                print("   尺寸: \(image.size.width) x \(image.size.height)")
                                print("   原始大小: \(String(format: "%.1f", sizeInKB)) KB")
                            }
                            
                        } catch {
                            print("⚠️ 图片 \(index + 1) 加载失败: \(error)")
                        }
                    }
                }
                
                await MainActor.run {
                    print("✅ 所有图片加载完成，共 \(loadedImages.count) 张")
                    onComplete(loadedImages)
                }
            }
        }
    }
}
