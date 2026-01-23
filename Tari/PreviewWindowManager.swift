import SwiftUI
import AppKit
import Combine

class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class PreviewWindowManager: ObservableObject {
    static let shared = PreviewWindowManager()
    
    private var previewPanel: NSPanel?
    private var hostingView: NSHostingView<PreviewDialog>?
    
    // 保存当前正在预览的 ID，用于 UI 状态绑定
    @Published var currentPreviewId: UUID?
    
    private init() {}
    
    func showPreview(itemID: UUID, relativeTo mainWindow: NSWindow?) {
        if previewPanel == nil {
            createPanel()
        }

        let contentView = PreviewDialog(
            itemID: itemID,
            onClose: { [weak self] in self?.hidePreview() }
        )

        if let hostingView {
            hostingView.rootView = contentView
        } else {
            let hv = NSHostingView(rootView: contentView)
            previewPanel?.contentView = hv
            hostingView = hv
        }

        if let mainFrame = mainWindow?.frame {
            let panelWidth: CGFloat = 560
            let xPos = mainFrame.minX + (mainFrame.width - panelWidth) / 2
            let yPos = mainFrame.maxY - 10
            previewPanel?.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }

        previewPanel?.orderFront(nil)
        currentPreviewId = itemID
    }
    
    func hidePreview() {
        previewPanel?.orderOut(nil)
        currentPreviewId = nil
    }
    
    func togglePreview(itemID: UUID, mainWindow: NSWindow?) {
        if currentPreviewId == itemID {
            hidePreview()
        } else {
            showPreview(itemID: itemID, relativeTo: mainWindow)
        }
    }
    
    private func createPanel() {
        let panel = PreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // 1. 🟢 设置背景全透明
        panel.backgroundColor = .clear 
        panel.isOpaque = false
        
        // 2. 🔴 核心修复：关闭系统自带阴影
        // 那个直角框就是它画的。关掉它，完全依赖你在 SwiftUI 里画的阴影。
        panel.hasShadow = false 
        
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating 
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.becomesKeyOnlyIfNeeded = false
        
        self.previewPanel = panel
    }

}