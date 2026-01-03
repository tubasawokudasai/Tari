import Foundation
import CoreData
import AppKit

// 数据存储层：处理 Core Data 操作和解档
final class ClipboardDataStore {
    static let shared = ClipboardDataStore()
    private let context = PersistenceController.shared.container.viewContext
    
    // 私有初始化器确保单例
    private init() {}
    
    // MARK: - 按需加载完整数据
    func fetchArchivedData(id: UUID) -> Data? {
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first?.additionalData
    }
    
    // MARK: - 检查指纹是否存在
    func hasItem(with fingerprint: String) -> Bool {
        let request: NSFetchRequest<ClipboardEntity> = ClipboardEntity.fetchRequest()
        request.predicate = NSPredicate(format: "fingerprint == %@", fingerprint)
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }
    

    
    // MARK: - 保存新的剪贴板项目
    @discardableResult
    func saveNewItem(text: String, contentType: ClipboardContentType, additionalData: Data?, appName: String?, fingerprint: String?) -> UUID {
        let newId = UUID()
        let now = Date()
        
        context.perform {
            let entity = ClipboardEntity(context: self.context)
            entity.id = newId
            entity.text = text
            entity.timestamp = now
            entity.creationTime = now
            entity.contentType = contentType.rawValue
            entity.additionalData = additionalData
            entity.appName = appName
            entity.fingerprint = fingerprint
            try? PersistenceController.shared.save()
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
                try? PersistenceController.shared.save()
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
                try? PersistenceController.shared.save()
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
}