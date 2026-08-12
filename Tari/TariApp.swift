//
//  TariApp.swift
//  Tari
//
//  Created by wjb on 2025/12/20.
//

import SwiftUI

import SwiftUI

@main
struct TariApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("Tari", image: "StatusIcon") {
            Button("显示剪贴板") {
                appDelegate.togglePanel()
            }
            
            Divider()
            
            SettingsLink {
                Text("偏好设置...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("退出") {
                appDelegate.quitApp()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        
        Settings { SettingsView() }
    }
}
