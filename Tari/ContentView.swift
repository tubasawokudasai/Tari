import SwiftUI
import AppKit
import UniformTypeIdentifiers



struct ContentView: View {
    @State private var searchText = ""
    @State private var selectedId: UUID?
    @FocusState private var isSearchFocused: Bool
    @ObservedObject var clipboard: ClipboardManager
    
    init(clipboard: ClipboardManager) {
        self.clipboard = clipboard
    }
    
    // 拖拽排序相关状态
    @State private var draggedItem: ClipboardItem?
    
    // ✅ 新增：用于存储 ScrollView 的可见宽度，用来计算触发时机
    @State private var scrollViewWidth: CGFloat = 0
    
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
                // ✅ 1. 定义坐标空间名称
                ScrollView(.horizontal, showsIndicators: false) {
                    // ✅ 2. 换回 HStack 以支持拖拽排序
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
                        
                        // ✅ 3. 自定义触发器 (LoadMoreTrigger)
                        if clipboard.hasMoreData {
                            LoadMoreTrigger(
                                isLoading: clipboard.isLoading,
                                parentWidth: scrollViewWidth
                            ) { clipboard.loadMoreItems() }
                        }
                    }
                    // === 修改点 2：只保留垂直和右侧 padding ===
                    // 移除 .horizontal, 20，改为 .vertical 和 .trailing
                    // 左侧 padding 现在由上面的 Color.clear (8px) + spacing (12px) 代替了
                    .padding(.vertical, 10)
                    .padding(.trailing, 20)
                }
                .coordinateSpace(name: "SCROLL_SPACE") // ✅ 命名坐标空间
                // ✅ 获取 ScrollView 自身的宽度
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.size.width) { newWidth in scrollViewWidth = newWidth }
                            .onAppear { scrollViewWidth = geo.size.width }
                    }
                )
                .scrollClipDisabled()
                .onTapGesture {
                    selectedId = nil
                    PreviewWindowManager.shared.hidePreview()
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
                        }
                        // ✅ 唤醒后直接设置搜索焦点，方便用户直接搜索
                        isSearchFocused = true
                        selectedId = nil
                        PreviewWindowManager.shared.hidePreview()
                        
                        // 3. 重置标记
                        clipboard.shouldScrollToTop = false
                        print("DEBUG: 窗口唤醒，执行 UI 重置")
                    } else {
                        // ✅ 窗口只是获得焦点，但不需要滚动时，也设置搜索焦点
                        isSearchFocused = true
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
                // 如果当前有预览窗口打开，更新预览内容
                if let currentPreviewId = PreviewWindowManager.shared.currentPreviewId, currentPreviewId != newId {
                    if let selectedItem = clipboard.items.first(where: { $0.id == newId }) {
                        PreviewWindowManager.shared.showPreview(item: selectedItem, relativeTo: NSApp.keyWindow)
                    }
                }
            } else {
                PreviewWindowManager.shared.hidePreview()
            }
        }
        .onChange(of: isSearchFocused) { if $0 { selectedId = nil; PreviewWindowManager.shared.hidePreview() } }
        .background(KeyEventView { event in
            handleKeyEvent(event)
        })
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 51: // Delete
            if !isSearchFocused, let id = selectedId {
                clipboard.deleteItem(id: id)
                selectedId = clipboard.items.first?.id
                PreviewWindowManager.shared.hidePreview()
                return nil
            }
        case 8 where event.modifierFlags.contains(.command): // Cmd+C
            copySelectedItem()
            return nil
        case 49: // Space
            if let id = selectedId, let selectedItem = clipboard.items.first(where: { $0.id == id }) {
                PreviewWindowManager.shared.togglePreview(item: selectedItem, mainWindow: NSApp.keyWindow)
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
        // 1. 先写入剪贴板 (极快)
        clipboard.copyItemToClipboard(item: item)
        
        // 2. 立即隐藏窗口 (让用户感觉响应最快)
        NSApp.hide(nil)
        
        // 3. 将数据操作放到下一个 RunLoop 或后台，避免阻塞当前隐藏动画
        // 这一步只是更新 UI 排序，晚几百毫秒用户无感
        DispatchQueue.main.async {
            clipboard.moveItemToTop(id: item.id)
        }
        
        // 4. 执行粘贴
        // 这里的延时是为了等待“上一个应用”重新获得焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulateCmdV()
        }
    }
    
    // MARK: - 核心优化：使用 CGEvent 模拟按键
    private func simulateCmdV() {
        // 定义虚拟键码：V 键是 0x09
        let kVK_ANSI_V: CGKeyCode = 0x09
        
        // 创建按下事件 (Command + V)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let eventDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false) else {
            return
        }
        
        // 设置修饰键 (Command)
        eventDown.flags = .maskCommand
        eventUp.flags = .maskCommand // 抬起时也要保持 Command 状态
        
        // 发送事件到系统
        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
    }
    
    private func hideMainPanels() {
        NSApplication.shared.windows.forEach { if $0 is NSPanel { $0.orderOut(nil) } }
    }
}

// ✅ 4. 提取出来的触发器组件
// 这个组件的作用是：时刻计算自己在 "SCROLL_SPACE" 中的位置
struct LoadMoreTrigger: View {
    let isLoading: Bool
    let parentWidth: CGFloat
    let onLoad: () -> Void
    
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.frame(in: .named("SCROLL_SPACE")).minX) { minX in
                    // 核心逻辑：
                    // 如果触发器的左边缘 (minX) 小于 ScrollView 的宽度 (parentWidth)
                    // 说明触发器已经滑入屏幕（或者即将滑入），此时加载数据
                    // 加上 +100 的缓冲距离，让用户还没完全到底时就预加载
                    if minX < parentWidth + 100 && !isLoading {
                        onLoad()
                    }
                }
            // 初始化检测（防止一开始数据太少填不满屏幕时不加载）
                .onAppear {
                    let minX = geo.frame(in: .named("SCROLL_SPACE")).minX
                    if minX < parentWidth && !isLoading {
                        onLoad()
                    }
                }
        }
        .frame(width: 40, height: 1) // 给它一点宽度以便检测
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
