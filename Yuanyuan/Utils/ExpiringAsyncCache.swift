import Foundation

/// 简单的“过期缓存 + 请求去重（in-flight）”
/// - 目标：让页面进入时可以“先用缓存秒开”，并避免短时间内重复 GET
actor ExpiringAsyncCache<Key: Hashable, Value> {
    struct Snapshot {
        let value: Value
        let isFresh: Bool
        let expiry: Date
    }
    
    private struct Entry {
        var value: Value
        var expiry: Date
    }
    
    private var storage: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Value, Error>] = [:]
    
    func peek(_ key: Key, now: Date = Date()) -> Snapshot? {
        guard let e = storage[key] else { return nil }
        return Snapshot(value: e.value, isFresh: e.expiry > now, expiry: e.expiry)
    }
    
    func getFresh(_ key: Key, now: Date = Date()) -> Value? {
        guard let e = storage[key] else { return nil }
        return e.expiry > now ? e.value : nil
    }
    
    func set(_ key: Key, value: Value, ttl: TimeInterval, now: Date = Date()) {
        storage[key] = Entry(value: value, expiry: now.addingTimeInterval(ttl))
    }
    
    /// 失效某个 key 的缓存。
    /// - Parameter cancelInFlight: 是否取消同 key 的进行中请求。默认 true（保持原语义）。
    func invalidate(_ key: Key, cancelInFlight: Bool = true) {
        storage.removeValue(forKey: key)
        if cancelInFlight {
            inFlight[key]?.cancel()
            inFlight.removeValue(forKey: key)
        }
        // cancelInFlight=false：保留 inFlight，让并发强刷复用同一请求，避免重复 GET
    }
    
    /// 失效全部缓存。
    /// - Parameter cancelInFlight: 是否取消全部进行中请求。默认 true（保持原语义）。
    func invalidateAll(cancelInFlight: Bool = true) {
        storage.removeAll()
        if cancelInFlight {
            for (_, t) in inFlight { t.cancel() }
            inFlight.removeAll()
        }
        // cancelInFlight=false：保留 inFlight，让调用方继续复用正在进行的请求
    }
    
    /// 只在缓存不 fresh 时才会触发 fetch，并对同 key 的并发 fetch 做合并。
    func getOrFetch(
        _ key: Key,
        ttl: TimeInterval,
        now: Date = Date(),
        fetcher: @escaping () async throws -> Value
    ) async throws -> Value {
        if let v = getFresh(key, now: now) { return v }
        if let t = inFlight[key] { return try await t.value }
        
        let task = Task<Value, Error> {
            try await fetcher()
        }
        inFlight[key] = task
        
        do {
            let v = try await task.value
            inFlight.removeValue(forKey: key)
            set(key, value: v, ttl: ttl, now: now)
            return v
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }
}


