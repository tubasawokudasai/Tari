import Foundation
import CoreData
import AppKit

// 数据存储层：处理 Core Data 操作和解档
final class ClipboardDataStore {
    static let shared = ClipboardDataStore()
    private let context = PersistenceController.shared.container.viewContext
    
    // 私有初始化器确保单例
    private init() {}
    
    // MARK: - 按需加载完整数据 (内存优化版)
    func fetchArchivedData(id: UUID) -> Data? {
        // 1. 创建一个临时的后台上下文，不与主线程 viewContext 共享缓存
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        
        var resultData: Data?
        
        // 2. 在该上下文中同步执行查询
        bgContext.performAndWait {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            
            // 3. 设置属性只读，不做更改跟踪 (微小的性能提升)
            bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            if let entity = try? bgContext.fetch(request).first {
                // 4. 拷贝数据。由于 Data 是结构体 (Value Type)，这里会发生 Copy-on-Write 的引用传递，
                // 但一旦离开闭包，bgContext 被销毁，Core Data 底层的 Row Cache 就会被释放。
                resultData = entity.additionalData
            }
        }
        
        return resultData
    }
    
    // MARK: - 检查指纹是否存在
    func hasItem(with fingerprint: String) -> Bool {
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        request.predicate = NSPredicate(format: "fingerprint == %@", fingerprint)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }
    
    // MARK: - 根据指纹获取项目ID
    func fetchItemIdByFingerprint(fingerprint: String) -> UUID? {
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        request.predicate = NSPredicate(format: "fingerprint == %@", fingerprint)
        request.fetchLimit = 1
        request.propertiesToFetch = ["id"]
        
        guard let entity = try? context.fetch(request).first else { return nil }
        return entity.id
    }
    

    
    // MARK: - 保存新的剪贴板项目，增强数据验证
    @discardableResult
    func saveNewItem(text: String, contentType: ClipboardContentType, additionalData: Data?, appName: String?, fingerprint: String?) -> UUID {
        let newId = UUID()
        let now = Date()
        
        // 验证基本数据
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            // 如果文本为空，使用默认文本
            let defaultText = "空内容 \(Date())"
            context.perform {
                let entity = ClipboardEntity(context: self.context)
                entity.id = newId
                entity.text = defaultText
                entity.timestamp = now
                entity.creationTime = now
                entity.contentType = contentType.rawValue
                entity.additionalData = additionalData
                entity.appName = appName
                entity.fingerprint = fingerprint
                do {
                    try PersistenceController.shared.save()
                    // 🔴 新增：保存成功后，立即将对象转为 Fault，释放内存中的数据
                    self.context.refresh(entity, mergeChanges: false)
                } catch {
                    print("保存Core Data失败: \(error)")
                }
            }
            return newId
        }
        
        context.perform {
            let entity = ClipboardEntity(context: self.context)
            entity.id = newId
            entity.text = trimmedText
            entity.timestamp = now
            entity.creationTime = now
            entity.contentType = contentType.rawValue
            entity.additionalData = additionalData
            entity.appName = appName
            entity.fingerprint = fingerprint
            do {
                try PersistenceController.shared.save()
                // 🔴 新增：保存成功后，立即将对象转为 Fault，释放内存中的数据
                self.context.refresh(entity, mergeChanges: false)
            } catch {
                print("保存Core Data失败: \(error)")
            }
        }
        
