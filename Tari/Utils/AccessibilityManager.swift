//
//  AccessibilityManager.swift
//  Tari
//

import AppKit
import ApplicationServices

struct AccessibilityManager {
    /// 检查当前应用是否拥有辅助功能 (Accessibility) 权限
    /// - Parameter showAlertIfDisabled: 权限失效或未授权时，是否自动弹出 NSAlert 引导弹窗
    /// - Returns: 是否拥有有效权限
    @discardableResult
    static func checkAndRequestPermission(showAlertIfDisabled: Bool = true) -> Bool {
        // 1. 静默检查当前权限
        let isTrusted = AXIsProcessTrusted()
        
        if isTrusted {
            // 只要成功过一次，记录下来
            UserDefaults.standard.set(true, forKey: "hasRequestedAccessibility")
            return true
        }
        
        // 2. 检查是否是首次请求
        let hasRequested = UserDefaults.standard.bool(forKey: "hasRequestedAccessibility")
        
        if !hasRequested {
            // 首次请求：调用带 prompt 参数的 API，必定会触发 macOS 系统的原生弹窗。
            // 为了避免双重弹窗，此时我们直接返回，不再展示自定义 NSAlert。
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            UserDefaults.standard.set(true, forKey: "hasRequestedAccessibility")
            return false
        }
        
        // 3. 已经请求过，但目前无权限 (被用户拒绝、或因重新打包签名改变导致失效)
        // 此时 macOS 系统通常不会再主动弹窗，所以我们必须弹出我们自定义的单引导弹窗。
        if showAlertIfDisabled {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "需要重新授权辅助功能"
                alert.informativeText = "Tari 需要辅助功能权限来自动模拟 Cmd+V 进行粘贴。\n\n检测到应用权限尚未开启，或因重新打包/更新导致已有权限已失效。\n\n请在打开的系统设置中：\n1. 如果列表中已存在 Tari，请先选中并点击【减号 (-) 删除】\n2. 然后点击【加号 (+) 重新添加】或重新勾选 Tari。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "取消")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // 跳转至 macOS 系统设置中的“辅助功能”授权页面
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        
        return false
    }
}
