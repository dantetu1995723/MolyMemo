import Foundation

/// 用 background URLSession 把录音上传到后端，保证 App 在后台/被系统挂起时也能继续上传。
final class MeetingMinutesBackgroundUploader: NSObject {
    static let shared = MeetingMinutesBackgroundUploader()

    static let backgroundSessionIdentifier = "com.molymemo.app.meetingminutes.upload"

    /// 由 UIApplicationDelegate 的 `handleEventsForBackgroundURLSession` 注入
    var backgroundSessionCompletionHandler: (() -> Void)?

    private let generateEndpoint = "/api/v1/meeting-minutes/generate"

    private struct TaskInfo: Codable {
        let bodyPath: String
        let audioPath: String
        let duration: Double
        let createdAt: Double
    }

    private let taskInfoDefaultsKey = "meetingMinutes.bgUpload.taskInfoByTaskId"
    private let lock = NSLock()
    private var responseDataByTaskId: [Int: Data] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        _ = session
    }

    func enqueueGenerateMeetingMinutes(
        originalAudioFileURL: URL,
        duration: TimeInterval,
        uploadToChat: Bool,
        updateMeetingList: Bool
    ) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let persistedAudioURL = try RecordingFileStore.persistToAppGroup(originalURL: originalAudioFileURL)
                let (bodyURL, boundary) = try self.buildMultipartBodyFile(audioFileURL: persistedAudioURL)
                let request = try self.makeGenerateRequest(boundary: boundary)

                let task = self.session.uploadTask(with: request, fromFile: bodyURL)
                self.saveTaskInfo(taskId: task.taskIdentifier, info: TaskInfo(
                    bodyPath: bodyURL.path,
                    audioPath: persistedAudioURL.path,
                    duration: duration,
                    createdAt: Date().timeIntervalSince1970
                ))
                task.resume()
            } catch {
                #if DEBUG
                AppGroupDebugLog.append("[MeetingMinutesBGUpload] enqueue failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Request/Body

    private func resolvedBaseURL() throws -> String {
        let candidate = BackendChatConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = candidate.isEmpty ? BackendChatConfig.defaultBaseURL : candidate
        return BackendChatConfig.normalizeBaseURL(base)
    }

    private func currentSessionId() -> String? {
        let fromConfig = BackendChatConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromConfig.isEmpty { return fromConfig }
        let fromDefaults = (UserDefaults.standard.string(forKey: "yuanyuan_auth_session_id") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fromDefaults.isEmpty ? nil : fromDefaults
    }

    private func makeGenerateRequest(boundary: String) throws -> URLRequest {
        let base = try resolvedBaseURL()
        guard let url = URL(string: "\(base)\(generateEndpoint)") else {
            throw NSError(domain: "MeetingMinutesBGUpload", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的服务器地址"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let sessionId = currentSessionId(), !sessionId.isEmpty else {
            throw NSError(domain: "MeetingMinutesBGUpload", code: 2, userInfo: [NSLocalizedDescriptionKey: "缺少登录态（X-Session-Id）"])
        }
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")

        return request
    }

    private func buildMultipartBodyFile(audioFileURL: URL) throws -> (bodyURL: URL, boundary: String) {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw NSError(domain: "MeetingMinutesBGUpload", code: 3, userInfo: [NSLocalizedDescriptionKey: "音频文件不存在"])
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let folder = try RecordingFileStore.appGroupRecordingsFolder()
        let bodyURL = folder.appendingPathComponent("upload_body_\(UUID().uuidString).tmp")

        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: bodyURL)
        defer { try? out.close() }

        func write(_ s: String) throws {
            guard let d = s.data(using: .utf8) else { return }
            try out.write(contentsOf: d)
        }

        let fileName = audioFileURL.lastPathComponent
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"audio_file\"; filename=\"\(fileName)\"\r\n")
        try write("Content-Type: audio/m4a\r\n\r\n")

        let input = try FileHandle(forReadingFrom: audioFileURL)
        defer { try? input.close() }

        while true {
            let chunk = try input.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try out.write(contentsOf: chunk)
        }

        try write("\r\n")

        // enable_translation=false（与现有 MeetingMinutesService 默认一致）
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"enable_translation\"\r\n\r\n")
        try write("false\r\n")

        try write("--\(boundary)--\r\n")

        return (bodyURL, boundary)
    }

    // MARK: - Persistence

    private func loadTaskInfoMap() -> [String: TaskInfo] {
        guard let defaults = UserDefaults(suiteName: AppIdentifiers.appGroupId),
              let data = defaults.data(forKey: taskInfoDefaultsKey),
              let map = try? JSONDecoder().decode([String: TaskInfo].self, from: data)
        else { return [:] }
        return map
    }

    private func saveTaskInfo(taskId: Int, info: TaskInfo) {
        lock.lock(); defer { lock.unlock() }
        var map = loadTaskInfoMap()
        map[String(taskId)] = info
        if let defaults = UserDefaults(suiteName: AppIdentifiers.appGroupId),
           let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: taskInfoDefaultsKey)
            defaults.synchronize()
        }
    }

    private func removeTaskInfo(taskId: Int) -> TaskInfo? {
        lock.lock(); defer { lock.unlock() }
        var map = loadTaskInfoMap()
        let info = map.removeValue(forKey: String(taskId))
        if let defaults = UserDefaults(suiteName: AppIdentifiers.appGroupId),
           let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: taskInfoDefaultsKey)
            defaults.synchronize()
        }
        return info
    }
}

// MARK: - URLSession delegates

extension MeetingMinutesBackgroundUploader: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        responseDataByTaskId[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskId = task.taskIdentifier
        let info = removeTaskInfo(taskId: taskId)

        // 清理 body 临时文件（音频文件留在 App Group 供后续排查/重试；可后续加清理策略）
        if let p = info?.bodyPath, !p.isEmpty {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: p))
        }

        lock.lock()
        let data = responseDataByTaskId.removeValue(forKey: taskId)
        lock.unlock()

        if let error {
            #if DEBUG
            AppGroupDebugLog.append("[MeetingMinutesBGUpload] task=\(taskId) failed: \(error.localizedDescription)")
            #endif
            return
        }

        if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            #if DEBUG
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            AppGroupDebugLog.append("[MeetingMinutesBGUpload] task=\(taskId) HTTP \(http.statusCode) raw=\(raw)")
            #endif
            return
        }

        #if DEBUG
        AppGroupDebugLog.append("[MeetingMinutesBGUpload] task=\(taskId) completed")
        #endif
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let handler = self.backgroundSessionCompletionHandler
            self.backgroundSessionCompletionHandler = nil
            handler?()
        }
    }
}

