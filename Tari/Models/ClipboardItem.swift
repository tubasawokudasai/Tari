import Foundation
import SwiftUI
import UniformTypeIdentifiers

// 剪贴板内容类型枚举
enum ClipboardContentType: String, Codable {
    case text
    case fileURL
    case image
    case unknown
}

// 轻量级数据传输对象：只包含元数据，不包含实际内容数据
struct ClipboardListItem: Identifiable, Equatable, Codable, Transferable {
    let id: UUID
    let text: String
    let timestamp: Date
    let creationTime: Date
    let contentType: ClipboardContentType
    let appName: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.timestamp == rhs.timestamp
    }
    
    // MARK: - Transferable 协议实现
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: ClipboardListItem.self, contentType: UTType(exportedAs: "com.tari.clipboarditem"))
    }
}