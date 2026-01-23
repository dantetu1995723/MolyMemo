import SwiftUI

struct FeishuCalendarSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var didSync: Bool
    
    private enum SyncState { case idle, syncing, success }
    
    @State private var calendars: [FeishuCalendarBackendService.CalendarItem] = []
    @State private var selectedCalendarId: String?
    @State private var isLoading = false
    @State private var syncState: SyncState = .idle
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            calendarSelectionView
        }
        .background(Color(hex: "F7F8FA").ignoresSafeArea())
        .task { await fetchCalendars() }
    }

    init(didSync: Binding<Bool> = .constant(false)) {
        self._didSync = didSync
    }
    
    // MARK: - 选择日历
    
    private var calendarSelectionView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                calendarSection
                if let error = errorMessage {
                    Text(error).font(.system(size: 14)).foregroundColor(.red).padding(.horizontal, 20)
                }
                Spacer(minLength: 100)
            }
            .padding(.top, 20)
        }
        .safeAreaInset(edge: .bottom) { syncButton }
    }
    
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择日历").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: "333333"))
                if isLoading { ProgressView().scaleEffect(0.8).padding(.leading, 4) }
                Spacer()
            }
            
            if calendars.isEmpty && !isLoading {
                Text("未发现可用日历，请确认已完成飞书授权。")
                    .font(.system(size: 14)).foregroundColor(Color(hex: "999999")).padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(calendars.enumerated()), id: \.element.id) { idx, cal in
                        calendarRow(cal)
                        if idx < calendars.count - 1 { Divider().padding(.leading, 16) }
                    }
                }
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func calendarRow(_ cal: FeishuCalendarBackendService.CalendarItem) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedCalendarId = cal.calendarId
                syncState = .idle
            }
        } label: {
            HStack(spacing: 12) {
                Circle().fill(Color(hex: String(format: "%06X", cal.color ?? 0x007AFF))).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cal.name).font(.system(size: 15, weight: .medium)).foregroundColor(Color(hex: "333333"))
                    if let desc = cal.description, !desc.isEmpty {
                        Text(desc).font(.system(size: 12)).foregroundColor(Color(hex: "999999")).lineLimit(1)
                    }
                }
                Spacer()
                if selectedCalendarId == cal.calendarId {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16).frame(height: 60).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var syncButton: some View {
        let canSync = selectedCalendarId != nil && syncState != .syncing && syncState != .success
        return Button { Task { await startSync() } } label: {
            HStack {
                if syncState == .syncing { ProgressView().tint(.white).padding(.trailing, 8) }
                if syncState == .success {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.white).padding(.trailing, 6)
                }
                Text(buttonTitle).font(.system(size: 17, weight: .bold))
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(buttonBackground(canSync: canSync))
            .foregroundColor(.white).cornerRadius(27)
            .shadow(color: buttonShadow(canSync: canSync), radius: 8, y: 4)
        }
        .disabled(!canSync)
        .padding(.horizontal, 24).padding(.bottom, 20)
    }
    
    private var buttonTitle: String {
        switch syncState {
        case .idle: return "开始同步"
        case .syncing: return "正在同步..."
        case .success: return "同步成功"
        }
    }
    
    private func buttonBackground(canSync: Bool) -> Color {
        switch syncState {
        case .success:
            return Color(hex: "34C759")
        case .syncing, .idle:
            return canSync ? Color(hex: "007AFF") : Color.gray.opacity(0.3)
        }
    }
    
    private func buttonShadow(canSync: Bool) -> Color {
        switch syncState {
        case .success:
            return Color(hex: "34C759").opacity(0.3)
        case .syncing, .idle:
            return canSync ? Color(hex: "007AFF").opacity(0.3) : .clear
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func fetchCalendars() async {
        isLoading = true
        errorMessage = nil
        do {
            calendars = try await FeishuCalendarBackendService.fetchCalendars()
            if selectedCalendarId == nil, let first = calendars.first {
                selectedCalendarId = first.calendarId
            }
        } catch {
            errorMessage = "获取日历失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    @MainActor
    private func startSync() async {
        guard let calendarId = selectedCalendarId else { return }
        syncState = .syncing
        errorMessage = nil
        do {
            _ = try await FeishuCalendarBackendService.sync(calendarId: calendarId)
            withAnimation { syncState = .success }
            didSync = true
        } catch {
            errorMessage = "同步失败: \(error.localizedDescription)"
            syncState = .idle
        }
    }
}
