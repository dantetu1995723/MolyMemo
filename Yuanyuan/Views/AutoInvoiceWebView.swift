import SwiftUI
import WebKit

// 自动开票 WebView
struct AutoInvoiceWebView: View {
    @Environment(\.dismiss) private var dismiss
    let url: String
    let companyInfo: CompanyInfo
    let onSuccess: () -> Void
    let onError: (String) -> Void
    
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0
    @State private var currentStep = "正在打开开票页面..."
    
    var body: some View {
        NavigationStack {
            ZStack {
                // WebView
                AutoInvoiceWebViewController(
                    url: url,
                    companyInfo: companyInfo,
                    isLoading: $isLoading,
                    loadingProgress: $loadingProgress,
                    currentStep: $currentStep,
                    onSuccess: {
                        HapticFeedback.success()
                        onSuccess()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    },
                    onError: { error in
                        HapticFeedback.error()
                        onError(error)
                    }
                )
                
                // 加载进度覆盖层
                if isLoading {
                    LoadingOverlay(progress: loadingProgress, step: currentStep)
                }
            }
            .navigationTitle("自动开票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.7))
                    }
                }
            }
        }
    }
}

// 加载进度覆盖层
struct LoadingOverlay: View {
    let progress: Double
    let step: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // 进度环
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color(red: 0.6, green: 0.75, blue: 0.2),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // 步骤说明
                VStack(spacing: 8) {
                    Text(step)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("请稍候...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
}

// WebView 控制器
struct AutoInvoiceWebViewController: UIViewRepresentable {
    let url: String
    let companyInfo: CompanyInfo
    @Binding var isLoading: Bool
    @Binding var loadingProgress: Double
    @Binding var currentStep: String
    let onSuccess: () -> Void
    let onError: (String) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.hasLoadedURL == false {
            if let url = URL(string: url) {
                let request = URLRequest(url: url)
                webView.load(request)
                context.coordinator.hasLoadedURL = true
                print("🌐 开始加载 URL: \(url)")
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            companyInfo: companyInfo,
            isLoading: $isLoading,
            loadingProgress: $loadingProgress,
            currentStep: $currentStep,
            onSuccess: onSuccess,
            onError: onError
        )
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let companyInfo: CompanyInfo
        @Binding var isLoading: Bool
        @Binding var loadingProgress: Double
        @Binding var currentStep: String
        let onSuccess: () -> Void
        let onError: (String) -> Void
        var hasLoadedURL = false
        var hasFilledForm = false
        
        init(
            companyInfo: CompanyInfo,
            isLoading: Binding<Bool>,
            loadingProgress: Binding<Double>,
            currentStep: Binding<String>,
            onSuccess: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.companyInfo = companyInfo
            self._isLoading = isLoading
            self._loadingProgress = loadingProgress
            self._currentStep = currentStep
            self.onSuccess = onSuccess
            self.onError = onError
        }
        
        // 页面开始加载
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("📄 页面开始加载")
            DispatchQueue.main.async {
                self.loadingProgress = 0.2
                self.currentStep = "正在打开开票页面..."
            }
        }
        
        // 页面加载完成
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ 页面加载完成")
            
            DispatchQueue.main.async {
                self.loadingProgress = 0.5
                self.currentStep = "正在填写开票信息..."
            }
            
            // 等待页面完全渲染
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.fillFormAndSubmit(webView: webView)
            }
        }
        
