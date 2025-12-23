import SwiftUI
import AppKit
import UniformTypeIdentifiers

// 窗口委托实现，用于处理点击其他区域关闭预览
class PreviewWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        onClose()
    }
}

struct ContentView: View {
    @State private var searchText = ""
    @State private var selectedId: UUID?
    @State private var previewWindow: NSWindow?
    @State private var previewWindowDelegate: PreviewWindowDelegate?
    @FocusState private var isSearchFocused: Bool
    @ObservedObject var clipboard: ClipboardManager
    
    init(clipboard: ClipboardManager) {
        self.clipboard = clipboard
    }
    
    // 拖拽排序相关状态
    @State private var draggedItem: ClipboardItem?
    
    private let closePreviewNotification = NotificationCenter.default.publisher(for: Notification.Name("ClosePreviewWindow"))
    
    // 添加窗口焦点监听
    private let windowDidBecomeKey = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
    
    var displayItems: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboard.items
        } else {
            return clipboard.items.filter { item in
                item.text.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    


    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("搜索剪贴板...", text: $searchText)
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _ in clipboard.resetPagination() }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: 260)
            .background(Color.white.opacity(0.4))
            .cornerRadius(6)
            .padding(.top, 15)
            .padding(.bottom, 5)
            .zIndex(10)
            
            // 修改：包裹 ScrollViewReader
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // === 修改点 1：调整锚点宽度 === 
                        // 目标边距 20 - spacing 12 = 8 
                        // 这样当 scroll 到这个锚点时，屏幕左边会正好留出 8(锚点) + 12(间距) = 20 的空白 
                        Color.clear
                            .frame(width: 8, height: 1)
                            .id("SCROLL_TO_TOP_ANCHOR")
                        
                        // 修改点：直接遍历 items 而不是 indices，避免数组变动时的越界崩溃
                        // 注意：这里我们假设 item.id 是唯一的
                        ForEach(displayItems, id: \.id) { item in
                            DraggableItemCard(
                                item: item,
                                isSelected: selectedId == item.id,
                                onTapSelect: { selectedId = item.id },
                                onTapDouble: {
                                    selectedId = item.id
                                    copyAndPaste(item: item)
                                },
                                draggedItem: $draggedItem,
                                clipboard: clipboard
                            )
                            .id(item.id)
                        }
                        
                        if clipboard.hasMoreData {
                            Color.clear.frame(width: 20).onAppear { clipboard.loadMoreItems() }
                        }
                    }
                    // === 修改点 2：只保留垂直和右侧 padding === 
                    // 移除 .horizontal, 20，改为 .vertical 和 .trailing 
                    // 左侧 padding 现在由上面的 Color.clear (8px) + spacing (12px) 代替了 
                    .padding(.vertical, 10)
                    .padding(.trailing, 20)
                }
                .scrollClipDisabled()
                .onTapGesture {
                    selectedId = nil
                    isSearchFocused = false
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                
                // === 核心修复：监听窗口唤醒 ===
                .onReceive(windowDidBecomeKey) { _ in
                    // 只有当 Manager 标记需要重置时，才执行滚动
                    if clipboard.shouldScrollToTop {
                        // 1. 瞬间滚动到顶部
                        proxy.scrollTo("SCROLL_TO_TOP_ANCHOR", anchor: .leading)
                        
                        // 2. 清理搜索状态
                        if !searchText.isEmpty {
                            searchText = ""
                            isSearchFocused = false
                        }
                        selectedId = nil
                        
                        // 3. 重置标记
                        clipboard.shouldScrollToTop = false
                        print("DEBUG: 窗口唤醒，执行 UI 重置")
                    }
                }
            }
            
            Spacer(minLength: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 24))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .onChange(of: selectedId) { newId in
            if newId != nil {
                isSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
                if previewWindow != nil, let id = newId { showPreviewWindow(for: id) }
            }
        }
        .onChange(of: isSearchFocused) { if $0 { selectedId = nil } }
        .background(KeyEventView { event in
            handleKeyEvent(event)
        })
        .onReceive(closePreviewNotification) { _ in hidePreviewWindow() }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 51: // Delete
            if !isSearchFocused, let id = selectedId {
                clipboard.deleteItem(id: id)
                selectedId = clipboard.items.first?.id
                return nil
            }
        case 8 where event.modifierFlags.contains(.command): // Cmd+C
            copySelectedItem()
            return nil
        case 49: // Space
            if let id = selectedId {
                previewWindow != nil ? hidePreviewWindow() : showPreviewWindow(for: id)
            }
            return nil
        default: break
        }
        return event
    }
    
    func copySelectedItem() {
        guard let id = selectedId, let item = clipboard.items.first(where: { $0.id == id }) else { return }
        clipboard.copyItemToClipboard(item: item)
        clipboard.moveItemToTop(id: id)
        hideMainPanels()
    }

    func copyAndPaste(item: ClipboardItem) {
        clipboard.copyItemToClipboard(item: item)
        clipboard.moveItemToTop(id: item.id)
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let script = NSAppleScript(source: "tell application \"System Events\" to keystroke \"v\" using command down")
            script?.executeAndReturnError(nil)
        }
    }

    private func hideMainPanels() {
        NSApplication.shared.windows.forEach { if $0 is NSPanel { $0.orderOut(nil) } }
    }

    private func showPreviewWindow(for itemId: UUID) {
        hidePreviewWindow()
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered, defer: false
        )
        window.level = .statusBar
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: PreviewView(itemId: itemId, manager: clipboard) { self.hidePreviewWindow() })
        
        // 隐藏标题栏按钮（红绿灯）
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        
        // 添加圆角
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true
        
        // 允许通过窗口背景拖动
        window.isMovableByWindowBackground = true
        
        window.center()
        window.orderFront(nil)
        
        // 点击其他区域关闭预览
        previewWindowDelegate = PreviewWindowDelegate(onClose: { self.hidePreviewWindow() })
        window.delegate = previewWindowDelegate
        
        self.previewWindow = window
    }

    private func hidePreviewWindow() {
        previewWindow?.delegate = nil
        previewWindow?.orderOut(nil)
        previewWindow = nil
        previewWindowDelegate = nil
    }
}

// 提取可拖拽的卡片到单独的结构体，减少 ContentView 的复杂性
struct DraggableItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    @Binding var draggedItem: ClipboardItem?
    @ObservedObject var clipboard: ClipboardManager
    
    var body: some View {
        ItemCard(
            item: item,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
            onTapDouble: onTapDouble
        )
        // ✅ 核心修复：onDrag 和 dropDestination 必须在同一个 View 层级上
        .onDrag {
            // 1. 立即锁定拖拽对象
            if NSApp.isActive {
                self.draggedItem = item
            }
            // 2. 调用模型的方法生成数据
            return item.createItemProvider()
        }
        .dropDestination(for: ClipboardItem.self) { items, _ in
            self.draggedItem = nil
            return true
        } isTargeted: { isTargeted in
            handleDropTargetChange(isTargeted: isTargeted)
        }
    }
    
    private func handleDropTargetChange(isTargeted: Bool) {
        guard isTargeted, let dragged = draggedItem, dragged.id != item.id else { return }
        
        if let sourceIndex = clipboard.items.firstIndex(where: { $0.id == dragged.id }),
           let targetIndex = clipboard.items.firstIndex(where: { $0.id == item.id }) {
            
            if sourceIndex != targetIndex {
                withAnimation(.spring()) {
                    clipboard.moveItem(from: sourceIndex, to: targetIndex)
                }
            }
        }
    }
}
