# 录音转写重构总结

## ✅ 已完成的工作

### 1. 创建了 OSSUploadService.swift
- 路径: `Matters/Utils/OSSUploadService.swift`
- 功能: 负责音频文件上传到阿里云 OSS
- 特性:
  - ✅ 支持上传进度回调
  - ✅ 自动设置 Content-Type
  - ✅ 支持删除临时文件
  - ✅ 详细的日志输出

### 2. 重构了 QwenASRService.swift
- 改进:
  - ❌ 删除了 Base64 编码逻辑（节省内存和时间）
  - ❌ 删除了音频压缩逻辑（不再需要）
  - ✅ 使用 OSS URL 方式调用 ASR API
  - ✅ 添加进度回调支持
  - ✅ 自动清理临时文件

### 3. 创建了配置文档
- `OSS_CONFIG.md`: 完整的 OSS 配置指南
- `Podfile`: CocoaPods 依赖配置

## 🔧 需要完成的步骤

### 方案A: 使用 Swift Package Manager（推荐）

由于 CocoaPods 有问题，建议使用 SPM：

1. **在 Xcode 中添加 OSS SDK**:
   - 打开项目：`Matters.xcodeproj`
   - File -> Add Package Dependencies
   - 搜索：`https://github.com/aliyun/aliyun-oss-ios-sdk`
   - 选择版本 2.10.19 或更新

2. **配置 OSS**:
   - 编辑 `Matters/Utils/OSSUploadService.swift`
   - 填入你的 OSS 配置（见下方）

3. **添加文件到项目**:
   - 在 Xcode 中右键 Utils 文件夹
   - Add Files to "Matters"
   - 选择 `OSSUploadService.swift`

### 方案B: 手动集成 OSS SDK

1. **下载 SDK**:
   ```bash
   cd ~/Downloads
   wget https://github.com/aliyun/aliyun-oss-ios-sdk/archive/refs/tags/release_2.10.19.zip
   unzip release_2.10.19.zip
   ```

2. **添加到项目**:
   - 将 `AliyunOSSiOS.framework` 拖入 Xcode 项目
   - Targets -> Matters -> General -> Frameworks, Libraries, and Embedded Content
   - 添加框架并选择 "Embed & Sign"

## 📝 必须配置的参数

编辑 `Matters/Utils/OSSUploadService.swift` 第 7-10 行：

```swift
private static let endpoint = "https://oss-cn-beijing.aliyuncs.com"  // 你的OSS地域
private static let accessKeyId = "填入你的AccessKeyId"  
private static let accessKeySecret = "填入你的AccessKeySecret"  
private static let bucketName = "matters-audio"  // 你的Bucket名称
```

### 如何获取这些参数：

1. **创建 OSS Bucket**:
   - 登录 https://oss.console.aliyun.com/
   - 创建 Bucket，名称如 `matters-audio`
   - 地域选择「华北2（北京）」
   - 读写权限设置为「公共读」

2. **获取 AccessKey**:
   - 方式1（推荐）：使用 RAM 子用户
     - 进入 https://ram.console.aliyun.com/
     - 创建用户，勾选「编程访问」
     - 授予 `AliyunOSSFullAccess` 权限
     - 保存 AccessKey ID 和 Secret
   
   - 方式2（快速测试）：使用主账号
     - 进入 https://usercenter.console.aliyun.com/
     - AccessKey 管理 -> 创建 AccessKey

## 🎯 使用流程

重构后的流程：

```
用户录音 
  ↓
本地保存 WAV/M4A 文件
  ↓  
上传到阿里云 OSS (OSSUploadService)
  ↓
获得公网 URL
  ↓
传递 URL 给 ASR API (QwenASRService)
  ↓
识别完成后自动删除 OSS 文件
```

## 优势对比

| 特性 | 旧方案 (Base64) | 新方案 (OSS URL) |
|------|----------------|------------------|
| 文件大小限制 | ~50MB | 无限制 |
| 需要压缩 | ✅ 是 | ❌ 否 |
| 内存占用 | 高（Base64编码） | 低 |
| 上传速度 | 慢 | 快 |
| 请求体大小 | 大（+33%） | 小 |
| 成功率 | 低（大文件易失败） | 高 |

## 💰 成本估算

- 存储费用：临时文件，可忽略
- 流量费用：约 0.5元/GB
- 请求费用：0.01元/万次

**预估**：每天 100 个音频（10MB/个）= 约 15-20 元/月

## 🐛 故障排查

### 问题1: 找不到 AliyunOSSiOS 模块
- **解决**: 确认已正确添加 OSS SDK（通过 SPM 或手动）

### 问题2: 上传失败 - InvalidAccessKeyId  
- **解决**: 检查 AccessKey 是否正确填写

### 问题3: 上传失败 - NoSuchBucket
- **解决**: 检查 Bucket 名称和 endpoint 地域是否匹配

### 问题4: ASR 无法访问 URL
- **解决**: 确认 Bucket 权限设置为「公共读」

## 📱 测试步骤

1. 配置好 OSS 参数
2. 构建并运行 App
3. 录制一段音频
4. 点击转写按钮
5. 观察控制台输出：
   - ☁️ OSS 上传进度
   - ✅ OSS 上传成功
   - 📤 ASR 识别请求
   - ✅ 识别成功
   - 🗑️ 删除临时文件

## 🔐 安全建议

⚠️ **重要**：当前密钥硬编码在客户端仅适合测试！

生产环境应该：
1. 使用 STS 临时凭证
2. 通过你的后端服务器获取临时凭证
3. 限制临时凭证的权限和有效期

## 📚 相关文档

- [阿里云 OSS iOS SDK](https://help.aliyun.com/zh/oss/developer-reference/ios-sdk-overview)
- [通义千问 ASR API](https://help.aliyun.com/zh/model-studio/qwen-speech-recognition)
- [OSS 简单上传](https://help.aliyun.com/zh/oss/user-guide/simple-upload)

## ✨ 下一步优化（可选）

- [ ] 添加上传失败重试机制
- [ ] 使用 STS 临时凭证
- [ ] 添加音频文件格式转换（统一为 MP3）
- [ ] 支持断点续传（大文件）
- [ ] 添加上传队列管理

