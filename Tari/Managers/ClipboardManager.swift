import AppKit
import Combine
import CoreData
import SwiftUI

class ClipboardManager: ObservableObject {
    // 暴露给 View 的数据源
    @Published var items: [ClipboardItem] = []
    
    // 分页相关属性
    @Published var currentPage = 0
    @Published var pageSize = 20
    @Published var hasMoreData = true
    @Published var isLoading = false
    
    // 新增：标记是否需要滚动回顶部
    @Published var shouldScrollToTop = false
    
    private var timer: AnyCancellable?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = NSPasteboard.general.changeCount
    
    // Core Data 上下文
    private let context = PersistenceController.shared.container.viewContext

    init() {
        // 1. 启动时加载第一页数据
        loadMoreItems()
        
        // 2. 启动剪贴板监听
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClipboard()
            }
    }

    // MARK: - Core Data 操作
    
    private func fetchItems(page: Int) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        // 按时间倒序：最新的在最上面
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = pageSize
        request.fetchOffset = page * pageSize
        
        do {
            let entities = try context.fetch(request)
            hasMoreData = entities.count >= pageSize
            
            return entities.compactMap { (entity: ClipboardEntity) -> ClipboardItem? in
            guard let id = entity.id,
                  let text = entity.text,
                  let time = entity.timestamp,
                  let contentTypeString = entity.contentType else { return nil }
            
            let contentType = ClipboardContentType(rawValue: contentTypeString) ?? .unknown
            // 使用timestamp作为creationTime，如果有专门的creationTime字段则使用它
            let creationTime = entity.creationTime ?? time
            
            return ClipboardItem(
                id: id, 
                text: text, 
                timestamp: time,
                creationTime: creationTime,
                contentType: contentType,
                additionalData: entity.additionalData
            )
        }
        } catch {
            print("Fetch failed: \(error)")
            hasMoreData = false
            return []
        }
    }
    
    func loadMoreItems() {
        // ✅ 检查锁
        guard hasMoreData, !isLoading else { return }
        isLoading = true  
        
        let pageToLoad = currentPage
        let newItems = fetchItems(page: pageToLoad)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.currentPage == 0 {
                self.items = newItems
            } else {
                let existingIDs = Set(self.items.map { $0.id })
                let uniqueNewItems = newItems.filter { !existingIDs.contains($0.id) }
                self.items.append(contentsOf: uniqueNewItems)
            }
            
            if !newItems.isEmpty {
                self.currentPage += 1
            }
            
            self.isLoading = false // ✅ 解锁
        }
    }
    
    func resetPagination() {
        currentPage = 0
        hasMoreData = true
        // 注意：不要立即清空 items，否则 UI 会闪烁，loadMoreItems 会替换它们
        loadMoreItems()
    }
    
    // MARK: - 增删改查
    
    private func saveNewItem(text: String, contentType: ClipboardContentType, additionalData: Data? = nil) {
        let newId = UUID()
        let currentDate = Date()
        let newItem = ClipboardItem(id: newId, text: text, timestamp: currentDate, creationTime: currentDate, contentType: contentType, additionalData: additionalData)
        
        DispatchQueue.main.async {
            self.items.insert(newItem, at: 0)
            // 插入新数据后，需要调整一下后续数据的状态或简单地重新标记
        }
        
        context.perform {
            let newEntity = ClipboardEntity(context: self.context)
            newEntity.id = newId
            newEntity.text = text
            newEntity.timestamp = currentDate
            newEntity.creationTime = currentDate
            newEntity.contentType = contentType.rawValue
            newEntity.additionalData = additionalData
            
            try? PersistenceController.shared.save()
        }
    }
    
    func deleteItem(id: UUID) {
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == id }
        }
        
        context.perform {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            if let results = try? self.context.fetch(request), let entity = results.first {
                self.context.delete(entity)
                try? PersistenceController.shared.save()
            }
        }
    }
    
    func deleteAllItems() {
        DispatchQueue.main.async {
            self.items.removeAll()
            self.currentPage = 0
        }
        
        context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = ClipboardEntity.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try? self.context.execute(deleteRequest)
            try? self.context.save()
        }
    }
    
    // MARK: - 状态重置
    
    /// 将数据裁剪回第一页，释放内存，重置分页索引
    func pruneToFirstPage() {
        if items.count > pageSize {
            items = Array(items.prefix(pageSize))
            currentPage = 1
            hasMoreData = true
            
            // === 核心修复：标记需要滚动 ===
            // 这里不发送通知，而是设置标记，等 View 可见时自己处理
            DispatchQueue.main.async {
                self.shouldScrollToTop = true
            }
            print("DEBUG: 内存已释放，保留前 \(items.count) 个条目，标记下次唤醒需回滚顶部")
        } else {
            // 即使没有释放内存（数据很少），如果是延迟重置触发的，也应该回滚
            // 为了体验一致性，这里也设置标记
            DispatchQueue.main.async {
                self.shouldScrollToTop = true
            }
            print("DEBUG: 数据量不大无需释放内存，但标记下次唤醒需回滚顶部")
        }
    }
    
    // MARK: - 排序核心逻辑 (修复版)
    
    func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        // 1. 范围检查
        guard sourceIndex != destinationIndex,
              sourceIndex < items.count,
              destinationIndex < items.count else { return }
        
        // 2. 内存移动 (立即响应 UI)
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: destinationIndex)
        
        // 3. 重新计算时间戳以确保持久化顺序
        // 逻辑：以当前列表中第一个元素的时间（或当前时间）为基准
        // 依次向下递减微小的时间间隔。这样保证 Index 0 时间最新，Index N 时间最旧。
        let baseDate = items.first?.timestamp ?? Date()
        
        // 我们只更新受影响范围内的项目，或者为了稳健更新整个当前加载的列表
        // 更新整个列表虽然是 O(N)，但对于剪贴板这种小数据量（通常几十条）是瞬间完成的，且最安全
        
        context.perform {
            for (index, loopItem) in self.items.enumerated() {
                // 计算新的时间戳：越往下，时间越早 (减去的时间越多)
                // 使用 0.001 秒作为间隔，足够区分且不会对实际时间造成太大偏差
                let newTimestamp = baseDate.addingTimeInterval(-TimeInterval(index) * 0.001)
                
                // A. 更新内存中的 Model (为了防止下次 View 刷新时跳变)
                // 只有当 View 重新读取 items 属性时才生效，因为 struct 是值类型，
                // 此时是在 closure 中遍历，需要修改 self.items
                DispatchQueue.main.async {
                    if index < self.items.count {
                        // 创建一个新的副本并替换
                        var mutableItem = self.items[index]
                        // 只在时间戳真的变了时才替换，避免不必要的 View 刷新
                        if abs(mutableItem.timestamp.timeIntervalSince(newTimestamp)) > 0.0001 {
                            let updatedItem = ClipboardItem(
                                id: mutableItem.id,
                                text: mutableItem.text,
                                timestamp: newTimestamp,
                                creationTime: mutableItem.creationTime,
                                contentType: mutableItem.contentType,
                                additionalData: mutableItem.additionalData
                            )
                            self.items[index] = updatedItem
                        }
                    }
                }
                
                // B. 更新 Core Data
                let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", loopItem.id as CVarArg)
                
                if let entity = try? self.context.fetch(request).first {
                    entity.timestamp = newTimestamp
                }
            }
            
            // 提交保存
            try? PersistenceController.shared.save()
        }
    }
    
    func moveItemToTop(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if index == 0 { return } // 已经在顶部
        
        // 1. 内存移动
        let item = items.remove(at: index)
        // 赋予当前最新时间
        let newTimestamp = Date()
        let newItem = ClipboardItem(
            id: item.id,
            text: item.text,
            timestamp: newTimestamp,
            creationTime: item.creationTime,
            contentType: item.contentType,
            additionalData: item.additionalData
        )
        items.insert(newItem, at: 0)
        
        // 2. Core Data 更新
        context.perform {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            if let entity = try? self.context.fetch(request).first {
                entity.timestamp = newTimestamp
                try? PersistenceController.shared.save()
            }
        }
    }
    
    // MARK: - 剪贴板操作
    
    func copyItemToClipboard(item: ClipboardItem) {
        pasteboard.clearContents()
        
        // 使用该 Item 创建写入器
        let writer = item.makePasteboardWriter()
        pasteboard.writeObjects([writer])
    }
    
    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        // 检查是否是 App 内部刚刚复制的操作（避免循环记录）
        // 这里可以通过判断最顶部的 Item 内容和剪贴板内容是否一致来简单过滤
        
        // 1. 优先检查图片 (交换顺序：把图片检查放到最前面！)
        // 这样可以避免捕获到 Apple Notes 等应用产生的临时文件路径
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            // 使用 tiffRepresentation 确保保留最高质量
            handleNewContent(text: "图片 (\(Int(image.size.width))x\(Int(image.size.height)))", type: .image, data: image.tiffRepresentation)
            return
        }
        
        // 2. 其次检查文件URL
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL, fileURL.isFileURL {
             handleFile(url: fileURL)
             return
        }
        
        // 3. 检查富文本
        if let attributedString = pasteboard.readObjects(forClasses: [NSAttributedString.self], options: nil)?.first as? NSAttributedString {
            let plainText = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plainText.isEmpty else { return }
            
            let rtfData = try? attributedString.data(from: NSRange(location: 0, length: attributedString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            
            handleNewContent(text: plainText, type: .text, data: rtfData)
            return
        }
        
        // 4. 纯文本
        if let str = pasteboard.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                handleNewContent(text: trimmed, type: .text, data: nil)
            }
        }
    }
    
    private func handleFile(url: URL) {
        // 1. 对于来自剪贴板的 URL，通常需要申请安全访问权限
        let isSecuredURL = url.startAccessingSecurityScopedResource()
        defer {
            if isSecuredURL { url.stopAccessingSecurityScopedResource() }
        }
        
        do {
            // 2. 尝试将文件内容读取为 Data 保存 (适用于小文件，如图片/文档)
            // 如果是大文件，你可能需要考虑复制文件到 App 自己的沙盒 Documents 目录，而不是存进 Core Data
            let fileData = try Data(contentsOf: url)
            
            handleNewContent(
                text: url.lastPathComponent,
                type: .fileURL, // 或者你可以根据后缀判断改为 .image
                data: fileData // 保存文件真实内容，而不是 URL
            )
        } catch {
            print("读取文件失败: \(error)")
        }
    }
    
    private func handleNewContent(text: String, type: ClipboardContentType, data: Data?) {
        // 检查重复
        if let existingIndex = items.firstIndex(where: { $0.text == text && $0.contentType == type }) {
            let existingItem = items[existingIndex]
            moveItemToTop(id: existingItem.id)
        } else {
            saveNewItem(text: text, contentType: type, additionalData: data)
        }
    }
}
