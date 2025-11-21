import SwiftUI
import SwiftData
import UIKit

@main
struct MattersApp: App {
    @StateObject private var appState = AppState()
    
    // SwiftData 容器配置
    let modelContainer: ModelContainer
    
    init() {
        do {
            // 尝试正常初始化
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            modelContainer = try ModelContainer(
                for: PersistentChatMessage.self, DailyChatSummary.self, TodoItem.self, Contact.self, Expense.self, CompanyInfo.self, Meeting.self,
                configurations: configuration
            )
            print("✅ SwiftData 容器初始化成功")
        } catch {
            print("❌ 容器初始化失败，尝试删除旧数据库重建: \(error)")
            
            // 如果初始化失败（通常是模型变化导致），删除旧数据库
            do {
                // 获取默认存储URL
                if let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("default.store") {
                    try? FileManager.default.removeItem(at: storeURL)
                    print("🗑️ 已删除旧数据库")
                }
                
                // 重新创建容器
                let configuration = ModelConfiguration(
                    isStoredInMemoryOnly: false,
                    allowsSave: true
                )
                modelContainer = try ModelContainer(
                    for: PersistentChatMessage.self, DailyChatSummary.self, TodoItem.self, Contact.self, Expense.self, CompanyInfo.self, Meeting.self,
                    configurations: configuration
                )
                print("✅ 重建容器成功")
            } catch {
                print("❌ 重建容器失败: \(error)")
                fatalError("无法初始化 SwiftData 容器: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
                .environment(\.modelContext, modelContainer.mainContext)
                .onAppear {
                    print("🚀 ContentView onAppear - App 启动")
                    // 不再在启动时加载聊天记录，改为在进入聊天室时懒加载

                    // 请求通知权限
                    Task {
                        _ = await CalendarManager.shared.requestNotificationPermission()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerScreenshotAnalysis"))) { notification in
                    print("🎯 收到截图分析触发通知")

                    // 获取预分类结果
                    let category = notification.object as? ScreenshotCategory
                    if let category = category {
                        print("📊 收到预分类结果: \(category.rawValue)")
                    }

                    // 延迟执行，确保 App 完全启动
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("📲 开始执行 handleScreenshotFromClipboard")
                        appState.handleScreenshotFromClipboard(category: category)
                    }
                }
                .onOpenURL { url in
                    print("📱 收到URL: \(url)")
                    handleIncomingURL(url, modelContext: modelContainer.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartRecordingFromWidget"))) { notification in
                    print("🎤 收到快捷指令录音触发通知")
                    
                    let shouldNavigate = notification.userInfo?["shouldNavigateToMeeting"] as? Bool ?? false
                    let autoMinimize = notification.userInfo?["autoMinimize"] as? Bool ?? false
                    
                    if shouldNavigate {
                        // 快速启动模式：进入会议界面 → 启动录音 → 自动挂后台
                        DispatchQueue.main.async {
                            print("🚀 快捷指令快速启动模式")
                            
                            // 关闭所有其他界面
                            appState.showChatRoom = false
                            appState.showSettings = false
                            appState.showTodoList = false
                            appState.showContactList = false
                            appState.showExpenseList = false
                            appState.showLiveRecording = false
                            
                                // 跳转到会议界面
                                appState.showMeetingList = true
                                
                            // 极短延迟后启动录音（只需确保视图初始化）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                                        return modelContainer?.mainContext
                                    }
                                    LiveRecordingManager.shared.startRecording()
                                print("✅ 录音已启动")
                                
                                // 如果是快捷指令触发，等待录音和灵动岛初始化后自动挂后台
                                if autoMinimize {
                                    // 缩短等待时间到1秒（AVAudioEngine通常在0.5秒内就能初始化完成）
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        // 验证录音已成功启动
                                        if LiveRecordingManager.shared.isRecording {
                                            print("🏝️ 灵动岛已启动，自动挂起App")
                                            
                                            // 模拟按Home键，让App退到后台
                                            UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
                                            print("✅ App已自动挂到后台")
                                        } else {
                                            print("⚠️ 录音未成功启动，保持在前台")
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // 后台启动录音（保留用于其他场景）
                        print("🎯 后台启动录音模式")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                                return modelContainer?.mainContext
                            }
                            LiveRecordingManager.shared.startRecording()
                            print("✅ 后台录音已启动")
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopRecordingFromWidget"))) { _ in
                    print("🛑 收到Widget停止录音通知 - 保存到会议纪要")
                    DispatchQueue.main.async {
                        // 确保有ModelContext来保存
                        LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                            return modelContainer?.mainContext
                        }
                        LiveRecordingManager.shared.stopRecording(modelContext: modelContainer.mainContext)
                        print("✅ 录音已停止并保存")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    print("🚨 App即将完全退出")
                    // 确保LiveRecordingManager已经处理了录音保存
                    // 如果还在录音，强制停止并保存
                    if LiveRecordingManager.shared.isRecording {
                        print("⚠️ 检测到录音未停止，执行紧急保存")
                        LiveRecordingManager.shared.stopRecording(modelContext: modelContainer.mainContext)
                    }
                }
                .task {
                    // 监听AppIntent的执行（从Widget或快捷指令触发）
                    // 如果检测到录音Intent被触发，直接启动Live Activity
                    print("📱 App启动，检查是否有待处理的Intent")
                }
        }
    }
    
    // 处理URL scheme
    private func handleIncomingURL(_ url: URL, modelContext: ModelContext) {
        // 检查是否是matters://
        guard url.scheme == "matters" else { return }
        
        print("📱 处理URL: \(url.absoluteString)")
        
        if url.host == "screenshot" || url.path == "/screenshot" {
            print("📸 触发截图分享")
            // 从剪贴板获取截图并打开聊天室
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.handleScreenshotFromClipboard()
            }
        } else if url.host == "start-recording-widget" || url.path == "/start-recording-widget" {
            print("🎤 Widget触发会议录音 - 跳转到会议界面并启动录音")
            // 从Widget触发：跳转到会议界面并启动录音
            DispatchQueue.main.async {
                // 关闭其他界面
                appState.showChatRoom = false
                appState.showSettings = false
                appState.showTodoList = false
                appState.showContactList = false
                appState.showExpenseList = false
                appState.showLiveRecording = false
                
                // 延迟确保界面已加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // 跳转到会议界面
                    appState.showMeetingList = true
                    
                    // 再延迟一下启动录音，确保会议界面已经完全加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        LiveRecordingManager.shared.modelContextProvider = { [weak modelContainer] in
                            return modelContainer?.mainContext
                        }
                        LiveRecordingManager.shared.startRecording()
                        print("✅ 已跳转到会议界面并启动录音")
                    }
                }
            }
        } else if url.host == "start-recording" || url.path == "/start-recording" {
            print("🎤 触发会议录音 - 显示录音界面")
            // 显示录音界面
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.showLiveRecording = true
            }
        } else if url.host == "pause-recording" || url.path == "/pause-recording" {
            print("⏸️ 暂停录音")
            LiveRecordingManager.shared.pauseRecording()
        } else if url.host == "resume-recording" || url.path == "/resume-recording" {
            print("▶️ 继续录音")
            LiveRecordingManager.shared.resumeRecording()
        } else if url.host == "stop-recording" || url.path == "/stop-recording" {
            print("🛑 停止录音")
            LiveRecordingManager.shared.stopRecording(modelContext: modelContext)
        } else if url.host == "meeting-recording" || url.path == "/meeting-recording" {
            print("📝 跳转到会议纪要界面")
            // 关闭其他界面，打开会议纪要界面
            DispatchQueue.main.async {
                // 确保导航到会议界面
                appState.showChatRoom = false
                appState.showSettings = false
                appState.showTodoList = false
                appState.showContactList = false
                appState.showExpenseList = false
                appState.showLiveRecording = false
                
                // 延迟一下确保界面已加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.showMeetingList = true
                    print("✅ 已触发跳转到会议界面")
                }
            }
        }
    }
}
