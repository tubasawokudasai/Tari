//
//  LaunchAtLoginManager.swift
//  Tari
//
//  Created by wjb on 2026/9/26.
//

import SwiftUI
import Combine
import ServiceManagement
import os

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled: Bool = false
    @Published var requiresApproval: Bool = false
    @Published var statusDescription: String? = nil
    @Published var errorMessage: String? = nil
    
    private init() {
        refreshStatus()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }
    
    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        requiresApproval = (status == .requiresApproval)
        
        switch status {
        case .enabled:
            statusDescription = nil
        case .requiresApproval:
            statusDescription = "自启动需在系统设置的「登录项」中批准"
        case .notRegistered:
            statusDescription = nil
        case .notFound:
            statusDescription = nil
        @unknown default:
            statusDescription = nil
        }
    }
    
    func setLaunchAtLogin(enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            errorMessage = "设置开机自启失败: \(error.localizedDescription)"
        }
        refreshStatus()
    }
    
    func openSystemLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
