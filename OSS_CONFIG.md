# 阿里云 OSS 配置说明

## 1. 开通阿里云 OSS 服务

### 1.1 创建 Bucket
1. 登录 [阿里云 OSS 控制台](https://oss.console.aliyun.com/)
2. 点击「创建 Bucket」
3. 配置：
   - **Bucket 名称**: `matters-audio` （或自定义）
   - **地域**: 选择「华北2（北京）」（与 ASR 服务同地域）
   - **存储类型**: 标准存储
   - **读写权限**: 公共读（允许 ASR 服务访问）
   - **服务端加密**: 关闭（可选）

### 1.2 获取访问密钥（AccessKey）

#### 方式一：使用 RAM 子用户（推荐）
1. 进入 [RAM 访问控制](https://ram.console.aliyun.com/)
2. 创建用户：
   - 点击「用户」->「创建用户」
   - 勾选「编程访问」
   - 保存 AccessKey ID 和 AccessKey Secret
3. 授予权限：
   - 为用户添加权限策略：`AliyunOSSFullAccess`

#### 方式二：使用主账号密钥（不推荐生产环境）
1. 进入[用户信息管理](https://usercenter.console.aliyun.com/)
2. 左侧菜单选择「AccessKey 管理」
3. 创建 AccessKey 并保存

## 2. 配置项目

### 2.1 安装 CocoaPods（如果还没安装）
```bash
sudo gem install cocoapods
```

### 2.2 创建 Podfile
在项目根目录创建 `Podfile`:

```ruby
platform :ios, '18.0'

target 'Matters' do
  use_frameworks!
  
  # 阿里云 OSS SDK
  pod 'AliyunOSSiOS', '~> 2.10.19'
  
end

target 'MattersWidget' do
  use_frameworks!
end
```

### 2.3 安装依赖
```bash
cd /Users/yansongtu/Documents/Matters
pod install
```

### 2.4 更新配置文件
编辑 `Matters/Utils/OSSUploadService.swift`，填入你的配置：

```swift
// OSS配置
private static let endpoint = "https://oss-cn-beijing.aliyuncs.com"  // 根据你的Bucket地域
private static let accessKeyId = "YOUR_ACCESS_KEY_ID"  // 替换为你的 AccessKey ID
private static let accessKeySecret = "YOUR_ACCESS_KEY_SECRET"  // 替换为你的 AccessKey Secret
private static let bucketName = "matters-audio"  // 替换为你的 Bucket 名称
```

## 3. Bucket 权限配置

### 3.1 设置跨域规则（CORS）
在 OSS 控制台 -> Bucket -> 权限管理 -> 跨域设置，添加规则：

- **来源**: `*`
- **允许 Methods**: GET, POST, PUT, DELETE, HEAD
- **允许 Headers**: `*`
- **暴露 Headers**: `*`
- **缓存时间**: 0

### 3.2 设置 Bucket 访问权限
- **读写权限**: 公共读（public-read）
- 这样 ASR 服务可以通过 URL 直接访问音频文件

## 4. 地域对照表

| 地域 | Endpoint |
|------|----------|
| 华北2（北京） | oss-cn-beijing.aliyuncs.com |
| 华东1（杭州） | oss-cn-hangzhou.aliyuncs.com |
| 华东2（上海） | oss-cn-shanghai.aliyuncs.com |
| 华南1（深圳） | oss-cn-shenzhen.aliyuncs.com |

**建议**: 使用北京地域，与通义千问 ASR 服务在同一地域，速度更快

## 5. 使用流程

1. 用户录音 -> 本地保存为文件
2. 上传到 OSS -> 获得公网 URL
3. 将 URL 传给 ASR API -> 进行语音识别
4. 识别完成后 -> 自动删除 OSS 临时文件

## 6. 安全建议

✅ **推荐**:
- 使用 RAM 子用户，最小权限原则
- 定期轮换 AccessKey
- 不要将密钥提交到代码仓库

❌ **不推荐**:
- 使用主账号 AccessKey
- 在客户端硬编码密钥（生产环境应该用 STS 临时凭证）

## 7. 成本估算

OSS 费用主要包括：
- **存储费用**: 标准存储 0.12元/GB/月
- **流量费用**: 外网流出流量 0.5元/GB
- **请求费用**: PUT 请求 0.01元/万次，GET 请求 0.01元/万次

**预估**: 如果每天上传100个音频（每个10MB），约：
- 存储: 临时存储，可忽略
- 流量: 约 1GB/天 = 15元/月
- 请求: 可忽略

**总计**: 约 15-20 元/月

## 8. 故障排查

### 问题1: 上传失败 - NoSuchBucket
- 检查 Bucket 名称是否正确
- 检查 endpoint 地域是否匹配

### 问题2: 上传失败 - InvalidAccessKeyId
- 检查 AccessKey ID 和 Secret 是否正确
- 检查子用户是否有 OSS 权限

### 问题3: ASR 无法访问 URL
- 检查 Bucket 权限是否设置为「公共读」
- 检查 URL 格式是否正确

## 9. 下一步优化（可选）

- [ ] 使用 STS 临时凭证替代硬编码密钥
- [ ] 添加音频文件过期自动删除策略
- [ ] 使用 OSS 内网 Endpoint 降低流量成本（服务端场景）
- [ ] 添加上传失败重试机制

