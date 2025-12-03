import Photos
import UIKit

/// 相册管理器 - 用于自动获取最近的照片
class PhotoManager {
    static let shared = PhotoManager()
    
    private init() {}
    
    /// 请求相册访问权限
    func requestPhotoLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            print("✅ 相册权限已授权")
            return true
        case .notDetermined:
            print("🔍 请求相册权限...")
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            let granted = (newStatus == .authorized || newStatus == .limited)
            print(granted ? "✅ 用户授予了相册权限" : "❌ 用户拒绝了相册权限")
            return granted
        case .denied, .restricted:
            print("❌ 相册权限被拒绝或受限")
            return false
        @unknown default:
            return false
        }
    }
    
    /// 检查是否是有限访问权限
    func isLimitedAccess() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .limited
    }
    
    /// 提示用户选择更多照片（在有限访问模式下）
    func presentLimitedLibraryPicker() {
        guard #available(iOS 14, *) else { return }
        
        // iOS 15+ 不再推荐直接访问 UIApplication.shared.windows，
        // 这里通过当前激活的 UIWindowScene 获取 keyWindow。
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            print("⚠️ 无法找到有效的根视图控制器，无法打开相册选择器")
            return
        }
        
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
    }
    
    /// 获取相册最近的一张照片
    func fetchLatestPhoto() async -> UIImage? {
        print("🔍 开始获取相册最近一张照片...")
        
        // 检查权限
        let hasPermission = await requestPhotoLibraryPermission()
        guard hasPermission else {
            print("❌ 无相册权限，无法获取照片")
            return nil
        }
        
        // 创建获取选项：按创建日期降序排列
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        // 获取所有照片
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let asset = fetchResult.firstObject else {
            print("❌ 相册中没有照片")
            return nil
        }
        
        print("✅ 找到最近一张照片，创建时间: \(asset.creationDate ?? Date())")
        
        // 获取图片
        return await fetchImage(from: asset)
    }
    
    /// 获取最近 N 张照片
    func fetchLatestPhotos(count: Int) async -> [UIImage] {
        print("🔍 开始获取相册最近 \(count) 张照片...")
        
        // 检查权限
        let hasPermission = await requestPhotoLibraryPermission()
        guard hasPermission else {
            print("❌ 无相册权限，无法获取照片")
            return []
        }
        
        // 创建获取选项：按创建日期降序排列
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = count
        
        // 获取所有照片
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard fetchResult.count > 0 else {
            print("❌ 相册中没有照片")
            return []
        }
        
        print("✅ 找到 \(fetchResult.count) 张照片")
        
        // 并行获取所有图片
        var images: [UIImage] = []
        for i in 0..<fetchResult.count {
            let asset = fetchResult.object(at: i)
            if let image = await fetchImage(from: asset) {
                images.append(image)
            }
        }
        
        print("✅ 成功获取 \(images.count) 张图片")
        return images
    }
    
    /// 从 PHAsset 获取 UIImage
    private func fetchImage(from asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            // 获取原图尺寸
            let targetSize = CGSize(
                width: asset.pixelWidth,
                height: asset.pixelHeight
            )
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    print("⚠️ 获取图片失败: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                } else if let image = image {
                    print("✅ 成功获取图片，尺寸: \(image.size.width) x \(image.size.height)")
                    continuation.resume(returning: image)
                } else {
                    print("⚠️ 未知原因导致图片获取失败")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// 检查最近一张照片是否是截图（通过创建时间判断）
    /// - Parameter within: 在多少秒内创建的照片（默认5秒）
    func isLatestPhotoRecent(within seconds: TimeInterval = 5.0) async -> Bool {
        // 检查权限
        let hasPermission = await requestPhotoLibraryPermission()
        guard hasPermission else { return false }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let asset = fetchResult.firstObject,
              let creationDate = asset.creationDate else {
            return false
        }
        
        let timeDiff = Date().timeIntervalSince(creationDate)
        let isRecent = timeDiff <= seconds
        
        print("📸 最近照片创建于 \(String(format: "%.1f", timeDiff)) 秒前，\(isRecent ? "是" : "不是")最近的截图")
        
        return isRecent
    }
}