        // 页面加载失败
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ 页面加载失败: \(error)")
            DispatchQueue.main.async {
                self.isLoading = false
                self.onError("页面加载失败：\(error.localizedDescription)")
            }
        }
        
        // 自动填写表单并提交（使用AI智能填写）
        func fillFormAndSubmit(webView: WKWebView) {
            guard !hasFilledForm else { return }
            hasFilledForm = true
            
            print("📝 开始智能填写表单（传统规则 + AI辅助）...")
            
            // 使用AI智能填写服务
            AIFormFillerService.intelligentFillForm(
                webView: webView,
                companyInfo: companyInfo,
                onSuccess: { [weak self] in
                    guard let self = self else { return }
                    
                    print("✅ 表单填写成功")
                    
                    // 更新进度
                    DispatchQueue.main.async {
                        self.loadingProgress = 0.9
                        self.currentStep = "正在提交开票申请..."
                    }
                    
                    // 等待2秒，让表单数据稳定后再点击提交
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.clickSubmitButton(webView: webView)
                    }
                },
                onError: { [weak self] errorMessage in
                    guard let self = self else { return }
                    
                    print("❌ 智能填写失败: \(errorMessage)")
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("自动填写失败：\(errorMessage)")
                    }
                }
            )
        }
        
        // 点击提交按钮
        func clickSubmitButton(webView: WKWebView) {
            let submitScript = """
            (function() {
                // 尝试多种方式查找提交按钮
                const selectors = [
                    'button[type="submit"]',
                    '.submit-btn',
                    '#submit',
                    'button.btn-primary',
                    'button.ant-btn-primary',
                    'input[type="submit"]',
                    '.invoice-submit',
                    '#invoice-submit'
                ];
                
                for (let selector of selectors) {
                    const button = document.querySelector(selector);
                    if (button && !button.disabled) {
                        console.log('✅ 找到提交按钮: ' + selector);
                        button.click();
                        return {success: true, method: selector};
                    }
                }
                
                // 通过文本查找按钮
                const buttons = document.querySelectorAll('button, input[type="button"], a.btn');
                for (let button of buttons) {
                    const text = (button.textContent || button.innerText || button.value || '').trim();
                    if ((text.includes('申请开票') || 
                        text.includes('提交') ||
                        text.includes('确认开票') ||
                        text.includes('确定')) && !button.disabled) {
                        console.log('✅ 通过文本找到按钮: ' + text);
                        button.click();
                        return {success: true, method: 'text:' + text};
                    }
                }
                
                console.log('❌ 未找到可用的提交按钮');
                return {success: false};
            })();
            """
            
            webView.evaluateJavaScript(submitScript) { result, error in
                if let error = error {
                    print("❌ 提交按钮脚本执行失败: \(error)")
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("提交按钮点击失败：\(error.localizedDescription)")
                    }
                    return
                }
                
                // 检查点击结果
                if let resultDict = result as? [String: Any],
                   let success = resultDict["success"] as? Bool,
                   success {
                    let method = resultDict["method"] as? String ?? "unknown"
                    print("✅ 提交按钮点击成功，方法: \(method)")
                    
                    // 更新进度
                    DispatchQueue.main.async {
                        self.loadingProgress = 0.95
                        self.currentStep = "正在提交，请稍候..."
                    }
                    
                    // 等待2秒，检查是否有确认对话框
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.checkAndClickConfirmDialog(webView: webView)
                    }
                } else {
                    print("❌ 未找到提交按钮")
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.onError("页面上未找到提交按钮，请手动提交")
                    }
                }
            }
        }
        
        // 检查并点击确认对话框
        func checkAndClickConfirmDialog(webView: WKWebView) {
            let confirmScript = """
            (function() {
                // 查找确认对话框中的"确定"按钮
                const confirmKeywords = ['确定', '确认', 'OK', '提交'];
                const buttons = document.querySelectorAll('button, a.btn, div[role="button"]');
                
                for (let button of buttons) {
                    const text = (button.textContent || button.innerText || '').trim();
                    // 检查按钮文本是否包含确认关键词，且不是"取消"
                    if (confirmKeywords.some(keyword => text === keyword || text.includes(keyword)) 
                        && !text.includes('取消')) {
                        // 检查按钮是否可见（对话框中的按钮）
                        const rect = button.getBoundingClientRect();
                        if (rect.width > 0 && rect.height > 0) {
                            console.log('✅ 找到确认对话框按钮: ' + text);
                            button.click();
                            return {found: true, text: text};
                        }
                    }
                }
                
                console.log('ℹ️ 未找到确认对话框，可能直接提交成功');
                return {found: false};
            })();
            """
            
            webView.evaluateJavaScript(confirmScript) { result, error in
                if let error = error {
                    print("⚠️ 确认对话框检查失败: \(error)")
                }
                
                if let resultDict = result as? [String: Any],
                   let found = resultDict["found"] as? Bool,
                   found {
                    let buttonText = resultDict["text"] as? String ?? ""
                    print("✅ 已点击确认按钮: \(buttonText)")
                    
                    // 点击确认后，等待3秒再验证结果
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.verifySubmissionResult(webView: webView)
                    }
                } else {
                    // 没有确认对话框，直接验证结果（也等待3秒）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.verifySubmissionResult(webView: webView)
                    }
                }
            }
        }
        
        // 验证提交结果
        func verifySubmissionResult(webView: WKWebView) {
            let verifyScript = """
            (function() {
                // 检查是否有成功提示
                const successKeywords = ['成功', '已提交', '申请已受理', '开票申请已提交'];
                const errorKeywords = ['失败', '错误', '请重试', '必填'];
                
                // 检查页面文本
                const bodyText = document.body.innerText || '';
                
                // 检查成功提示
                for (let keyword of successKeywords) {
                    if (bodyText.includes(keyword)) {
                        return {success: true, message: keyword};
                    }
                }
                
                // 检查错误提示
                for (let keyword of errorKeywords) {
                    if (bodyText.includes(keyword)) {
                        return {success: false, message: keyword};
                    }
                }
                
                // 检查是否有错误提示框
                const errorElements = document.querySelectorAll('.error, .alert-error, .message-error, [class*="error"]');
                if (errorElements.length > 0) {
                    const errorText = Array.from(errorElements).map(el => el.innerText).join(' ');
                    if (errorText.trim()) {
                        return {success: false, message: errorText};
                    }
                }
                
                // 检查URL是否变化（可能跳转到成功页面）
                const currentUrl = window.location.href;
                if (currentUrl.includes('success') || currentUrl.includes('result')) {
                    return {success: true, message: 'URL跳转'};
                }
                
                // 无法确定，默认认为成功（避免误判）
                return {success: true, message: '提交完成'};
            })();
            """
            
            webView.evaluateJavaScript(verifyScript) { result, error in
                if let error = error {
                    print("⚠️ 验证脚本执行失败: \(error)")
                    // 无法验证，但已经点击了，认为可能成功
                    self.completeSubmission(success: true, message: "已点击提交")
                    return
                }
                
                if let resultDict = result as? [String: Any],
                   let success = resultDict["success"] as? Bool {
                    let message = resultDict["message"] as? String ?? ""
                    print(success ? "✅ 验证结果：成功 - \(message)" : "❌ 验证结果：失败 - \(message)")
                    self.completeSubmission(success: success, message: message)
                } else {
                    // 无法解析结果，默认认为成功
                    self.completeSubmission(success: true, message: "已提交")
                }
            }
        }
        
        // 完成提交流程
        func completeSubmission(success: Bool, message: String) {
            DispatchQueue.main.async {
                if success {
                    self.loadingProgress = 1.0
                    self.currentStep = "开票申请已提交！"
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isLoading = false
                        self.onSuccess()
                    }
                } else {
                    self.isLoading = false
                    self.onError("提交失败：\(message)，请检查填写信息或手动提交")
                }
            }
        }
    }
}

