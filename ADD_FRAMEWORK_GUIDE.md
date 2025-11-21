# 添加 AliyunOSSiOS Framework 到项目

✅ **SDK 已经下载并构建完成！** 现在只需要在 Xcode 中添加即可。

## 📍 Framework 位置
```
/Users/yansongtu/Documents/Matters/Matters/AliyunOSSiOS.xcframework
```

## 🔧 在 Xcode 中添加 Framework

### 步骤 1：打开项目
```bash
open /Users/yansongtu/Documents/Matters/Matters.xcodeproj
```

### 步骤 2：添加 Framework
1. 在 Xcode 左侧项目导航器中，选择最顶层的 **Matters** 项目（蓝色图标）
2. 在中间区域，选择 **Matters** target（不是 MattersWidget）
3. 点击顶部的 **General** 标签
4. 滚动到 **Frameworks, Libraries, and Embedded Content** 部分
5. 点击 **+** 按钮
6. 在弹出窗口中，点击 **Add Other...** → **Add Files...**
7. 导航到 `/Users/yansongtu/Documents/Matters/Matters/`
8. 选择 `AliyunOSSiOS.xcframework` 文件夹
9. 点击 **Open**
10. 确保右侧显示 **Embed & Sign**

### 步骤 3：配置 Build Settings
1. 在同一个 Target 设置界面，点击顶部的 **Build Settings** 标签
2. 在搜索框中输入 `Other Linker Flags`
3. 找到 **Other Linker Flags** 设置
4. 双击右侧的值区域
5. 点击 **+** 按钮，添加：`-ObjC`
6. 点击空白处确认

### 步骤 4：添加系统库
1. 回到 **General** 标签
2. 在 **Frameworks, Libraries, and Embedded Content** 部分
3. 点击 **+** 按钮，搜索并添加以下系统库（选择 **Do Not Embed**）：
   - `libresolv.tbd`
   - `SystemConfiguration.framework`
   - `CoreTelephony.framework`

### 步骤 5：添加 OSSUploadService.swift
1. 在项目导航器中，右键点击 `Matters/Utils` 文件夹
2. 选择 **Add Files to "Matters"**
3. 找到并选择 `OSSUploadService.swift`
4. ✅ 确保勾选 **Matters** target
5. 点击 **Add**

---

## ✅ 验证安装

构建项目（Cmd + B），如果没有错误，说明安装成功！

---

## 🎯 下一步

1. ✅ Framework 已添加
2. ⏭️ 创建 OSS Bucket：https://oss.console.aliyun.com/
   - Bucket 名称：`matters-audio`
   - 地域：华北2（北京）
   - 读写权限：**公共读**
3. ⏭️ 测试录音转写功能

---

## 🐛 如果遇到问题

### 问题 1：找不到 AliyunOSSiOS 模块
- 检查 Framework 是否正确添加到 **Frameworks, Libraries, and Embedded Content**
- 确保选择了 **Embed & Sign**

### 问题 2：编译错误 "Undefined symbols"
- 确保添加了 `-ObjC` 到 **Other Linker Flags**
- 确保添加了三个系统库

### 问题 3：运行时崩溃
- 检查系统库是否都已添加
- 清理项目：Product → Clean Build Folder (Shift + Cmd + K)
- 重新构建

---

**提示**：整个过程大约 3-5 分钟！

