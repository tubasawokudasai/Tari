import SwiftUI
import AppKit
import Combine

class PreviewWindowManager: ObservableObject {
    static let shared = PreviewWindowManager()
    
    private var previewPanel: NSPanel?
    
    // 保存当前正在预览的 ID，用于 UI 状态绑定
    @Published var currentPreviewId: UUID?
    
    private init() {}
    
    func showPreview(item: ClipboardItem, relativeTo mainWindow: NSWindow?) {
        // 1. 如果窗口不存在，创建它
        if previewPanel == nil {
            createPanel()
        }
        
        // 2. 更新内容
        // 这里我们把 PreviewDialog 包装在 NSHostingView 中
        // 注意：我们需要传入 onClose 回调
        let contentView = PreviewDialog(
            item: item,
            onClose: { [weak self] in self?.hidePreview() },
            clipboard: ClipboardManager() // 这里其实只需用来复制，稍微调整 PreviewDialog 逻辑即可
        )
        
        previewPanel?.contentView = NSHostingView(rootView: contentView)
        
        // 3. 计算位置：在主窗口正上方
        if let mainFrame = mainWindow?.frame {
            // 预览窗口大小 (假设 PreviewDialog 是固定的或者自适应的，这里给个大概初始值，SwiftUI 会撑开)
            let panelWidth: CGFloat = 450
            let panelHeight: CGFloat = 400
            
            // 水平居中于主窗口
            let xPos = mainFrame.minX + (mainFrame.width - panelWidth) / 2
            
            // 垂直位于主窗口上方 (留 10px 间距)
            let yPos = mainFrame.maxY + 10
            
            previewPanel?.setFrame(NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight), display: true)
        }
        
        // 4. 显示窗口 (不激活，这样焦点还在搜索框)
        previewPanel?.orderFront(nil)
        currentPreviewId = item.id
    }
    
    func hidePreview() {
        previewPanel?.orderOut(nil)
        currentPreviewId = nil
    }
    
    func togglePreview(item: ClipboardItem, mainWindow: NSWindow?) {
        if currentPreviewId == item.id {
            hidePreview()
        } else {
            showPreview(item: item, relativeTo: mainWindow)
        }
    }
    
    private func createPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView], // 无边框
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating // 保证浮在普通窗口上面
        panel.isMovableByWindowBackground = false
        
        // 这一步很关键：让它不抢夺主窗口的焦点
        panel.becomesKeyOnlyIfNeeded = true
        
        self.previewPanel = panel
    }
}