import SwiftUI
import SwiftData

// 批量联系人扫描收集页面
struct ContactBatchScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    
    @State private var collectedImages: [UIImage] = []
    @State private var isMonitoring = false
    @State private var selectedImageIndices: Set<Int> = []
    @State private var showingSendConfirmation = false
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                topNavigationBar
                
                // 主内容区
                if collectedImages.isEmpty {
                    emptyStateView
                } else {
                    imageGridView
                }
                
                // 底部操作栏
                bottomActionBar
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }
    
    // MARK: - 顶部导航栏
    
    private var topNavigationBar: some View {
        HStack(spacing: 16) {
            // 返回按钮
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                    )
            }
            .buttonStyle(ScaleButtonStyle())
            
            // 标题
            VStack(alignment: .leading, spacing: 2) {
                Text("批量扫描")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                
                if !collectedImages.isEmpty {
                    Text("已收集 \(collectedImages.count) 张截图")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                }
            }
            
            Spacer()
            
            // 清空按钮
            if !collectedImages.isEmpty {
                Button(action: clearAll) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.8))
                                .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 2)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - 空状态视图
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 图标
            Image(systemName: "photo.stack")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.5))
            
            // 提示文字
            VStack(spacing: 12) {
                Text("开始批量扫描联系人")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                
                Text("切换到微信，连续截图多个联系人\n截图会自动显示在这里")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: -0.5)
                    .shadow(color: Color.black, radius: 0, x: -0.5, y: 0.5)
                    .shadow(color: Color.black, radius: 0, x: 0.5, y: 0.5)
            }
            
            // 操作提示
            VStack(alignment: .leading, spacing: 10) {
                InstructionRow(number: "1", text: "打开微信，找到想添加的联系人")
                InstructionRow(number: "2", text: "连续截图（侧边按钮或快捷指令）")
                InstructionRow(number: "3", text: "回到这里，点击「发送识别」")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    // MARK: - 图片网格视图
    
    private var imageGridView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(imageGroups.indices, id: \.self) { groupIndex in
                    ImageGroupSection(
                        groupIndex: groupIndex,
                        images: imageGroups[groupIndex],
                        selectedIndices: $selectedImageIndices,
                        onDelete: { indices in
                            deleteImages(at: indices)
                        }
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
    }
    
    // MARK: - 底部操作栏
    
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            if !collectedImages.isEmpty {
                // 选择操作
                HStack(spacing: 12) {
                    if !selectedImageIndices.isEmpty {
                        Button(action: {
                            deleteImages(at: selectedImageIndices)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("删除 \(selectedImageIndices.count) 张")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.red.opacity(0.8))
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    
                    Button(action: {
                        if selectedImageIndices.isEmpty {
                            selectedImageIndices = Set(0..<collectedImages.count)
                        } else {
                            selectedImageIndices.removeAll()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: selectedImageIndices.isEmpty ? "checkmark.square" : "square")
                                .font(.system(size: 14, weight: .semibold))
                            Text(selectedImageIndices.isEmpty ? "全选" : "取消全选")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(Color.black.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.black.opacity(0.05))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            
            // 发送按钮
            if !collectedImages.isEmpty {
                Button(action: sendToChat) {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .bold))
                        
                        Text("发送识别 (\(collectedImages.count)张)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 1.0, blue: 0.25),
                                        Color(red: 0.78, green: 0.98, blue: 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.4), radius: 20, x: 0, y: 8)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(
            Rectangle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }
    
    // MARK: - 数据处理
    
    // 按10张一组分组
    private var imageGroups: [[UIImage]] {
        stride(from: 0, to: collectedImages.count, by: 10).map { startIndex in
            let endIndex = min(startIndex + 10, collectedImages.count)
            return Array(collectedImages[startIndex..<endIndex])
        }
    }
    
    // 开始监听截图
    private func startMonitoring() {
        print("📸 开始监听截图...")
        isMonitoring = true
        
        // 注册通知监听
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BatchScanNewScreenshot"),
            object: nil,
            queue: .main
        ) { notification in
            if let image = notification.object as? UIImage {
                print("✅ 收到新截图")
                collectedImages.append(image)
                HapticFeedback.light()
            }
        }
    }
    
    // 停止监听
    private func stopMonitoring() {
        print("🛑 停止监听截图")
        isMonitoring = false
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("BatchScanNewScreenshot"), object: nil)
    }
    
    // 清空所有图片
    private func clearAll() {
        collectedImages.removeAll()
        selectedImageIndices.removeAll()
        HapticFeedback.light()
    }
    
    // 删除选中的图片
    private func deleteImages(at indices: Set<Int>) {
        let sortedIndices = indices.sorted(by: >)
        for index in sortedIndices {
            if index < collectedImages.count {
                collectedImages.remove(at: index)
            }
        }
        selectedImageIndices.removeAll()
        HapticFeedback.success()
    }
    
    // 发送到聊天室
    private func sendToChat() {
        guard !collectedImages.isEmpty else { return }
        
        print("📤 发送 \(collectedImages.count) 张截图到聊天室进行批量识别")
        HapticFeedback.medium()
        
        // 发送通知，告诉ChatRoomPage处理批量识别
        NotificationCenter.default.post(
            name: NSNotification.Name("BatchContactScan"),
            object: collectedImages
        )
        
        // 关闭当前页面，返回到聊天室
        dismiss()
    }
}

// MARK: - 子组件

// 图片分组区域
struct ImageGroupSection: View {
    let groupIndex: Int
    let images: [UIImage]
    @Binding var selectedIndices: Set<Int>
    let onDelete: (Set<Int>) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分组标题
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .medium))
                Text("第 \(groupIndex + 1) 组 (\(images.count) 张)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.7))
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // 图片网格
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(images.indices, id: \.self) { localIndex in
                    let globalIndex = groupIndex * 10 + localIndex
                    ImageThumbnailCell(
                        image: images[localIndex],
                        isSelected: selectedIndices.contains(globalIndex),
                        onTap: {
                            if selectedIndices.contains(globalIndex) {
                                selectedIndices.remove(globalIndex)
                            } else {
                                selectedIndices.insert(globalIndex)
                            }
                            HapticFeedback.light()
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// 图片缩略图单元格
struct ImageThumbnailCell: View {
    let image: UIImage
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.clear,
                            lineWidth: 3
                        )
                )
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .onTapGesture {
                    onTap()
                }
            
            // 选中标记
            Circle()
                .fill(isSelected ? Color(red: 0.85, green: 1.0, blue: 0.25) : Color.white)
                .frame(width: 24, height: 24)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                .overlay(
                    isSelected ? Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black) : nil
                )
                .offset(x: 5, y: -5)
                .allowsHitTesting(false)
        }
    }
}

// 操作说明行
struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 1.0, blue: 0.25),
                                    Color(red: 0.78, green: 0.98, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color.black.opacity(0.7))
            
            Spacer()
        }
    }
}

