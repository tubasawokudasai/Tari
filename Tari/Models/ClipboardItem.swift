import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftUI

// 剪贴板内容类型枚举
enum ClipboardContentType: String, Codable {
    case text
    case fileURL
    case image
    case unknown
}

// 作为 View 层的数据传输对象
struct ClipboardItem: Identifiable, Equatable, Transferable, Codable {
    let id: UUID
    let text: String
    // timestamp 用于排序，会被修改
    let timestamp: Date
    // creationTime 存储真实创建时间，不会被修改
    let creationTime: Date
    let contentType: ClipboardContentType
    var additionalData: Data?
    
    // 增加 Equatable 实现，帮助 SwiftUI 减少不必要的重绘
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id && lhs.timestamp == rhs.timestamp && lhs.creationTime == rhs.creationTime
    }
    
    // 创建粘贴板写入对象
    func makePasteboardWriter() -> NSPasteboardWriting {
        switch contentType {
        case .image:
            // 如果是图片，尝试从 additionalData 恢复 NSImage
            if let data = additionalData, let image = NSImage(data: data) {
                return image // NSImage 遵循 NSPasteboardWriting 协议
            }
        case .fileURL:
            // 如果是文件，尝试恢复 URL
            if let data = additionalData,
               let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) {
                return url
            }
        case .text:
            // 文本直接返回
            return text as NSString
        default:
            break
        }
        // 默认回退到文本
        return text as NSString
    }
    
    // MARK: - Transferable 协议实现
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .utf8PlainText) {
            item in
            // 将 ClipboardItem 转换为可以传输的数据
            switch item.contentType {
            case .text:
                return item.text.data(using: .utf8) ?? Data()
            case .fileURL:
                return item.text.data(using: .utf8) ?? Data()
            case .image:
                return item.text.data(using: .utf8) ?? Data()
            default:
                return item.text.data(using: .utf8) ?? Data()
            }
        } importing: {
            data in
            // 从传输的数据创建 ClipboardItem
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Tari", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to decode string"])            }
            let currentDate = Date()
            return ClipboardItem(
                id: UUID(),
                text: text,
                timestamp: currentDate,
                creationTime: currentDate,
                contentType: .text
            )
        }
    }
}

extension ClipboardItem {
    // 将原本 ItemCard 里的逻辑移到这里
    func createItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        
        // 1. 纯文本
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(self.text.data(using: .utf8), nil)
            return nil
        }
        
        // 2. 文件
        if self.contentType == .fileURL, let url = URL(string: self.text) {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                completion(url.dataRepresentation, nil)
                return nil
            }
        }
        
        // 3. 图片
        if self.contentType == .image, let data = self.additionalData {
            let type = UTType.png.identifier
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
        
        // 4. 内部排序数据
        if let data = try? JSONEncoder().encode(self) {
            // 注意：这里 Identifier 要和你的 dropDestination 对应，通常用 App Bundle ID 前缀
            provider.registerDataRepresentation(forTypeIdentifier: "com.tari.item", visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
        }
        
        return provider
    }
}