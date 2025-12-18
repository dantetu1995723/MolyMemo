import SwiftUI
import PhotosUI

// MARK: - Toolbox Button
struct ToolboxButton: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Image(systemName: "shippingbox")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "666666")) // Reverted to 666666
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color(hex: "F7F8FA"))
                )
                .overlay(
                    Circle()
                        .inset(by: 0.5)
                        .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 1)
                )
        }
    }
}

// MARK: - Attachment Preview
struct AttachmentPreview: View {
    let image: UIImage
    let onDelete: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .cornerRadius(12)
                .clipped()
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.black.opacity(0.2)))
            }
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Suggestion Bar
struct SuggestionBar: View {
    let suggestions: [String] = ["创建日程", "创建人脉", "创建报销"]
    let onSuggestionTap: ((String) -> Void)?
    
    init(onSuggestionTap: ((String) -> Void)? = nil) {
        self.onSuggestionTap = onSuggestionTap
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        onSuggestionTap?(suggestion)
                    }) {
                        HStack(alignment: .center, spacing: 4) {
                            Text(suggestion)
                                .font(Font.custom("PingFang SC", size: 14))
                                .kerning(0.5)
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 0.36, green: 0.36, blue: 0.36))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .inset(by: 0.5)
                                .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Camera Picker
struct CameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let dismiss: DismissAction
        
        init(onImagePicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Action Menu
struct ActionMenu: View {
    @ObservedObject var viewModel: ChatInputViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 拍照片
                Button(action: {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        viewModel.showCamera = true
                    }
                }) {
                    MenuCardView(icon: "camera", label: "拍照片")
                }
                .buttonStyle(PlainButtonStyle())
                
                // 传图片
                PhotosUI.PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                    MenuCardView(icon: "photo", label: "传图片")
                }
                .buttonStyle(PlainButtonStyle())
                
                // 扫一扫
                Button(action: {
                    // Scan action
                }) {
                    MenuCardView(icon: "qrcode.viewfinder", label: "扫一扫")
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // 第二行占位（保持两行高度）
            HStack(spacing: 12) {
                Color.clear.frame(maxWidth: .infinity).frame(height: 110)
                Color.clear.frame(maxWidth: .infinity).frame(height: 110)
                Color.clear.frame(maxWidth: .infinity).frame(height: 110)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "F7F8FA"))
        .fullScreenCover(isPresented: $viewModel.showCamera) {
            CameraPicker { image in
                viewModel.selectedImage = image
                viewModel.showMenu = false
                viewModel.checkForSuggestions()
            }
            .ignoresSafeArea()
        }
    }
}

// 纯样式组件，不带手势，由外部包装 Button 或 Picker
private struct MenuCardView: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "333333"))
                .frame(width: 32, height: 32)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "666666"))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
    }
}
