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
    
    // 标记是否需要滚动回顶部
    @Published var shouldScrollToTop = false
    
    private var timer: AnyCancellable?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = NSPasteboard.general.changeCount
    
    // Core Data 上下文
    private let context = PersistenceController.shared.container.viewContext

    init() {
        loadMoreItems()
        
        // 启动剪贴板监听
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClipboard()
            }
    }

    // MARK: - 监听剪贴板 (修复：支持图片/文件 + 多项目)
        private func checkClipboard() {
            guard pasteboard.changeCount != lastChangeCount else { return }
            lastChangeCount = pasteboard.changeCount
            
            // 1. 获取所有项目
            guard let pbItems = pasteboard.pasteboardItems, !pbItems.isEmpty else { return }
            
            // 2. 准备存储结构
            var allItemsData: [[String: Data]] = []
            
            // 获取预览文本 (可能为空，比如纯图片时)
            var displayString = pasteboard.string(forType: .string) ?? ""
            
            // 标记内容类型
            var detectedType: ClipboardContentType = .text
            var hasImage = false
            var hasFile = false
            
            // 3. 遍历每一个 Item
            for item in pbItems {
                var itemDict: [String: Data] = [:]
                
                for type in item.types {
                    // 存储数据
                    if let data = item.data(forType: type) {
                        itemDict[type.rawValue] = data
                    }
                    
                    // 类型检测
                    if type == .tiff || type == .png {
                        hasImage = true
                    } else if type == .fileURL {
                        hasFile = true
                    }
                }
                
                if !itemDict.isEmpty {
                    allItemsData.append(itemDict)
                }
            }
            
            // 4. 智能判断类型和标题
            if hasImage {
                detectedType = .image
                // 如果没有文字描述，给一个默认标题
                if displayString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayString = "图片 \(Date())"
                }
            } else if hasFile {
                detectedType = .fileURL // 注意：这里可能需要配合你的 handleFile 逻辑，或者简化处理
                if displayString.isEmpty {
                    displayString = "文件"
                }
            }
            
            // 如果完全没有数据，直接退出
            if allItemsData.isEmpty { return }
            
            // 5. 归档存储
            let finalData = try? NSKeyedArchiver.archivedData(withRootObject: allItemsData, requiringSecureCoding: false)
            
            print("DEBUG 捕获: 抓到了 \(allItemsData.count) 个 Items. 类型: \(detectedType)")
            
            // 6. 保存
            // 注意：这里我们传入 detectedType，这样 ItemCard 才能正确显示图标
            handleNewContent(text: displayString, type: detectedType, data: finalData)
        }

    // MARK: - 写入剪贴板 (最终修复：多项目还原)
        func copyItemToClipboard(item: ClipboardItem) {
            // 1. 清空剪贴板
            pasteboard.clearContents()
            
            var allItemsData: [[String: Data]] = []
            
            // 2. 解析数据 (兼容性处理)
            if let archivedData = item.additionalData {
                // 情况 A：新版数据，结构是 [[String: Data]]
                if let newFormat = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [[String: Data]] {
                    allItemsData = newFormat
                }
                // 情况 B：旧版数据，结构是 [String: Data]，为了防止 App 崩溃做个兼容
                else if let oldFormat = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [String: Data] {
                    allItemsData = [oldFormat]
                }
            }
            
            // 如果解析失败，兜底创建一个纯文本 Item
            if allItemsData.isEmpty {
                let simpleItem = NSPasteboardItem()
                simpleItem.setString(item.text, forType: .string)
                pasteboard.writeObjects([simpleItem])
                return
            }
            
            // 3. 重建 NSPasteboardItem 数组
            var pbItems: [NSPasteboardItem] = []
            
            for itemDict in allItemsData {
                let pbItem = NSPasteboardItem()
                
                for (typeRaw, data) in itemDict {
                    // ⚠️ 关键过滤：
                    //  过滤 Source，防止 Navicat 发现来源不是它自己而拒绝解析
                    if typeRaw == "org.nspasteboard.source" {
                        continue
                    }
                    
                    let type = NSPasteboard.PasteboardType(typeRaw)
                    pbItem.setData(data, forType: type)
                }
                pbItems.append(pbItem)
            }
            
            // 4. 一次性写入所有 Items
            // 这样 Navicat 就会看到 multiple items，从而粘贴多行
            let success = pasteboard.writeObjects(pbItems)
            
            print("DEBUG 还原: 写入了 \(pbItems.count) 个 Items。结果: \(success)")
        }
    
    // MARK: - 数据管理方法 (修复缺失成员)
    
    // 修复：pruneToFirstPage (防止内存堆积)
    func pruneToFirstPage() {
        if items.count > pageSize {
            items = Array(items.prefix(pageSize))
        }
        currentPage = 1
        hasMoreData = true
    }

    // 修复：moveItem (拖拽排序支持)
    func moveItem(from source: Int, to destination: Int) {
        guard items.indices.contains(source), items.indices.contains(destination) else { return }
        
        let item = items.remove(at: source)
        items.insert(item, at: destination)
        
        // 重新同步所有项目的时间戳（或者根据业务逻辑仅修改被拖拽项）
        // 这里采用简单的本地顺序调整，不强制更新数据库时间戳以防乱序
    }

    func resetPagination() {
        currentPage = 0
        hasMoreData = true
        items.removeAll()
        loadMoreItems()
    }

    // MARK: - 内部业务逻辑
    
    private func handleFile(url: URL) {
        // ✅ 修复拼写：去掉多余的 Access
        let isSecuredURL = url.startAccessingSecurityScopedResource()
        defer { if isSecuredURL { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let fileData = try Data(contentsOf: url)
            handleNewContent(text: url.lastPathComponent, type: .fileURL, data: fileData)
        } catch {
            print("读取文件失败: \(error)")
        }
    }
    
    private func handleNewContent(text: String, type: ClipboardContentType, data: Data?) {
        if let existingIndex = items.firstIndex(where: { $0.text == text && $0.contentType == type }) {
            let id = items[existingIndex].id
            moveItemToTop(id: id)
            return
        }
        saveNewItem(text: text, contentType: type, additionalData: data)
    }

    private func saveNewItem(text: String, contentType: ClipboardContentType, additionalData: Data?) {
        let newId = UUID()
        let now = Date()
        let newItem = ClipboardItem(id: newId, text: text, timestamp: now, creationTime: now, contentType: contentType, additionalData: additionalData)
        
        DispatchQueue.main.async {
            self.items.insert(newItem, at: 0)
            self.shouldScrollToTop = true
            // 限制内存中的数量
            if self.items.count > 100 { self.pruneToFirstPage() }
        }
        
        context.perform {
            let entity = ClipboardEntity(context: self.context)
            entity.id = newId
            entity.text = text
            entity.timestamp = now
            entity.creationTime = now
            entity.contentType = contentType.rawValue
            entity.additionalData = additionalData
            try? PersistenceController.shared.save()
        }
    }

    func loadMoreItems() {
        // 1. 状态检查，防止重复加载
        guard !isLoading && hasMoreData else { return }
        isLoading = true
        
        // 2. 构造 Fetch Request
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = pageSize
        request.fetchOffset = currentPage * pageSize
        
        // 3. 在后台线程执行查询
        context.perform {
            do {
                let results = try self.context.fetch(request)
                
                // 🔥 核心修复：显式指定 [ClipboardItem] 类型，解决推断报错
                let newItems: [ClipboardItem] = results.compactMap { entity in
                    guard let id = entity.id,
                          let text = entity.text,
                          let ts = entity.timestamp else { return nil }
                    
                    return ClipboardItem(
                        id: id,
                        text: text,
                        timestamp: ts,
                        creationTime: entity.creationTime ?? ts,
                        contentType: ClipboardContentType(rawValue: entity.contentType ?? "") ?? .text,
                        additionalData: entity.additionalData
                    )
                }
                
                // 4. 回到主线程更新 UI 状态
                DispatchQueue.main.async {
                    if self.currentPage == 0 {
                        // 第一页直接替换
                        self.items = newItems
                    } else {
                        // 后续页去重追加
                        let existingIds = Set(self.items.map { $0.id })
                        let uniqueNewItems = newItems.filter { !existingIds.contains($0.id) }
                        self.items.append(contentsOf: uniqueNewItems)
                    }
                    
                    // 更新分页状态
                    self.hasMoreData = newItems.count == self.pageSize
                    self.currentPage += 1
                    self.isLoading = false
                    print("DEBUG: 已加载第 \(self.currentPage) 页，共 \(newItems.count) 条数据")
                }
            } catch {
                print("Fetch Error: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    private func fetchItems(page: Int) -> [ClipboardItem] {
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = pageSize
        request.fetchOffset = page * pageSize
        
        do {
            let results = try context.fetch(request)
            return results.compactMap { entity in
                guard let id = entity.id, let text = entity.text, let ts = entity.timestamp else { return nil }
                return ClipboardItem(
                    id: id, text: text, timestamp: ts,
                    creationTime: entity.creationTime ?? ts,
                    contentType: ClipboardContentType(rawValue: entity.contentType ?? "") ?? .text,
                    additionalData: entity.additionalData
                )
            }
        } catch { return [] }
    }

    func moveItemToTop(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        let newTimestamp = Date()
        let updatedItem = ClipboardItem(id: item.id, text: item.text, timestamp: newTimestamp, creationTime: item.creationTime, contentType: item.contentType, additionalData: item.additionalData)
        items.insert(updatedItem, at: 0)
        
        context.perform {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? self.context.fetch(request).first {
                entity.timestamp = newTimestamp
                try? PersistenceController.shared.save()
            }
        }
    }
    
    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        context.perform {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? self.context.fetch(request).first {
                self.context.delete(entity)
                try? PersistenceController.shared.save()
            }
        }
    }
    
    // 清空剪贴板和所有存储的项目
    func clearAll() {
        // 1. 清空系统剪贴板
        pasteboard.clearContents()
        lastChangeCount = pasteboard.changeCount
        
        // 2. 清空内存中的项目
        DispatchQueue.main.async {
            self.items.removeAll()
            self.currentPage = 0
            self.hasMoreData = true
        }
        
        // 3. 清空Core Data中的所有项目
        context.perform {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            do {
                let entities = try self.context.fetch(request)
                for entity in entities {
                    self.context.delete(entity)
                }
                try PersistenceController.shared.save()
            } catch {
                print("清空Core Data失败: \(error)")
            }
        }
    }
}