        return newId
    }
    
    // MARK: - 复制项目到剪贴板
    func copyItemToClipboard(id: UUID) {
        guard let archivedData = fetchArchivedData(id: id) else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        var allItemsData: [[String: Data]] = []
        
        // 解析数据 (兼容性处理)
        do {
            // 使用新的 API 尝试解析新格式 [[String: Data]]
            if let newFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [[String: Data]] {
                allItemsData = newFormat
            } 
            // 使用新的 API 尝试解析旧格式 [String: Data]
            else if let oldFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [String: Data] {
                allItemsData = [oldFormat]
            }
        } catch {
            print("解析剪贴板数据失败: \(error)")
        }
        
        // 如果解析失败，兜底创建一个纯文本 Item
        if allItemsData.isEmpty {
            if let item = fetchListItemById(id: id) {
                let simpleItem = NSPasteboardItem()
                simpleItem.setString(item.text, forType: .string)
                pasteboard.writeObjects([simpleItem])
            }
            return
        }
        
        // 重建 NSPasteboardItem 数组
        var pbItems: [NSPasteboardItem] = []
        
        for itemDict in allItemsData {
            let pbItem = NSPasteboardItem()
            
            for (typeRaw, data) in itemDict {
                // 过滤 Source，防止 Navicat 发现来源不是它自己而拒绝解析
                if typeRaw == "org.nspasteboard.source" {
                    continue
                }
                
                let type = NSPasteboard.PasteboardType(typeRaw)
                pbItem.setData(data, forType: type)
            }
            pbItems.append(pbItem)
        }
        
        // 一次性写入所有 Items
        pasteboard.writeObjects(pbItems)
    }
    
    // MARK: - 获取单个列表项
    func fetchListItemById(id: UUID) -> ClipboardListItem? {
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        guard let entity = try? context.fetch(request).first,
              let id = entity.id,
              let text = entity.text,
              let ts = entity.timestamp else { return nil }
        
        return ClipboardListItem(
            id: id,
            text: text,
            timestamp: ts,
            creationTime: entity.creationTime ?? ts,
            contentType: ClipboardContentType(rawValue: entity.contentType ?? "") ?? .text,
            appName: entity.appName
        )
    }
    
    // MARK: - 更新项目时间戳
    func updateItemTimestamp(id: UUID, newTimestamp: Date) {
        context.perform {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? self.context.fetch(request).first {
                entity.timestamp = newTimestamp
                do {
                    try PersistenceController.shared.save()
                } catch {
                    print("保存Core Data失败: \(error)")
                }
            }
        }
    }
    
    // MARK: - 删除单个项目
    func deleteItem(id: UUID) {
        context.perform {
            let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? self.context.fetch(request).first {
                self.context.delete(entity)
                do {
                    try PersistenceController.shared.save()
                } catch {
                    print("保存Core Data失败: \(error)")
                }
            }
        }
    }
    
    // MARK: - 清空所有项目
    func clearAll() {
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
    
    // 记录上一次清理的时间，避免频繁清理引发性能问题
    private var lastCleanupTime: Date = .distantPast
    
    // MARK: - 清理过期记录和超出最大限制的记录
    func cleanUpOldAndExcessItems() {
        // 如果距离上次清理还不到 1 天（86400秒），直接跳过
        let now = Date()
        guard now.timeIntervalSince(lastCleanupTime) > 86400 else {
            return
        }
        lastCleanupTime = now
        
        context.perform {
            let defaults = UserDefaults.standard
            
            // 1. 获取设置参数，如果不存在则使用默认值
            let retentionDays = defaults.object(forKey: "retentionPeriod") as? Int ?? 30
            let maxCount = defaults.object(forKey: "maxRecordCount") as? Int ?? 1000
            
            // 2. 清理过期数据 (retentionDays == 0 表示永久保存)
            if retentionDays > 0 {
                if let expirationDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) {
                    let dateRequest: NSFetchRequest<NSFetchRequestResult> = ClipboardEntity.fetchRequest()
                    dateRequest.predicate = NSPredicate(format: "timestamp < %@", expirationDate as CVarArg)
                    let deleteDateRequest = NSBatchDeleteRequest(fetchRequest: dateRequest)
                    
                    do {
                        try self.context.execute(deleteDateRequest)
                    } catch {
                        print("删除过期记录失败: \(error)")
                    }
                }
            }
            
            // 3. 强制保存，确保接下来的查询是基于最新状态的
            if self.context.hasChanges {
                try? self.context.save()
            }
            
            // 4. 清理超出最大数量限制的数据 (maxCount == 0 表示无限制)
            if maxCount > 0 {
                let countRequest: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
                
                // 获取当前总数
                if let currentCount = try? self.context.count(for: countRequest), currentCount > maxCount {
                    let excessCount = currentCount - maxCount
                    
                    // 获取需要删除的（最旧的）项目的 ID
                    let excessRequest: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
                    excessRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
                    excessRequest.fetchLimit = excessCount
                    excessRequest.propertiesToFetch = ["id"]
                    
                    do {
                        let entitiesToDelete = try self.context.fetch(excessRequest)
                        for entity in entitiesToDelete {
                            self.context.delete(entity)
                        }
                        try self.context.save()
                    } catch {
                        print("删除超额记录失败: \(error)")
                    }
                }
            }
        }
    }
}