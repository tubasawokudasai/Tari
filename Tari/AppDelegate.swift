//
//  AppDelegate.swift
//  Tari
//
//  Created by wjb on 2025/12/20.
//

import SwiftUI
import AppKit
import KeyboardShortcuts

// 定义快捷键名称
extension KeyboardShortcuts.Name {
    static let toggleBottomClip = Self("toggleBottomClip")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    let clipboardManager = ClipboardManager()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为菜单栏应用（不在Dock中显示）
        NSApplication.shared.setActivationPolicy(.accessory)
        
        setupPanel()
        setupStatusBar()
        
        // 设置默认快捷键为 Command + Shift + V
        KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .toggleBottomClip)
        
        // 监听快捷键按下
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
        
        // 显示主面板菜单项
        let showMenuItem = NSMenuItem(title: "显示剪贴板", action: #selector(togglePanel), keyEquivalent: "")
        showMenuItem.target = self
        menu.addItem(showMenuItem)
        
        // 分隔线
        menu.addItem(NSMenuItem.separator())
        
        // 退出应用菜单项
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

        // 修改：移除 didResignKey 的自动隐藏预览逻辑，只保留面板本身隐藏
        // （防止焦点切换时意外关闭预览）
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !(self.panel?.isKeyWindow ?? false) {
                    self.panel?.orderOut(nil)
                    // 移除：不再在这里发送关闭预览的通知，避免弹出预览时瞬间关闭
                }
            }
        }

        let contentView = ContentView(clipboard: clipboardManager)
        panel?.contentView = NSHostingView(rootView: contentView)
        panel?.setFrame(NSRect(x: 0, y: 0, width: screenWidth, height: fixedHeight), display: true)
    }

    @objc func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            // 新增：只有在显式隐藏主面板时，才关闭预览窗口
            NotificationCenter.default.post(name: Notification.Name("ClosePreviewWindow"), object: nil)
        } else {
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
