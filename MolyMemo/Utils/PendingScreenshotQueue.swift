import Foundation
import UIKit

/// AppIntent -> 主App 的“待发送截图”队列（App Group 文件队列）。
/// 目的：避免依赖 App Group UserDefaults（真机上可能出现 CFPreferences Container:(null) 导致读写失效）。
enum PendingScreenshotQueue {
    private static let dirName = "pending_screenshots"
    private static let metaExt = "json"
    private static let defaultImageExt = "img"

    private struct PendingMeta: Codable {
        /// App Group 内缩略图相对路径（例如 screenshot_thumbnails/thumb_xxx.jpg）
        var thumbnailRelativePath: String?
        /// 毫秒时间戳（用于 debug/追踪，不影响排序）
        var createdAtMs: Int?
    }

    static func appGroupURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroupId)
    }

    static func directoryURL() -> URL? {
        appGroupURL()?.appendingPathComponent(dirName, isDirectory: true)
    }

    /// 写入一条待发送截图（jpg），返回相对路径（相对 App Group 根目录）。
    static func enqueue(image: UIImage) -> String? {
        enqueue(image: image, thumbnailRelativePath: nil)
    }

    /// 写入一条待发送截图（jpg）+ 元数据（json），返回图片相对路径（相对 App Group 根目录）。
    static func enqueue(image: UIImage, thumbnailRelativePath: String?) -> String? {
        guard let dir = directoryURL() else { return nil }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("PendingScreenshotQueue mkdir failed: \(error)")
            #endif
            return nil
        }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let name = "pending_\(ts)_\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(name)

        // 性能关键点：截图往往分辨率很大，直接 jpeg 压缩会比较耗时（尤其是第一张截图唤醒主App开始网络发送时）。
        // 这里先把待发送截图缩放到合理上限（与后端发送时的 maxSize 对齐），显著降低“连续截图第二张变慢”的概率。
        let prepared = resizedForQueue(image, maxPixel: 2048)
        guard let data = prepared.jpegData(compressionQuality: 0.88) else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("PendingScreenshotQueue write failed: \(error)")
            #endif
            return nil
        }

        #if DEBUG
        AppGroupDebugLog.append("PendingScreenshotQueue wrote bytes=\(data.count) file=\(name)")
        #endif

        let rel = "\(dirName)/\(name)"

        // 写 meta（失败不影响主流程）
        let meta = PendingMeta(thumbnailRelativePath: thumbnailRelativePath, createdAtMs: ts)
        writeMeta(meta, forImageRelativePath: rel)

        return rel
    }

    /// 极致快路径：直接把快捷指令传入的原始图片 bytes 落盘（不解码、不重压缩）
    /// - 目标：让快捷指令动作“秒过”
    /// - fileExt: 可用 screenshot.filename 的扩展名；为空则用 .img
    static func enqueue(rawData: Data, fileExt: String? = nil, thumbnailRelativePath: String? = nil) -> String? {
        guard !rawData.isEmpty else { return nil }
        guard let dir = directoryURL() else { return nil }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("PendingScreenshotQueue mkdir failed: \(error)")
            #endif
            return nil
        }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let ext0 = (fileExt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ext = ext0.isEmpty ? defaultImageExt : ext0
        let name = "pending_\(ts)_\(UUID().uuidString).\(ext)"
        let url = dir.appendingPathComponent(name)

        // 纯写盘：不做 atomic（更快）；即使极端被打断，主App也会检测 decode 失败并丢弃该条。
        do {
            try rawData.write(to: url, options: [])
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("PendingScreenshotQueue raw write failed: \(error)")
            #endif
            return nil
        }

        let rel = "\(dirName)/\(name)"
        let meta = PendingMeta(thumbnailRelativePath: thumbnailRelativePath, createdAtMs: ts)
        writeMeta(meta, forImageRelativePath: rel)
        return rel
    }

    /// 列出当前队列（按文件名时间戳升序）。
    static func listPendingRelativePaths(limit: Int = 8) -> [String] {
        guard let dir = directoryURL() else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }

        let imgs = items
            // 只收图片文件：排除 meta json
            .filter { $0.hasPrefix("pending_") && !$0.hasSuffix(".\(metaExt)") }
            .sorted()
            .prefix(max(0, limit))

        return imgs.map { "\(dirName)/\($0)" }
    }

    static func loadImage(relativePath: String) -> UIImage? {
        guard let groupURL = appGroupURL() else { return nil }
        let url = groupURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 读取该 pending 图片对应的缩略图相对路径（若未写入 meta 则为 nil）
    static func thumbnailRelativePath(forPendingImageRelativePath relativePath: String) -> String? {
        loadMeta(forImageRelativePath: relativePath)?.thumbnailRelativePath
    }

    static func remove(relativePath: String) {
        guard let groupURL = appGroupURL() else { return }
        let url = groupURL.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)

        // 同时删除 meta（若存在）
        if let metaRel = metaRelativePath(forImageRelativePath: relativePath) {
            let metaURL = groupURL.appendingPathComponent(metaRel)
            try? FileManager.default.removeItem(at: metaURL)
        }
    }
}

// MARK: - Meta

private extension PendingScreenshotQueue {
    private static func resizedForQueue(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > 0 else { return image }
        let scale = min(1.0, maxPixel / maxSide)
        guard scale < 1.0 else { return image }

        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func metaRelativePath(forImageRelativePath imageRel: String) -> String? {
        let t = imageRel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        // 兼容任意扩展名：pending_xxx.jpg / pending_xxx.heic / pending_xxx.img ...
        let base = (t as NSString).deletingPathExtension
        guard !base.isEmpty else { return nil }
        return base + ".\(metaExt)"
    }

    private static func writeMeta(_ meta: PendingMeta, forImageRelativePath imageRel: String) {
        guard let groupURL = appGroupURL() else { return }
        guard let metaRel = metaRelativePath(forImageRelativePath: imageRel) else { return }
        let url = groupURL.appendingPathComponent(metaRel)
        do {
            let data = try JSONEncoder().encode(meta)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            AppGroupDebugLog.append("PendingScreenshotQueue meta write failed: \(error)")
            #endif
        }
    }

    private static func loadMeta(forImageRelativePath imageRel: String) -> PendingMeta? {
        guard let groupURL = appGroupURL() else { return nil }
        guard let metaRel = metaRelativePath(forImageRelativePath: imageRel) else { return nil }
        let url = groupURL.appendingPathComponent(metaRel)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PendingMeta.self, from: data)
    }
}


