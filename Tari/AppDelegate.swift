//
//  AppDelegate.swift
//  Tari
//
//  Created by wjb on 2025/12/20.
//

import SwiftUI
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleBottomClip = Self("toggleBottomClip", default: .init(.v, modifiers: [.command, .shift]))
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    let clipboardManager = ClipboardManager()
    var resetTask: DispatchWorkItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        setupPanel()
        KeyboardShortcuts.onKeyDown(for: .toggleBottomClip) { [weak self] in
            self?.togglePanel()
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    @objc func clearClipboard() {
        clipboardManager.clearAll()
    }
    
    func setupPanel() {
        guard let screen = NSScreen.main else { return }
        let screenWidth = screen.frame.width
        let fixedHeight: CGFloat = 320
        
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: screenWidth, height: 320),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered, defer: false
        )
        
        panel?.isMovable = false
        panel?.level = .statusBar
        panel?.backgroundColor = .clear
        panel?.hasShadow = true
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.becomesKeyOnlyIfNeeded = true
        
        // 监听窗口失去焦点事件，直接关闭面板
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.closePanel()
        }
        
        let contentView = ContentView(clipboard: clipboardManager)
        panel?.contentView = NSHostingView(rootView: contentView)
        panel?.setFrame(NSRect(x: 0, y: 0, width: screenWidth, height: fixedHeight), display: true)
    }
    
    // --- 核心修改 2：提取统一的关闭逻辑 ---
    func closePanel() {
        guard let panel = panel, panel.isVisible else { return }
        
        // 1. 关闭预览窗口 (如果存在)
        PreviewWindowManager.shared.hidePreview()
        
        // 2. 隐藏窗口
        panel.orderOut(nil)
        
        // 3. 创建延迟重置任务
        let task = DispatchWorkItem { [weak self] in
            print("DEBUG: 执行延迟重置任务") // 可以在这里打断点验证
            self?.clipboardManager.pruneToFirstPage()
            
            // 每次关闭面板后，顺便清理过期和超量记录
            ClipboardDataStore.shared.cleanUpOldAndExcessItems()
        }
        
        self.resetTask = task
        
        // 4. 0.6秒后执行
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }
    
    @objc func togglePanel() {
        guard let panel = panel else { return }
        
        if panel.isVisible {
            // === 关闭逻辑 ===
            closePanel() // 直接调用封装的方法
        } else {
            // === 打开逻辑 ===
            
            // 关键：一旦唤醒，立即取消之前的重置任务
            resetTask?.cancel()
            resetTask = nil
            
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

extension NSPanel {
    override open var canBecomeKey: Bool {
        return true
    }
}
