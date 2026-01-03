import AppKit
import Combine
import CoreData
import CryptoKit
import SwiftUI

class ClipboardManager: ObservableObject {
    // 暴露给 View 的数据源：只包含轻量级的 ClipboardListItem
    @Published var items: [ClipboardListItem] = []
    
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
    
    // 数据存储层
    private let dataStore = ClipboardDataStore.shared

    init() {
        loadMoreItems()
        
        // 启动剪贴板监听
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClipboard()
            }
    }

    // MARK: - 文本标准化函数
    private func extractCanonicalText(from allItemsData: [[String: Data]]) -> String? {
        for dict in allItemsData {
            if let data = dict["public.utf8-plain-text"],
               let text = String(data: data, encoding: .utf8) {
                return normalizeText(text)
            }
        }
        return nil
    }
    
    private func normalizeText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - 指纹生成函数
    private func makeClipboardFingerprint(allItemsData: [[String: Data]]) -> String {
        // 1️⃣ 先尝试 canonical text
        if let canonicalText = extractCanonicalText(from: allItemsData),
           !canonicalText.isEmpty {
            return "text:" + canonicalText
        }

        // 2️⃣ 否则退回 payload hash（图片 / 二进制）
        var hasher = SHA256()

        for dict in allItemsData {
            let sortedKeys = dict.keys
                .filter { $0 != "org.nspasteboard.source" }
                .sorted()

            for key in sortedKeys {
                hasher.update(data: key.data(using: .utf8)!) // 安全强制解包，因为 key 是来自 dict.keys
                hasher.update(data: dict[key]!) // 安全强制解包，因为 dict[key] 一定存在
            }
        }

        // 将 SHA256.Digest 转换为 Data，然后获取 hexString
        let digest = hasher.finalize()
        let data = Data(digest)
        return data.hexString
    }

    // MARK: - 监听剪贴板 (支持图片/文件 + 多项目)
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
            detectedType = .fileURL
            if displayString.isEmpty {
                displayString = "文件"
            }
        }
        
        // 如果完全没有数据，直接退出
        if allItemsData.isEmpty { return }
        
        // 5. 归档存储
        let finalData = try? NSKeyedArchiver.archivedData(withRootObject: allItemsData, requiringSecureCoding: false)
        
        // 6. 获取应用来源信息
        var appName: String? = nil
        
        // 从剪贴板项目中获取来源信息
        for item in pbItems {
            // 尝试获取应用来源信息
            if let sourceData = item.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.source")) {
                if let source = String(data: sourceData, encoding: .utf8) {
                    appName = source
                    // 如果 source 不是有效的 bundle identifier，尝试获取当前活动应用
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) == nil {
                        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                            appName = frontmostApp.bundleIdentifier
                        }
                    }
                    break
                }
            } else {
                // 尝试获取当前活动应用
                if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                    appName = frontmostApp.bundleIdentifier
                }
            }
        }
        
        // 7. 检查来源是否是自己的应用，如果是则不保存（防止复制时出现重复记录）
        let currentAppBundleIdentifier = Bundle.main.bundleIdentifier
        if appName != currentAppBundleIdentifier {
            // 8. 生成并检查指纹
            let fingerprint = makeClipboardFingerprint(allItemsData: allItemsData)
            if dataStore.hasItem(with: fingerprint) {
                return // 已经存在，不保存
            }
            
            // 保存：使用 ClipboardDataStore 保存新项
            saveNewItem(text: displayString, contentType: detectedType, additionalData: finalData, appName: appName, fingerprint: fingerprint)
        }
    }

    // MARK: - 写入剪贴板
    func copyItemToClipboard(id: UUID) {
        dataStore.copyItemToClipboard(id: id)
    }
    
    // 修复：pruneToFirstPage (防止内存堆积)
    func pruneToFirstPage() {
        // 必须在主线程执行，确保 UI 状态同步
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 减少保留的项目数量
            if self.items.count > self.pageSize / 2 {
                self.items = Array(self.items.prefix(self.pageSize / 2))
            }
            
            self.currentPage = 1
            self.hasMoreData = true
            self.shouldScrollToTop = true
        }
    }

    // 修复：moveItem (拖拽排序支持)
    func moveItem(from source: Int, to destination: Int) {
        guard items.indices.contains(source), items.indices.contains(destination) else { return }
        
        let item = items.remove(at: source)
        items.insert(item, at: destination)
    }

    func resetPagination() {
        currentPage = 0
        hasMoreData = true
        items.removeAll()
        loadMoreItems()
    }

    // MARK: - 内部业务逻辑
    
    private func handleFile(url: URL) {
        let isSecuredURL = url.startAccessingSecurityScopedResource()
        defer { if isSecuredURL { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let fileData = try Data(contentsOf: url)
            handleNewContent(text: url.lastPathComponent, type: .fileURL, data: fileData)
        } catch {
            print("读取文件失败: \(error)")
        }
    }
    
    private func handleNewContent(text: String, type: ClipboardContentType, data: Data?, appName: String? = nil) {
        // 生成指纹
        var fingerprint: String
        if type == .fileURL {
            // 对于文件URL，使用URL作为稳定标识
            fingerprint = "file:" + text
        } else {
            // 对于其他类型，使用标准化文本作为指纹
            let normalizedText = normalizeText(text)
            fingerprint = normalizedText.isEmpty ? "" : "text:" + normalizedText
        }
        
        // 检查指纹是否已存在
        if fingerprint.isEmpty || dataStore.hasItem(with: fingerprint) {
            return
        }
        
        saveNewItem(text: text, contentType: type, additionalData: data, appName: appName, fingerprint: fingerprint)
    }

    private func saveNewItem(text: String, contentType: ClipboardContentType, additionalData: Data?, appName: String? = nil, fingerprint: String? = nil) {
        // ✅ 唯一 ID 来源
        let newId = dataStore.saveNewItem(
            text: text,
            contentType: contentType,
            additionalData: additionalData,
            appName: appName,
            fingerprint: fingerprint
        )

        let now = Date()
        let newItem = ClipboardListItem(
            id: newId,
            text: text,
            timestamp: now,
            creationTime: now,
            contentType: contentType,
            appName: appName
        )

        DispatchQueue.main.async {
            self.items.insert(newItem, at: 0)
            self.shouldScrollToTop = true
            if self.items.count > 100 {
                self.pruneToFirstPage()
            }
        }
    }

    func loadMoreItems() {
        // 1. 状态检查，防止重复加载
        guard !isLoading && hasMoreData else { return }
        isLoading = true
        
        // 2. 构造 Fetch Request：使用 dictionaryResultType 只获取轻量级字段
        let request = NSFetchRequest<NSDictionary>(entityName: "ClipboardEntity")
        request.resultType = .dictionaryResultType
        request.fetchLimit = pageSize
        request.fetchOffset = currentPage * pageSize
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        // 只获取需要的轻量级字段，减少内存占用
        request.propertiesToFetch = [
            "id", "text", "timestamp", "creationTime", "contentType", "appName"
        ]
        
        // 3. 在后台线程执行查询
        context.perform {
            do {
                let results = (try self.context.fetch(request)) ?? []
                
                // 4. 转换为轻量级的 ClipboardListItem
                let newItems = results.compactMap { dict -> ClipboardListItem? in
                    guard
                        let id = dict["id"] as? UUID,
                        let text = dict["text"] as? String,
                        let ts = dict["timestamp"] as? Date
                    else { return nil }
                    
                    return ClipboardListItem(
                        id: id,
                        text: text,
                        timestamp: ts,
                        creationTime: dict["creationTime"] as? Date ?? ts,
                        contentType: ClipboardContentType(rawValue: dict["contentType"] as? String ?? "") ?? .text,
                        appName: dict["appName"] as? String
                    )
                }
                
                // 5. 回到主线程更新 UI 状态
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
                }
            } catch {
                print("Fetch Error: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - 操作剪贴板项目
    func moveItemToTop(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        let newTimestamp = Date()
        let updatedItem = ClipboardListItem(id: item.id, text: item.text, timestamp: newTimestamp, creationTime: item.creationTime, contentType: item.contentType, appName: item.appName)
        items.insert(updatedItem, at: 0)
        
        // 使用 ClipboardDataStore 更新 Core Data
        dataStore.updateItemTimestamp(id: id, newTimestamp: newTimestamp)
    }
    
    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        // 使用 ClipboardDataStore 删除 Core Data 中的项目
        dataStore.deleteItem(id: id)
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
        
        // 3. 使用 ClipboardDataStore 清空 Core Data 中的所有项目
        dataStore.clearAll()
    }
}
