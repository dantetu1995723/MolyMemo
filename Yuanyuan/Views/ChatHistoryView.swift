import SwiftUI
import SwiftData

// 聊天历史视图 - 世界树形式展示每日聊天总结
struct ChatHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Query(sort: \DailyChatSummary.date, order: .reverse) private var dailySummaries: [DailyChatSummary]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 深色背景 - 世界树风格
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.1, green: 0.12, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if dailySummaries.isEmpty {
                    // 空状态
                    VStack(spacing: 20) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 70, weight: .light))
                            .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                            .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.6), radius: 20, x: 0, y: 0)
                        
                        Text("记忆树尚未生长")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                } else {
                    // 世界树列表 - 带主树干
                    ZStack(alignment: .topLeading) {
                        // 主树干 - 贯穿整个页面
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3),
                                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.6),
                                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.5),
                                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 4)
                                .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.5), radius: 8, x: 0, y: 0)
                        }
                        .padding(.leading, 40)
                        .padding(.top, 0)
                        
                        // 节点和卡片列表
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(dailySummaries.enumerated()), id: \.element.id) { index, summary in
                                    WorldTreeNodeView(
                                        summary: summary,
                                        isFirst: index == 0,
                                        isLast: index == dailySummaries.count - 1
                                    )
                                }
                            }
                            .padding(.top, 30)
                            .padding(.bottom, 50)
                        }
                    }
                }
            }
            .navigationTitle("记忆世界树")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticFeedback.light()
                        dismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                            Text("返回")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                        .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    }
                }
            }
        }
    }
}

// 世界树节点视图
struct WorldTreeNodeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    let summary: DailyChatSummary
    let isFirst: Bool
    let isLast: Bool
    @State private var isExpanded: Bool = false
    @State private var showMessages: Bool = false
    @State private var originalMessages: [ChatMessage] = []
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左侧节点区域（叠加在主树干上）
            ZStack {
                // 树节点 - 发光的能量核心
                ZStack {
                    // 外圈发光
                    Circle()
                        .fill(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3))
                        .frame(width: 40, height: 40)
                        .blur(radius: 8)
                    
                    // 中圈
                    Circle()
                        .stroke(Color(red: 0.85, green: 1.0, blue: 0.25), lineWidth: 3)
                        .frame(width: 28, height: 28)
                        .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.8), radius: 10, x: 0, y: 0)
                    
                    // 内核
                    Circle()
                        .fill(Color(red: 0.85, green: 1.0, blue: 0.25))
                        .frame(width: 14, height: 14)
                        .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25), radius: 6, x: 0, y: 0)
                }
            }
            .frame(width: 60, height: 60)
            .padding(.leading, 12)
            
            // 横向分支线（从节点到卡片）
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.7),
                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 24, height: 3)
                .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.5), radius: 4, x: 0, y: 0)
                .padding(.top, 28)
            
            // 右侧内容卡片
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    HapticFeedback.light()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                }) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 日期标签区
                        HStack(spacing: 10) {
                            // 日期文字
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.relativeDateString)
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                                    .shadow(color: Color.black, radius: 0, x: -1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: -1)
                                    .shadow(color: Color.black, radius: 0, x: -1, y: 1)
                                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                                    .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.6), radius: 8, x: 0, y: 0)
                                
                                Text(summary.formattedDate)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }
                            
                            Spacer()
                            
                            // 消息数量和展开按钮
                            HStack(spacing: 8) {
                                // 消息数量按钮 - 点击查看原始对话
                                if summary.messageCount > 0 {
                                    Button(action: {
                                        HapticFeedback.medium()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                            showMessages.toggle()
                                        }
                                        if showMessages && originalMessages.isEmpty {
                                            loadOriginalMessages()
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: showMessages ? "eye.fill" : "bubble.left.and.bubble.right.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                            Text("\(summary.messageCount)")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundColor(Color.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .fill(Color(red: 0.85, green: 1.0, blue: 0.25))
                                        )
                                    }
                                }
                                
                                // 展开/收起图标
                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                                    .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.6), radius: 6, x: 0, y: 0)
                                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            }
                        }
                        
                        // 总结内容 - 可折叠
                        Text(summary.summary)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineSpacing(6)
                            .lineLimit(isExpanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // 原始对话记录 - 展开时显示
                        if showMessages {
                            VStack(spacing: 0) {
                                // 分割线
                                Rectangle()
                                    .fill(Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3))
                                    .frame(height: 1)
                                    .padding(.vertical, 12)
                                
                                // 标题
                                HStack {
                                    Image(systemName: "timeline.selection")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("对话记录")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    Spacer()
                                    
                                    // 消息数量提示
                                    if !originalMessages.isEmpty {
                                        Text("\(originalMessages.filter { !$0.isGreeting }.count)条")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Color.white.opacity(0.5))
                                    }
                                }
                                .foregroundColor(Color(red: 0.85, green: 1.0, blue: 0.25))
                                .padding(.bottom, 10)
                                
                                // 原始消息列表 - 限制高度 + ScrollView
                                if originalMessages.isEmpty {
                                    Text("加载中...")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(Color.white.opacity(0.5))
                                        .padding(.vertical, 10)
                                } else {
                                    ScrollView {
                                        VStack(spacing: 8) {
                                            ForEach(originalMessages.filter { !$0.isGreeting }) { message in
                                                HistoryMessageBubble(message: message)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .frame(maxHeight: 350)  // 限制最大高度
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.03))
                                    )
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .padding(18)
                    .background(
                        ZStack {
                            // 深色半透明背景
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.6))
                            
                            // 霓虹边框
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.6),
                                            Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .shadow(color: Color(red: 0.85, green: 1.0, blue: 0.25).opacity(0.4), radius: 8, x: 0, y: 0)
                            
                            // 玻璃高光
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.trailing, 20)
            .padding(.bottom, isLast ? 30 : 60)
        }
    }
    
    // 加载当天的原始消息
    private func loadOriginalMessages() {
        let dayStart = DailyChatSummary.startOfDay(summary.date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        
        let descriptor = FetchDescriptor<PersistentChatMessage>(
            predicate: #Predicate<PersistentChatMessage> { message in
                message.timestamp >= dayStart && message.timestamp < dayEnd
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            let persistentMessages = try modelContext.fetch(descriptor)
            var msgs = persistentMessages.map { $0.toChatMessage() }
            // 旧版本不存 segments：通过卡片批次回填，保证历史卡片也能展示
            appState.hydrateCardBatchesIfNeeded(for: &msgs, modelContext: modelContext)
            originalMessages = msgs
            print("✅ 加载了 \(originalMessages.count) 条原始消息")
        } catch {
            print("⚠️ 加载原始消息失败: \(error)")
        }
    }
}

