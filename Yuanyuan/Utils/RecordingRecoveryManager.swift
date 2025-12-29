import Foundation
import AVFoundation
import SwiftData

struct RecordingRecoveryManager {
    static func recoverOrphanedRecordings(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Meeting>()
        let existingMeetings = (try? modelContext.fetch(descriptor)) ?? []
        let existingPaths = Set(existingMeetings.compactMap { $0.audioFilePath })
        
        // 获取最近一次会议的创建时间，避免立即恢复刚保存的录音
        let recentMeetingThreshold = Date().addingTimeInterval(-5) // 5秒内创建的不恢复
        
        var didInsert = false
        for folder in candidateFolders() {
            let fileURLs = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            
            for fileURL in fileURLs where ["wav", "m4a"].contains(fileURL.pathExtension.lowercased()) {
                guard !existingPaths.contains(fileURL.path) else { continue }
                
                let creationDate = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                
                // 跳过刚创建的文件（可能是正在保存的）
                if creationDate > recentMeetingThreshold {
                    print("⏭️ 跳过最近创建的文件: \(fileURL.lastPathComponent)")
                    continue
                }
                
                let duration = await audioDuration(for: fileURL)
                
                // 跳过时长为0的文件（可能是损坏的）
                if duration <= 0 {
                    print("⚠️ 跳过无效录音文件（时长为0）: \(fileURL.lastPathComponent)")
                    continue
                }
                
                let meeting = Meeting(
                    title: defaultTitle(for: creationDate),
                    content: "",
                    audioFilePath: fileURL.path,
                    createdAt: creationDate,
                    duration: duration
                )
                
                modelContext.insert(meeting)
                didInsert = true
                print("🛠️ 已恢复孤立录音: \(fileURL.lastPathComponent) (时长: \(Int(duration))秒)")
            }
        }
        
        if didInsert {
            do {
                try modelContext.save()
                print("✅ 孤立录音恢复完成")
            } catch {
                print("❌ 保存恢复录音失败: \(error)")
            }
        } else {
            print("   没有需要恢复的孤立录音")
        }
    }
    
    private static func audioDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let durationTime = try? await asset.load(.duration) else {
            print("⚠️ 获取录音时长失败，返回0秒")
            return 0
        }

        let seconds = CMTimeGetSeconds(durationTime)
        if seconds.isNaN || seconds.isInfinite {
            return 0
        }
        return max(0, seconds)
    }
    
    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return "Moly录音 - \(formatter.string(from: date))"
    }
    
    private static func candidateFolders() -> [URL] {
        let recordingsURL = ensureRecordingsFolder()
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // 新目录（临时）优先，但仍兼容扫描旧的 Documents 目录以清理/恢复历史残留。
        return [recordingsURL, documentsURL]
    }
    
    private static func ensureRecordingsFolder() -> URL {
        // 统一后端接入：录音文件改用临时目录（不做持久化存储）。
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingRecordings", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        return folderURL
    }
}


