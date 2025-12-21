import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct ItemCard: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    var onDragStart: (() -> Void)? = nil
    
    static func == (lhs: ItemCard, rhs: ItemCard) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSelected == rhs.isSelected
    }

    private var contentTypeTitle: String {
        switch item.contentType {
        case .text: return "文本"
        case .fileURL: return "文件"
        case .image: return "图片"
        default: return "未知"
        }
    }
    
    private var contentTypeIcon: String {
        switch item.contentType {
        case .text: return "doc.text"
        case .fileURL: return "folder.fill"
        case .image: return "photo"
        default: return "questionmark"
        }
    }
    
    private var contentText: String {
        switch item.contentType {
        case .fileURL:
            // 尝试从URL中提取文件名
            if let url = URL(string: item.text) {
                return url.lastPathComponent
            }
            return item.text
        default:
            return item.text
        }
    }

    // 分解复杂的body为多个计算属性，帮助编译器进行类型检查
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contentTypeTitle)
                    .font(.system(size: 11, weight: .bold))
                Text(Formatters.timeFormatter.string(from: item.timestamp))
                    .font(.system(size: 9))
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            Spacer()
            Image(systemName: contentTypeIcon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.8), Color.black]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var contentView: some View {
        VStack(alignment: .leading) {
            contentDisplayView
            
            Spacer(minLength: 0)
            HStack {
                Spacer()
                contentFooterText
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
    
    private var contentDisplayView: some View {
        switch item.contentType {
        case .image:
            AnyView(imageContentView)
        default:
            AnyView(textContentView)
        }
    }
    
    private var imageContentView: some View {
        if let data = item.additionalData, let nsImage = NSImage(data: data) {
            return AnyView(
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 180)
                    .cornerRadius(8)
            )
        } else {
            return AnyView(
                Text(item.text)
                    .lineLimit(8)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.8))
                    .multilineTextAlignment(.leading)
            )
        }
    }
    
    private var textContentView: some View {
        Text(contentText.prefix(300))
            .lineLimit(8)
            .font(.system(size: 12))
            .foregroundColor(.black.opacity(0.8))
            .multilineTextAlignment(.leading)
    }
    
    private var contentFooterText: some View {
        Text(item.contentType == .image ? "图片" : "\(item.text.count) 个字符")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
    }
    
    private var footerOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .inset(by: isSelected ? 2.5 : 0.25)
            .stroke(isSelected ? Color.blue : Color.black.opacity(0.05), lineWidth: isSelected ? 5 : 0.5)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            contentView
        }
        .frame(width: 260, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(footerOverlay)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .drawingGroup()
        .gesture(TapGesture(count: 2).onEnded { _ in onTapDouble() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { _ in onTapSelect() })
        .onDrag {
            onDragStart?()
            let provider = NSItemProvider()
            
            // 1. 注册基础文本类型 (备忘录最常用)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(item.text.data(using: .utf8), nil)
                return nil
            }
            
            // 2. 如果是文件，注册文件类型
            if item.contentType == .fileURL, let url = URL(string: item.text) {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                    completion(url.dataRepresentation, nil)
                    return nil
                }
            }
            
            // 3. 如果是图片，注册图片类型
            if item.contentType == .image, let data = item.additionalData {
                let type = UTType.png.identifier
                provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            
            // 4. 注册内部排序类型
            if let data = try? JSONEncoder().encode(item) {
                provider.registerDataRepresentation(forTypeIdentifier: "com.tari.item", visibility: .ownProcess) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            
            return provider
        }
    }
}
