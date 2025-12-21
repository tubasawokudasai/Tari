import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var searchText = ""
    @State private var selectedId: UUID?
    @State private var previewWindow: NSWindow?
    @FocusState private var isSearchFocused: Bool
    @ObservedObject var clipboard: ClipboardManager
    
    init(clipboard: ClipboardManager) {
        self.clipboard = clipboard
    }
    
    // 拖拽排序相关状态
    @State private var draggedItem: ClipboardItem?
    
    private let closePreviewNotification = NotificationCenter.default.publisher(for: Notification.Name("ClosePreviewWindow"))
    
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
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
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
                            onDragStart: { 
                                // 只有当 App 是激活状态且确实在拖拽时才记录日志
                                if NSApp.isActive {
                                    DispatchQueue.main.async {
                                        self.draggedItem = item
                                    }
                                }
                            },
                            draggedItem: $draggedItem,
                            clipboard: clipboard
                        )
                    }
                    
                    if clipboard.hasMoreData {
                        Color.clear.frame(width: 20).onAppear { clipboard.loadMoreItems() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10) // 增加一点垂直空间给阴影
            }
            .scrollClipDisabled()
            .onTapGesture {
                selectedId = nil
                isSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
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
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.level = .statusBar
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: PreviewView(itemId: itemId, manager: clipboard) { self.hidePreviewWindow() })
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.previewWindow = window
    }

    private func hidePreviewWindow() {
        previewWindow?.orderOut(nil)
        previewWindow = nil
    }
}

// 提取可拖拽的卡片到单独的结构体，减少 ContentView 的复杂性
struct DraggableItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    let onDragStart: () -> Void
    @Binding var draggedItem: ClipboardItem?
    @ObservedObject var clipboard: ClipboardManager
    
    var body: some View {
        ItemCard(
            item: item,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
            onTapDouble: onTapDouble,
            onDragStart: {
                print("DEBUG: 开始拖拽 item: \(item.text.prefix(20))")
                onDragStart()
            }
        )
        // 拖放目标用于内部排序
        .dropDestination(for: ClipboardItem.self) { items, _ in
            // 只有当拖拽的是内部定义的 ClipboardItem 时才处理排序
            // 这里的 items 是通过 Transferable 协议解码出来的
            handleDropCompletion()
            return true
        } isTargeted: { isTargeted in
            handleDropTargetChange(isTargeted: isTargeted)
        }
    }
    
    // 将复杂逻辑提取到单独的函数中，帮助编译器进行类型检查
    private func handleDropCompletion() {
        print("DEBUG: 拖拽放置完成")
        self.draggedItem = nil
    }
    
    private func handleDropTargetChange(isTargeted: Bool) {
        guard isTargeted, let dragged = draggedItem, dragged.id != item.id else { return }
        
        // 提取索引查找逻辑
        guard let sourceIndex = findSourceIndex(dragged: dragged),
              let targetIndex = findTargetIndex() else { return }
        
        print("DEBUG: 排序触发: \(sourceIndex) -> \(targetIndex)")
        withAnimation(.spring()) {
            clipboard.moveItem(from: sourceIndex, to: targetIndex)
        }
    }
    
    private func findSourceIndex(dragged: ClipboardItem) -> Int? {
        return clipboard.items.firstIndex(where: { $0.id == dragged.id })
    }
    
    private func findTargetIndex() -> Int? {
        return clipboard.items.firstIndex(where: { $0.id == item.id })
    }
}
