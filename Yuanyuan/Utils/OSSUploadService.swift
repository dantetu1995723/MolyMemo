import Foundation
import AliyunOSSiOS

/// 阿里云OSS上传服务
class OSSUploadService {
    // OSS配置 - 从UserDefaults读取用户配置的凭证
    private static let endpoint = "https://oss-cn-beijing.aliyuncs.com"  // 华北2（北京）
    
    // 从UserDefaults读取用户配置的凭证
    private static var accessKeyId: String {
        UserDefaults.standard.string(forKey: "oss_access_key_id") ?? ""
    }
    
    private static var accessKeySecret: String {
        UserDefaults.standard.string(forKey: "oss_access_key_secret") ?? ""
    }
    
    private static var bucketName: String {
        UserDefaults.standard.string(forKey: "oss_bucket_name") ?? "yuanyuan-recordmeeting"
    }
    
    // 检查是否已配置凭证
    static var isConfigured: Bool {
        !accessKeyId.isEmpty && !accessKeySecret.isEmpty && !bucketName.isEmpty
    }
    
    // 保存用户配置的凭证
    static func saveCredentials(accessKeyId: String, accessKeySecret: String, bucketName: String) {
        UserDefaults.standard.set(accessKeyId, forKey: "oss_access_key_id")
        UserDefaults.standard.set(accessKeySecret, forKey: "oss_access_key_secret")
        UserDefaults.standard.set(bucketName, forKey: "oss_bucket_name")
        // 清除旧的客户端，强制重新初始化
        client = nil
    }
    
