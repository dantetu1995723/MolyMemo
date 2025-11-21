# 添加 AliyunOSSiOS SDK 操作指南

## 方法：使用 Swift Package Manager（最简单）

### 步骤 1：打开项目
在 Xcode 中打开 `Matters.xcodeproj`

### 步骤 2：添加 Package
1. 在 Xcode 顶部菜单栏，点击 **File** → **Add Package Dependencies...**
2. 在搜索框中输入：
   ```
   https://github.com/aliyun/aliyun-oss-ios-sdk
   ```
3. 点击搜索结果中的 **aliyun-oss-ios-sdk**

### 步骤 3：选择版本
1. 在右侧 **Dependency Rule** 选择：**Up to Next Major Version**
2. 版本号填写：`2.10.19`
3. 点击 **Add Package**

### 步骤 4：选择目标
1. 在弹出的窗口中，确保勾选 ✅ **AliyunOSSiOS**
2. Target 选择：**Matters**
3. 点击 **Add Package**

### 步骤 5：等待下载
Xcode 会自动下载并集成 SDK，等待几秒钟即可。

---

## 验证安装

安装完成后，在项目导航器中应该能看到：
```
Matters
├── Dependencies
│   └── aliyun-oss-ios-sdk
```

或者在项目设置中：
1. 选择项目 **Matters**
2. 选择 Target **Matters**
3. 进入 **General** → **Frameworks, Libraries, and Embedded Content**
4. 应该能看到 **AliyunOSSiOS.framework**

---

## 如果遇到问题

### 问题 1：搜索不到包
- 检查网络连接
- 直接复制 URL：`https://github.com/aliyun/aliyun-oss-ios-sdk`

### 问题 2：下载失败
- 关闭 Xcode
- 删除缓存：`rm -rf ~/Library/Developer/Xcode/DerivedData/*`
- 重新打开 Xcode 再试

---

## 完成后的下一步

SDK 添加完成后，还需要：

### 1. 添加 OSSUploadService.swift 到项目
在 Xcode 中：
1. 右键点击 `Matters/Utils` 文件夹
2. 选择 **Add Files to "Matters"**
3. 找到并选择 `OSSUploadService.swift`
4. 确保勾选 ✅ **Matters** target
5. 点击 **Add**

### 2. 创建 OSS Bucket
访问：https://oss.console.aliyun.com/
- Bucket 名称：`matters-audio`
- 地域：华北2（北京）
- 读写权限：**公共读**

### 3. 测试
运行 App，录音并点击转写，查看控制台日志。

---

**提示**：整个过程大约 2-3 分钟即可完成！

