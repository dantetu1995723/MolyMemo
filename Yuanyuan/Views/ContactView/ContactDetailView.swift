import SwiftUI
import SwiftData

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Bindable var contact: Contact
    
    @State private var selectedTab = 0 // 0: 基础信息, 1: 时间线
    @State private var showEditSheet = false
    @State private var showDeleteMenu = false
    
    // 颜色定义
    private let bgColor = Color(red: 0.97, green: 0.97, blue: 0.97)
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    private let iconColor = Color(hex: "CCCCCC")
    
    // 语音输入相关
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isRecording = false
    @State private var isAnimatingRecordingExit = false
    @State private var isCanceling = false
    @State private var audioPower: CGFloat = 0.0
    @State private var recordingTranscript: String = ""
    @State private var buttonFrame: CGRect = .zero
    @State private var isPressing = false
    @State private var pressStartTime: Date?
    
    private let silenceGate: Float = 0.12
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header
                ZStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.secondary.opacity(0.15)))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showDeleteMenu = true
                                }
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                            
                            Button(action: { dismiss() }) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                            }
                        }
                    }
                    
                    Text("人脉详情")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(primaryTextColor)
                    
                    if showDeleteMenu {
                        ContactDeletePillButton(
                            onDelete: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showDeleteMenu = false
                                }
                                HapticFeedback.medium()
                                modelContext.delete(contact)
                                dismiss()
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 44 + 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .zIndex(100)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 姓名
                        Text(contact.name)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(primaryTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                        
                        // 分段选择器
                        HStack(spacing: 0) {
                            TabButton(title: "基础信息", isSelected: selectedTab == 0) {
                                withAnimation(.spring(response: 0.3)) { selectedTab = 0 }
                            }
                            
                            TabButton(title: "时间线", isSelected: selectedTab == 1) {
                                withAnimation(.spring(response: 0.3)) { selectedTab = 1 }
                            }
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Capsule())
                        .padding(.horizontal, 40)
                        
                        if selectedTab == 0 {
                            // 基础信息内容
                            VStack(spacing: 20) {
                                // 公司和职位
                                InfoRow(icon: "building.2", text: contact.company ?? "未填写公司", subtext: contact.identity)
                                
                                // 行业
                                InfoRow(icon: "bag", text: contact.industry ?? "未填写行业")
                                
                                // 地区
                                InfoRow(icon: "mappin.and.ellipse", text: contact.location ?? "未填写地区")
                                
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                
                                // 电话
                                HStack(spacing: 0) {
                                    InfoRow(icon: "phone", text: contact.phoneNumber ?? "未填写电话")
                                    
                                    Button(action: {
                                        if let phone = contact.phoneNumber, let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Image(systemName: "phone.arrow.up.right")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(primaryTextColor)
                                            .frame(width: 44, height: 44)
                                            .background(Circle().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2))
                                    }
                                    .padding(.trailing, 20)
                                }
                                
                                // 邮箱
                                InfoRow(icon: "envelope", text: contact.email ?? "未填写邮箱")
                                
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                
                                // 生日
                                HStack(spacing: 0) {
                                    LabelWithIcon(icon: "calendar", title: "生日")
                                    Spacer()
                                    Text(contact.birthday ?? "未设置")
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                        .padding(.trailing, 20)
                                }
                                .padding(.leading, 20)
                                
                                // 性别
                                HStack(spacing: 0) {
                                    LabelWithIcon(icon: "person.fill", title: "性别")
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text(contact.gender ?? "未知")
                                            .font(.system(size: 16))
                                            .foregroundColor(primaryTextColor)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(iconColor)
                                    }
                                    .padding(.trailing, 20)
                                }
                                .padding(.leading, 20)
                                
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                
                                // 备注/详细描述
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 18))
                                        .foregroundColor(iconColor)
                                        .frame(width: 24, alignment: .leading)
                                    
                                    Text(contact.notes ?? "暂无详细描述，长按下方按钮可语音录入。")
                                        .font(.system(size: 16))
                                        .foregroundColor(primaryTextColor)
                                        .lineSpacing(6)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }
                        } else {
                            // 时间线内容
                            VStack {
                                Text("暂无时间线记录")
                                    .foregroundColor(secondaryTextColor)
                                    .padding(.top, 40)
                            }
                        }
                        
                        Spacer(minLength: 120)
                    }
                }
                
                if showDeleteMenu {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { withAnimation { showDeleteMenu = false } }
                }
            }
            
            // Voice Button
            ZStack {
                Capsule()
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
                    .background(Capsule().fill(Color.white))
                    .frame(height: 56)
                    .background(GeometryReader { geo in Color.clear.onAppear { buttonFrame = geo.frame(in: .named("ContactDetailViewSpace")) } })
                
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .foregroundColor(isRecording ? .red : .gray)
                    Text(isRecording ? "正在听..." : "长按可语音编辑")
                        .foregroundColor(Color(hex: "666666"))
                }
            }
            .opacity(isRecording ? 0 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { handleDragChanged($0) }.onEnded { handleDragEnded($0) })
            
            if isRecording || isAnimatingRecordingExit {
                VoiceRecordingOverlay(
                    isRecording: $isRecording,
                    isCanceling: $isCanceling,
                    isExiting: isAnimatingRecordingExit,
                    onExitComplete: {
                        finishRecordingOverlayDismissal()
                    },
                    audioPower: audioPower,
                    transcript: recordingTranscript,
                    inputFrame: buttonFrame,
                    toolboxFrame: .zero
                )
                .zIndex(1000)
            }
        }
        .coordinateSpace(name: "ContactDetailViewSpace")
        .background(bgColor)
        .onAppear { speechRecognizer.requestAuthorization() }
        .onReceive(speechRecognizer.$audioLevel) { self.audioPower = mapAudioLevelToPower($0) }
        .navigationBarHidden(true)
    }
    
    // Voice logic
    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isPressing { isPressing = true; pressStartTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if isPressing, let s = pressStartTime, Date().timeIntervalSince(s) >= 0.3 { if !isRecording { HapticFeedback.medium(); startVoiceInput() } } }
        }
        if isRecording { if value.translation.height < -50 { if !isCanceling { withAnimation { isCanceling = true } } } else { if isCanceling { withAnimation { isCanceling = false } } } }
    }
    private func handleDragEnded(_ value: DragGesture.Value) { isPressing = false; pressStartTime = nil; if isRecording { stopVoiceInput() } }
    private func mapAudioLevelToPower(_ level: Float) -> CGFloat { let c = max(0, min(level, 1)); guard c >= silenceGate else { return 0 }; return CGFloat(pow((c - silenceGate) / max(0.0001, 1 - silenceGate), 0.6)) }
    private func startVoiceInput() { isAnimatingRecordingExit = false; isRecording = true; isCanceling = false; recordingTranscript = "正在聆听..."; speechRecognizer.startRecording { t in let tr = t.trimmingCharacters(in: .whitespacesAndNewlines); self.recordingTranscript = tr.isEmpty ? "正在聆听..." : tr } }
    private func stopVoiceInput() { speechRecognizer.stopRecording(); if !isCanceling { let t = recordingTranscript.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty, t != "正在聆听..." { parseVoiceCommand(voiceText: t) } }; audioPower = 0; withAnimation(.easeInOut(duration: 0.2)) { isAnimatingRecordingExit = true } }
    private func finishRecordingOverlayDismissal() { isRecording = false; isAnimatingRecordingExit = false; isCanceling = false; audioPower = 0 }
    
    private func parseVoiceCommand(voiceText: String) {
        Task {
            // TODO: 调用相关的语音解析逻辑更新联系人信息
            // 这里可以复用类似 TodoVoiceParser 的逻辑，或者为联系人单独写一个
            HapticFeedback.success()
        }
    }
}

// MARK: - 辅助组件

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? Color(hex: "333333") : Color(hex: "999999"))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.white : Color.clear)
                .clipShape(Capsule())
                .shadow(color: isSelected ? Color.black.opacity(0.05) : Color.clear, radius: 4, x: 0, y: 2)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    var subtext: String? = nil
    
    private let iconColor = Color(hex: "CCCCCC")
    private let primaryTextColor = Color(hex: "333333")
    private let secondaryTextColor = Color(hex: "999999")
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(primaryTextColor)
                
                if let subtext = subtext, !subtext.isEmpty {
                    Text(subtext)
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct LabelWithIcon: View {
    let icon: String
    let title: String
    
    private let iconColor = Color(hex: "CCCCCC")
    private let primaryTextColor = Color(hex: "333333")
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(primaryTextColor)
        }
    }
}

struct ContactDeletePillButton: View {
    var onDelete: () -> Void
    var body: some View {
        Button(action: onDelete) {
            HStack(spacing: 8) {
                Image(systemName: "trash").font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: "FF3B30"))
                Text("删除人脉").foregroundColor(Color(hex: "FF3B30")).font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.leading, 20).padding(.trailing, 16).frame(width: 200, height: 52)
            .background(Capsule().fill(Color.white).shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}
