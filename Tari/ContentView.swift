import SwiftUI
import AppKit
import UniformTypeIdentifiers



struct ContentView: View {
    @State private var selectedId: UUID?
    @State private var lastSelectedId: UUID?
    @FocusState private var isSearchFocused: Bool
    @ObservedObject var clipboard: ClipboardManager
    
    init(clipboard: ClipboardManager) {
        self.clipboard = clipboard
    }
    
    // 拖拽排序已移除
    
    // ✅ 新增：用于存储 ScrollView 的可见宽度，用来计算触发时机
    @State private var scrollViewWidth: CGFloat = 0
    
    // ✅ 新增：用于触发相对时间更新的状态变量
    @State private var lastWakeUpTime: Date = Date()
    

    // 添加窗口焦点监听
    private let windowDidBecomeKey = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
    private let windowDidResignKey = NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
    
    // 直接使用 clipboard.items，搜索逻辑已移至 ClipboardManager
    var displayItems: [ClipboardListItem] {
        return clipboard.items
    }
    
    
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("搜索剪贴板...", text: $clipboard.searchText)
                    .focused($isSearchFocused)
                    .onChange(of: clipboard.searchText) { newText in 
                        clipboard.searchItems(text: newText)
                    }
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
                    HStack(spacing: 24) {
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
                                clipboard: clipboard,
                                lastWakeUpTime: lastWakeUpTime,
                                scrollViewWidth: scrollViewWidth
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
                    .padding(.top, 10)
                    .padding(.bottom, 30) // 增加底部间距
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
                .onReceive(windowDidBecomeKey) { notification in
                    // 检查新获得焦点的窗口是否是预览窗口，如果是，则忽略
                    // 检查新获得焦点的窗口是否是预览窗口，如果是，则忽略
                    if PreviewWindowManager.shared.currentPreviewId != nil {
                        return
                    }
                    
                    // ✅ 更新唤醒时间，触发相对时间重新计算
                    lastWakeUpTime = Date()
                    
                    // 只有当 Manager 标记需要重置时，才执行滚动
                    if clipboard.shouldScrollToTop {
                        // 1. 瞬间滚动到顶部
                        proxy.scrollTo("SCROLL_TO_TOP_ANCHOR", anchor: .leading)
                        
                        // 2. 清理搜索状态
                        if !clipboard.searchText.isEmpty {
                            clipboard.searchItems(text: "")
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
                .onReceive(windowDidResignKey) { _ in
                    lastSelectedId = nil
                }
                .onChange(of: selectedId) { newId in
                    if let id = newId {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            
            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .onChange(of: selectedId) { newId in
            if newId != nil {
                isSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
                // 如果当前有预览窗口打开，或者刚刚才关闭(0.2秒内)，更新预览内容
                if PreviewWindowManager.shared.wasRecentlyOpen() {
                    PreviewWindowManager.shared.currentPreviewId = newId
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
            if !isSearchFocused, let id = selectedId {
                PreviewWindowManager.shared.togglePreview(itemID: id)
                return nil
            }
        case 123: // Left arrow
            if !isSearchFocused {
                selectPreviousItem()
                return nil
            }
        case 124: // Right arrow
            if !isSearchFocused {
                selectNextItem()
                return nil
            }
        case 125: // Down arrow (optional usability enhancement to jump to list)
            if isSearchFocused {
                if !clipboard.items.isEmpty {
                    if let lastId = lastSelectedId, clipboard.items.contains(where: { $0.id == lastId }) {
                        selectedId = lastId
                    } else {
                        selectedId = clipboard.items.first?.id
                    }
                    return nil
                }
            }
        case 126: // Up arrow (focus search bar)
            if !isSearchFocused {
                lastSelectedId = selectedId
                isSearchFocused = true
                return nil
            }
        default: break
        }
        return event
    }
    
    private func selectPreviousItem() {
        let items = clipboard.items
        guard !items.isEmpty else { return }
        if let id = selectedId, let index = items.firstIndex(where: { $0.id == id }) {
            if index > 0 {
                selectedId = items[index - 1].id
            }
        } else {
            selectedId = items.first?.id
        }
    }

    private func selectNextItem() {
        let items = clipboard.items
        guard !items.isEmpty else { return }
        if let id = selectedId, let index = items.firstIndex(where: { $0.id == id }) {
            if index < items.count - 1 {
                selectedId = items[index + 1].id
            }
        } else {
            selectedId = items.first?.id
        }
    }
    
    func copySelectedItem() {
        guard let id = selectedId else { return }
        clipboard.copyItemToClipboard(id: id)
        clipboard.moveItemToTop(id: id)
        hideMainPanels()
    }
    
    func copyAndPaste(item: ClipboardListItem) {
        // 1. 先写入剪贴板 (极快)
        clipboard.copyItemToClipboard(id: item.id)
        
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
    let item: ClipboardListItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    @ObservedObject var clipboard: ClipboardManager
    let lastWakeUpTime: Date
    let scrollViewWidth: CGFloat
    
    @ObservedObject var previewManager = PreviewWindowManager.shared
    
    var body: some View {
        ItemCard(
            item: item,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
            onTapDouble: onTapDouble,
            lastWakeUpTime: lastWakeUpTime
        )
        .id("\(item.id)-\(lastWakeUpTime.timeIntervalSince1970)")
        .popover(isPresented: Binding(
            get: { previewManager.currentPreviewId == item.id },
            set: { isVisible in
                if !isVisible && previewManager.currentPreviewId == item.id {
                    previewManager.hidePreview()
                }
            }
        ), arrowEdge: .top) {
            PreviewDialog(itemID: item.id, onClose: { previewManager.hidePreview() })
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .named("SCROLL_SPACE"))) { newRect in
                        if previewManager.currentPreviewId == item.id {
                            if newRect.maxX < 0 || newRect.minX > scrollViewWidth {
                                previewManager.hidePreview()
                            }
                        }
                    }
            }
        )
        .onDrag {
            let provider = NSItemProvider()
            
            // 从 Core Data 加载实际数据供外部应用使用
            if let archivedData = ClipboardDataStore.shared.fetchArchivedData(id: item.id) {
                var allItemsData: [[String: Data]] = []
                if let newFormat = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [[String: Data]] {
                    allItemsData = newFormat
                } else if let oldFormat = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [String: Data] {
                    allItemsData = [oldFormat]
                }
                
                if let firstItem = allItemsData.first {
                    for (typeRaw, data) in firstItem {
                        if typeRaw == "org.nspasteboard.source" { continue }
                        provider.registerDataRepresentation(forTypeIdentifier: typeRaw, visibility: .all) { completion in
                            completion(data, nil)
                            return nil
                        }
                    }
                }
            } else {
                provider.registerObject(item.text as NSString, visibility: .all)
            }
            
            return provider
        }
    }
}
