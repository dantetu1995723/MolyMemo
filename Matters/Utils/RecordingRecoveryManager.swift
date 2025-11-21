import Foundation
import AVFoundation
import SwiftData

struct RecordingRecoveryManager {
    static func recoverOrphanedRecordings(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Meeting>()
        let existingMeetings = (try? modelContext.fetch(descriptor)) ?? []
        let existingPaths = Set(existingMeetings.compactMap { $0.audioFilePath })
        
        var didInsert = false
        for folder in candidateFolders() {
            let fileURLs = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            
            for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "wav" {
                guard !existingPaths.contains(fileURL.path) else { continue }
                
                let creationDate = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let duration = audioDuration(for: fileURL)
                
                let meeting = Meeting(
                    title: defaultTitle(for: creationDate),
                    content: "",
                    audioFilePath: fileURL.path,
                    createdAt: creationDate,
                    duration: duration
                )
                
                modelContext.insert(meeting)
                didInsert = true
                print("🛠️ 已恢复孤立录音: \(fileURL.lastPathComponent)")
            }
        }
        
        if didInsert {
            do {
                try modelContext.save()
                print("✅ 孤立录音恢复完成")
            } catch {
                print("❌ 保存恢复录音失败: \(error)")
            }
        }
    }
    
    private static func audioDuration(for url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isNaN || seconds.isInfinite {
            return 0
        }
        return max(0, seconds)
    }
    
    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return "会议录音 - \(formatter.string(from: date))"
    }
    
    private static func candidateFolders() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsURL = ensureRecordingsFolder()
        
        if recordingsURL == documentsURL {
            return [recordingsURL]
        }
        
        return [recordingsURL, documentsURL]
    }
    
    private static func ensureRecordingsFolder() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsURL.appendingPathComponent("MeetingRecordings", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        return folderURL
    }
}


