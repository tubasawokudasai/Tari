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
    static let toggleBottomClip = Self("toggleBottomClip")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    let clipboardManager = ClipboardManager()
    var statusItem: NSStatusItem?
    
    // 用于存储延迟重置的任务
    var resetTask: DispatchWorkItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        setupPanel()
        setupStatusBar()
        KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .toggleBottomClip)
        KeyboardShortcuts.onKeyDown(for: .toggleBottomClip) { [weak self] in
            self?.togglePanel()
        }
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Tari")
            button.action = #selector(togglePanel)
        }
        createMenu()
    }
    
    func createMenu() {
        let menu = NSMenu()
        let showMenuItem = NSMenuItem(title: "显示剪贴板", action: #selector(togglePanel), keyEquivalent: "v")
        showMenuItem.keyEquivalentModifierMask = [.command, .shift]
        showMenuItem.target = self
        menu.addItem(showMenuItem)
        menu.addItem(NSMenuItem.separator())
        let quitMenuItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        statusItem?.menu = menu
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
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
        panel?.level = .popUpMenu
        panel?.backgroundColor = .clear
        panel?.hasShadow = true
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.becomesKeyOnlyIfNeeded = true
        
        // --- 核心修改 1：失去焦点时，调用统一的 closePanel ---
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            // 延时一点点，防止误判
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !(self.panel?.isKeyWindow ?? false) {
                    // 这里原本只写了 orderOut，现在改为调用封装好的 closePanel
                    self.closePanel()
                }
            }
        }
        
        let contentView = ContentView(clipboard: clipboardManager)
        panel?.contentView = NSHostingView(rootView: contentView)
        panel?.setFrame(NSRect(x: 0, y: 0, width: screenWidth, height: fixedHeight), display: true)
    }
    
    // --- 核心修改 2：提取统一的关闭逻辑 ---
    func closePanel() {
        guard let panel = panel, panel.isVisible else { return }
        
        // 1. 隐藏窗口
        panel.orderOut(nil)
        
        // 2. 发送关闭预览通知
        NotificationCenter.default.post(name: Notification.Name("ClosePreviewWindow"), object: nil)
        
        // 3. 创建延迟重置任务
        let task = DispatchWorkItem { [weak self] in
            print("DEBUG: 执行延迟重置任务") // 可以在这里打断点验证
            self?.clipboardManager.pruneToFirstPage()
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
