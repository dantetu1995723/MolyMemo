import Foundation
import SwiftData
import UIKit

/// 图片识别错误日志 - 用于收集和分析识别错误，持续改进模型
@Model
final class ClassificationError {
    /// 唯一标识
    var id: UUID
    
    /// 错误发生时间
    var timestamp: Date
    
    /// 图片数据（JPEG格式）
    @Attribute(.externalStorage)
    var imageData: Data
    
    /// AI错误识别的分类
    var wrongCategory: String
    
    /// 用户修正的正确分类
    var correctCategory: String
    
    /// 识别置信度（如果有）
    var confidence: Double?
    
    /// 额外备注
    var notes: String?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        imageData: Data,
        wrongCategory: String,
        correctCategory: String,
        confidence: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.imageData = imageData
        self.wrongCategory = wrongCategory
        self.correctCategory = correctCategory
        self.confidence = confidence
        self.notes = notes
    }
    
    /// 便捷方法：从图片创建错误记录
    static func from(
        image: UIImage,
        wrongCategory: String,
        correctCategory: String,
        confidence: Double? = nil,
        notes: String? = nil
    ) -> ClassificationError? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("⚠️ 无法将图片转换为数据")
            return nil
        }
        
        return ClassificationError(
            imageData: imageData,
            wrongCategory: wrongCategory,
            correctCategory: correctCategory,
            confidence: confidence,
            notes: notes
        )
    }
}

/// 错误日志管理器
struct ClassificationErrorManager {
    /// 保存识别错误记录
    static func logError(
        image: UIImage,
        wrongCategory: String,
        correctCategory: String,
        confidence: Double? = nil,
        modelContext: ModelContext
    ) {
        guard let errorLog = ClassificationError.from(
            image: image,
            wrongCategory: wrongCategory,
            correctCategory: correctCategory,
            confidence: confidence
        ) else {
            print("⚠️ 无法创建错误日志")
            return
        }
        
        modelContext.insert(errorLog)
        
        do {
            try modelContext.save()
            print("✅ 识别错误已记录: \(wrongCategory) → \(correctCategory)")
        } catch {
            print("⚠️ 保存错误日志失败: \(error)")
        }
    }
    
    /// 获取所有错误记录（用于分析）
    static func fetchAllErrors(modelContext: ModelContext) -> [ClassificationError] {
        let descriptor = FetchDescriptor<ClassificationError>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("⚠️ 获取错误日志失败: \(error)")
            return []
        }
    }
    
    /// 获取错误统计
    static func getErrorStats(modelContext: ModelContext) -> [String: Int] {
        let errors = fetchAllErrors(modelContext: modelContext)
        
        var stats: [String: Int] = [:]
        for error in errors {
            let key = "\(error.wrongCategory) → \(error.correctCategory)"
            stats[key, default: 0] += 1
        }
        
        return stats
    }
    
    /// 清除旧的错误记录（保留最近30天）
    static func cleanupOldErrors(modelContext: ModelContext, daysToKeep: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date()) ?? Date()
        
        let descriptor = FetchDescriptor<ClassificationError>(
            predicate: #Predicate<ClassificationError> { error in
                error.timestamp < cutoffDate
            }
        )
        
        do {
            let oldErrors = try modelContext.fetch(descriptor)
            for error in oldErrors {
                modelContext.delete(error)
            }
            try modelContext.save()
            print("✅ 已清理 \(oldErrors.count) 条旧错误记录")
        } catch {
            print("⚠️ 清理错误记录失败: \(error)")
        }
    }
}

