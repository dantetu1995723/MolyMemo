import UIKit
import Vision

// 二维码识别工具类
class QRCodeScanner {
    
    // 从图片中识别二维码
    static func detectQRCode(in image: UIImage) async throws -> String? {
        guard let ciImage = CIImage(image: image) else {
            print("⚠️ 无法转换为 CIImage")
            return nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error = error {
                    print("❌ 二维码识别失败: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = request.results as? [VNBarcodeObservation],
                      let firstBarcode = results.first,
                      let payload = firstBarcode.payloadStringValue else {
                    print("⚠️ 未检测到二维码")
                    continuation.resume(returning: nil)
                    return
                }
                
                print("✅ 检测到二维码: \(payload)")
                continuation.resume(returning: payload)
            }
            
            // 只识别二维码类型
            request.symbologies = [.qr]
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ 执行识别请求失败: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    // 批量识别多张图片中的二维码
    static func detectQRCodes(in images: [UIImage]) async -> [String] {
        var qrCodes: [String] = []
        
        for (index, image) in images.enumerated() {
            print("🔍 正在识别第 \(index + 1)/\(images.count) 张图片...")
            
            if let qrCode = try? await detectQRCode(in: image) {
                qrCodes.append(qrCode)
                print("✅ 第 \(index + 1) 张图片识别成功")
            } else {
                print("⚠️ 第 \(index + 1) 张图片未检测到二维码")
            }
        }
        
        return qrCodes
    }
    
    // 判断二维码是否是发票开票链接
    static func isInvoiceQRCode(_ qrCode: String) -> Bool {
        let preview = qrCode.count > 100 ? "\(qrCode.prefix(100))..." : qrCode
        print("🔍 判断二维码类型")
        print("   内容: \(preview)")

        // 常见的发票开票平台域名
        let invoiceDomains = [
            // 诺诺发票
            "nnfp.jss.com.cn",
            "fapiao.jss.com.cn",
            "invoice.jss.com.cn",
            // 百望云
            "fp.baiwang.com",
            "invoice.baiwang.com",
            // 航天信息
            "51fapiao.cn",
            "fapiao.aisino.com",
            // 发票通
            "fapiao.com",
            "invoice.com",
            // 票通
            "yun88.com",
            "fp.yun88.com",
            // 高灯科技
            "17doubao.com",
            "fp.17doubao.com",
            // 微信发票助手
            "fapiao.qq.com",
            "fp.wechat.com",
            // 支付宝发票管家
            "fapiao.alipay.com",
            "invoice.alipay.com",
            // 美团
            "fapiao.meituan.com",
            // 饿了么
            "fapiao.ele.me",
            // 滴滴出行
            "fapiao.didiglobal.com",
            "fapiao.xiaojukeji.com",
            // 京东
            "fapiao.jd.com",
            // 税友软件
            "fp.servyou.com.cn",
            // 其他通用
            "kp.com"
        ]

        // 检查是否包含发票相关域名
        var matchedDomain: String?
        for domain in invoiceDomains {
            if qrCode.contains(domain) {
                matchedDomain = domain
                break
            }
        }
        
        let hasDomain = matchedDomain != nil
        if hasDomain {
            print("   ✅ 匹配到开票域名: \(matchedDomain!)")
        }

        // 检查是否包含发票相关关键词（URL参数等）
        let hasInvoiceKeyword = qrCode.contains("fapiao") ||
                                qrCode.contains("invoice") ||
                                qrCode.contains("开票")
        
        if hasInvoiceKeyword && !hasDomain {
            print("   ✅ 包含开票关键词（fapiao/invoice/开票）")
        }

        let isInvoice = hasDomain || hasInvoiceKeyword
        
        if isInvoice {
            print("   ✅ 判定为开票二维码")
        } else {
            print("   ❌ 不是开票二维码")
            print("   原因: 不包含已知开票域名，也不包含开票关键词")
            
            // 帮助诊断：检查是否是URL
            if qrCode.hasPrefix("http://") || qrCode.hasPrefix("https://") {
                print("   提示: 这是一个URL，但不是开票链接")
            } else {
                print("   提示: 这不是URL格式，可能是普通信息码")
            }
        }

        return isInvoice
    }
}