    // 清除凭证
    static func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: "oss_access_key_id")
        UserDefaults.standard.removeObject(forKey: "oss_access_key_secret")
        UserDefaults.standard.removeObject(forKey: "oss_bucket_name")
        client = nil
    }
    
    private static var client: OSSClient?
    
    /// 初始化OSS客户端
    private static func getClient() throws -> OSSClient {
        if let existingClient = client {
            return existingClient
        }
        
        guard isConfigured else {
            throw OSSError.configurationMissing
        }
        
        print("🔧 [OSS] 初始化客户端")
        print("   Endpoint: \(endpoint)")
        print("   Bucket: \(bucketName)")
        print("   AccessKeyId: \(accessKeyId)")
        print("   AccessKeySecret: \(accessKeySecret.prefix(8))***（已隐藏）")
        
        // OSSPlainTextAKSKPairCredentialProvider 已废弃。这里用 CustomSigner 来做同等 AK/SK 签名，避免废弃警告且不改变现有配置方式。
        // 说明：此签名方式等价于 Authorization: "OSS <AccessKeyId>:<Signature>"（Signature = Base64(HMAC-SHA1(secret, content))）
        guard let credentialProvider = OSSCustomSignerCredentialProvider(implementedSigner: { content, error in
            guard !accessKeyId.isEmpty, !accessKeySecret.isEmpty else {
                error?.pointee = NSError(
                    domain: "OSSUploadService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "OSS AccessKey 配置缺失"]
                )
                return ""
            }
            guard let signature = OSSUtil.calBase64Sha1(withData: content, withSecret: accessKeySecret) else {
                error?.pointee = NSError(
                    domain: "OSSUploadService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "OSS 签名失败"]
                )
                return ""
            }
            return "OSS \(accessKeyId):\(signature)"
        }) else {
            throw OSSError.configurationMissing
        }
        
        let clientConfig = OSSClientConfiguration()
        clientConfig.maxRetryCount = 3
        clientConfig.timeoutIntervalForRequest = 30
        clientConfig.timeoutIntervalForResource = 24 * 60 * 60  // 24小时
        
        let newClient = OSSClient(endpoint: endpoint, credentialProvider: credentialProvider, clientConfiguration: clientConfig)
        client = newClient
        return newClient
    }
    
    /// 上传音频文件到OSS
    /// - Parameters:
    ///   - fileURL: 本地音频文件URL
    ///   - progressHandler: 上传进度回调
    /// - Returns: 上传后的文件URL
    static func uploadAudioFile(fileURL: URL, progressHandler: ((Float) -> Void)? = nil) async throws -> String {
        print("☁️ [OSS] 开始上传音频到阿里云OSS")
        print("   本地文件: \(fileURL.lastPathComponent)")
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("❌ [OSS] 文件不存在: \(fileURL.path)")
            throw OSSError.fileNotFound
        }
        
        // 获取文件大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 ?? 0
        let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0
        print("📏 [OSS] 文件大小: \(String(format: "%.2f", fileSizeMB)) MB")
        
        // 生成唯一的对象键（文件名）
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileExtension = fileURL.pathExtension
        let objectKey = "audio/\(timestamp)_\(UUID().uuidString).\(fileExtension)"
        
        print("🔑 [OSS] 对象键: \(objectKey)")
        
        // 创建上传请求
        let putRequest = OSSPutObjectRequest()
        putRequest.bucketName = bucketName
        putRequest.objectKey = objectKey
        putRequest.uploadingFileURL = fileURL
        
        // 设置Content-Type
        let mimeType = getMimeType(for: fileExtension)
        putRequest.contentType = mimeType
        print("📄 [OSS] Content-Type: \(mimeType)")
        
        // 设置进度回调
        if let handler = progressHandler {
            putRequest.uploadProgress = { bytesSent, totalBytesSent, totalBytesExpectedToSend in
                let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
                DispatchQueue.main.async {
                    handler(progress)
                }
            }
        }
        
        // 执行上传
        let client = try getClient()
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = client.putObject(putRequest)
            task.continue({ taskResult -> Any? in
                if let error = taskResult.error {
                    let nsError = error as NSError
                    print("❌ [OSS] 上传失败")
                    print("   错误描述: \(error.localizedDescription)")
                    print("   错误域: \(nsError.domain)")
                    print("   错误代码: \(nsError.code)")
                    print("   详细信息: \(nsError.userInfo)")
                    
                    // 检查是否是 403 错误
                    if let httpResponse = nsError.userInfo["HttpResponseCode"] as? Int {
                        print("   HTTP状态码: \(httpResponse)")
                    }
                    if let responseBody = nsError.userInfo["ResponseBody"] as? String {
                        print("   响应内容: \(responseBody)")
                    }
                    
                    continuation.resume(throwing: OSSError.uploadFailed(error.localizedDescription))
                } else {
                    // 构建文件的公网URL
                    let fileURL = "https://\(bucketName).\(endpoint.replacingOccurrences(of: "https://", with: ""))/\(objectKey)"
                    print("✅ [OSS] 上传成功！")
                    print("   URL: \(fileURL)")
                    continuation.resume(returning: fileURL)
                }
                return nil
            })
        }
    }
    
    /// 删除OSS上的文件
    /// - Parameter objectKey: 对象键
    static func deleteFile(objectKey: String) async throws {
        print("🗑️ [OSS] 删除文件: \(objectKey)")
        
        let deleteRequest = OSSDeleteObjectRequest()
        deleteRequest.bucketName = bucketName
        deleteRequest.objectKey = objectKey
        
        let client = try getClient()
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = client.deleteObject(deleteRequest)
            task.continue({ taskResult -> Any? in
                if let error = taskResult.error {
                    print("❌ [OSS] 删除失败: \(error.localizedDescription)")
                    continuation.resume(throwing: OSSError.deleteFailed(error.localizedDescription))
                } else {
                    print("✅ [OSS] 删除成功")
                    continuation.resume()
                }
                return nil
            })
        }
    }
    
    /// 从URL提取对象键
    /// - Parameter urlString: OSS文件URL
    /// - Returns: 对象键
    static func extractObjectKey(from urlString: String) -> String? {
        // URL格式: https://bucket-name.oss-cn-beijing.aliyuncs.com/audio/xxx.wav
        guard let url = URL(string: urlString),
              let host = url.host,
              host.contains(bucketName) else {
            return nil
        }
        
        // 移除开头的 "/"
        let objectKey = String(url.path.dropFirst())
        return objectKey.isEmpty ? nil : objectKey
    }
    
    /// 根据文件扩展名获取MIME类型
    private static func getMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "mp4":
            return "audio/mp4"
        default:
            return "application/octet-stream"
        }
    }
}

/// OSS错误类型
enum OSSError: LocalizedError {
    case fileNotFound
    case uploadFailed(String)
    case deleteFailed(String)
    case invalidURL
    case configurationMissing
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "文件不存在"
        case .uploadFailed(let message):
            return "上传失败: \(message)"
        case .deleteFailed(let message):
            return "删除失败: \(message)"
        case .invalidURL:
            return "无效的URL"
        case .configurationMissing:
            return "OSS配置缺失，请在设置中配置AccessKey和Bucket信息"
        }
    }
}