// 历史消息气泡
struct HistoryMessageBubble: View {
    let message: ChatMessage
    @State private var selectedImage: IdentifiableImage? = nil
    @State private var isCardHorizontalPaging: Bool = false
    
    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            // 时间戳
            Text(formattedTime)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.white.opacity(0.4))
            
            if message.role == .user {
                UserBubble(message: message)
            } else {
                agentMessageContent
            }
        }
        .fullScreenCover(item: $selectedImage) { identifiableImage in
            FullScreenImageView(image: identifiableImage.image) {
                selectedImage = nil
            }
        }
    }

    // 让历史记录与 ChatView 的 AI 气泡/卡片顺序对齐：
    // - 优先使用持久化的 segments（后端 chunk 顺序）
    // - 若 segments 为空，则 fallback：文本 -> schedule -> contact -> invoice -> meeting（与 ChatView 兼容逻辑一致）
    @ViewBuilder
    private var agentMessageContent: some View {
        let segments: [ChatSegment] = {
            if let segs = message.segments, !segs.isEmpty {
                return segs
            }
            var segs: [ChatSegment] = []
            let t = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { segs.append(.text(t)) }
            if let s = message.scheduleEvents, !s.isEmpty { segs.append(.scheduleCards(s)) }
            if let c = message.contacts, !c.isEmpty { segs.append(.contactCards(c)) }
            if let i = message.invoices, !i.isEmpty { segs.append(.invoiceCards(i)) }
            if let m = message.meetings, !m.isEmpty { segs.append(.meetingCards(m)) }
            return segs
        }()
        
        let hasAnyCards = segments.contains(where: { $0.kind != .text })
        let firstTextSegmentId = segments.first(where: { $0.kind == .text })?.id
        
        VStack(alignment: .leading, spacing: 12) {
            ForEach(segments) { seg in
                switch seg.kind {
                case .text:
                    AIBubble(
                        text: seg.text ?? "",
                        messageId: nil,
                        shouldAnimate: false,
                        showActionButtons: false,
                        isInterrupted: message.isInterrupted,
                        showAvatar: (hasAnyCards ? (seg.id == firstTextSegmentId) : true)
                    )
                    
                case .scheduleCards:
                    ScheduleCardStackView(
                        events: .constant(seg.scheduleEvents ?? []),
                        isParentScrollDisabled: $isCardHorizontalPaging,
                        onDeleteRequest: nil,
                        onOpenDetail: nil
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
                    .allowsHitTesting(false)
                    
                case .contactCards:
                    ContactCardStackView(
                        contacts: .constant(seg.contacts ?? []),
                        isParentScrollDisabled: $isCardHorizontalPaging,
                        onOpenDetail: nil,
                        onDeleteRequest: nil
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
                    .allowsHitTesting(false)
                    
                case .invoiceCards:
                    InvoiceCardStackView(
                        invoices: .constant(seg.invoices ?? []),
                        onOpenDetail: nil,
                        onDeleteRequest: nil
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
                    .allowsHitTesting(false)
                    
                case .meetingCards:
                    MeetingSummaryCardStackView(
                        meetings: .constant(seg.meetings ?? []),
                        isParentScrollDisabled: $isCardHorizontalPaging,
                        onDeleteRequest: nil,
                        onOpenDetail: nil
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
                    .allowsHitTesting(false)
                }
            }
        }
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }
}

#Preview {
    ChatHistoryView()
        .modelContainer(for: DailyChatSummary.self, inMemory: true)
        .environmentObject(AppState())
}

