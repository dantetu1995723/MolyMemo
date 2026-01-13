import Foundation

/// 日程提醒时间解析（与后端 reminder_time 字段兼容）
///
/// 支持两类：
/// - 相对偏移码：`-15m` / `-1h` / `-2d` / `-1w`（相对 `startTime`）
/// - 绝对时间：ISO8601（如 `2026-01-06T09:50:00` / `2026-01-06T09:50:00Z` / 含毫秒）
enum ScheduleReminderTime {
    /// 计算“实际触发时间”
    /// - Returns: reminder 的绝对触发时间；无法解析则返回 nil
    static func resolveReminderDate(startTime: Date, reminderTimeRaw: String) -> Date? {
        let raw = reminderTimeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        
        // 1) 绝对时间：ISO8601
        if let abs = parseAbsoluteDate(raw) {
            return abs
        }
        
        // 2) 相对时间：-15m / -1h / -2d / -1w（也容忍 +15m 等）
        if let offset = parseRelativeOffsetSeconds(raw) {
            return startTime.addingTimeInterval(offset)
        }
        
        return nil
    }
    
    /// 解析 ISO8601 绝对时间（带/不带时区、带/不带毫秒）
    static func parseAbsoluteDate(_ raw: String) -> Date? {
        // ISO8601（带时区）
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        
        let isoNoFraction = ISO8601DateFormatter()
        isoNoFraction.formatOptions = [.withInternetDateTime]
        if let d = isoNoFraction.date(from: raw) { return d }
        
        // 常见无时区格式：2026-01-06T09:50:00
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = df.date(from: raw) { return d }
        
        return nil
    }
    
    private static func parseRelativeOffsetSeconds(_ raw: String) -> TimeInterval? {
        // 形如：-15m / +2h / 10m
        // - 后端常见是负号：表示“开始前”
        // - 这里也兼容正号/无符号
        let pattern = #"^([+-]?)(\d+)([mhdw])$"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let m = re.firstMatch(in: raw, range: range) else { return nil }
        
        func group(_ idx: Int) -> String? {
            guard idx < m.numberOfRanges else { return nil }
            let r = m.range(at: idx)
            guard r.location != NSNotFound, let rr = Range(r, in: raw) else { return nil }
            return String(raw[rr])
        }
        
        let signStr = group(1) ?? ""
        let nStr = group(2) ?? ""
        let unit = group(3) ?? ""
        // 允许 0m/0h：表示“开始时提醒”
        guard let n = Double(nStr), n >= 0 else { return nil }
        
        let secondsPerUnit: Double
        switch unit {
        case "m": secondsPerUnit = 60
        case "h": secondsPerUnit = 60 * 60
        case "d": secondsPerUnit = 24 * 60 * 60
        case "w": secondsPerUnit = 7 * 24 * 60 * 60
        default: return nil
        }
        
        let sign: Double = (signStr == "-") ? -1 : 1
        return sign * n * secondsPerUnit
    }
}

