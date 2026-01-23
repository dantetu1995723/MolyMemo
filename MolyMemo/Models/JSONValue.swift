import Foundation

/// 轻量 JSON 值：用于兼容后端字段可能是 String / Object / Array / Number / Bool / Null 的情况。
/// - Note: 这里不引入第三方依赖，避免把事情搞复杂。
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:
            try c.encodeNil()
        case let .bool(v):
            try c.encode(v)
        case let .number(v):
            try c.encode(v)
        case let .string(v):
            try c.encode(v)
        case let .object(v):
            try c.encode(v)
        case let .array(v):
            try c.encode(v)
        }
    }

    /// 便于 UI 判断“有没有绑定”：对象/数组/数字/bool 视为有值；字符串按去空格判断；null 视为无值。
    var hasMeaningfulValue: Bool {
        switch self {
        case .null:
            return false
        case let .string(s):
            return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .object, .array, .number, .bool:
            return true
        }
    }

    /// 仅用于日志/展示：把 JSONValue 转成紧凑 JSON 字符串（失败则返回 nil）。
    var compactJSONString: String? {
        let encoder = JSONEncoder()
        if #available(iOS 11.0, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

