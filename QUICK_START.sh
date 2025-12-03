#!/bin/bash

# 快速配置脚本 - AliyunOSSiOS SDK
# 使用方法：bash QUICK_START.sh

echo "🚀 开始配置 AliyunOSSiOS SDK..."
echo ""

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ 未找到 Xcode，请先安装 Xcode${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 已找到 Xcode${NC}"
xcodebuild -version

# 检查项目文件
PROJECT_PATH="/Users/yansongtu/Documents/Yuanyuan/Yuanyuan.xcodeproj"
if [ ! -d "$PROJECT_PATH" ]; then
    echo -e "${RED}❌ 未找到项目文件: $PROJECT_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 已找到项目文件${NC}"

# 检查 OSSUploadService.swift 是否在项目中
OSS_SERVICE_FILE="/Users/yansongtu/Documents/Yuanyuan/Yuanyuan/Utils/OSSUploadService.swift"
if [ ! -f "$OSS_SERVICE_FILE" ]; then
    echo -e "${RED}❌ 未找到 OSSUploadService.swift${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 已找到 OSSUploadService.swift${NC}"
echo ""

# 提示用户手动添加 SPM 依赖
echo -e "${YELLOW}📦 接下来需要在 Xcode 中手动添加 AliyunOSSiOS SDK：${NC}"
echo ""
echo "步骤："
echo "1️⃣  打开 Xcode 项目：Yuanyuan.xcodeproj"
echo "2️⃣  菜单栏：File → Add Package Dependencies..."
echo "3️⃣  搜索框输入：https://github.com/aliyun/aliyun-oss-ios-sdk"
echo "4️⃣  选择版本：2.10.19"
echo "5️⃣  点击 Add Package"
echo ""

# 询问用户是否已完成
read -p "已完成添加 SDK？(y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}请先完成 SDK 添加，然后再运行此脚本${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ 配置完成！${NC}"
echo ""
echo "📝 后续步骤："
echo "1. 在 Xcode 中添加 OSSUploadService.swift 到项目"
echo "2. 创建 OSS Bucket：https://oss.console.aliyun.com/"
echo "   - Bucket 名称：yuanyuan-audio"
echo "   - 地域：华北2（北京）"
echo "   - 读写权限：公共读"
echo "3. 运行 App 测试录音转写功能"
echo ""
echo -e "${GREEN}🎉 所有准备工作就绪！${NC}"

