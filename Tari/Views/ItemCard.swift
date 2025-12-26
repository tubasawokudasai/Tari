import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct ItemCard: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    
    // 缓存异步加载的内容
    @State private var cachedAttributedString: NSAttributedString?
    @State private var cachedBackgroundColor: NSColor?
    @State private var cachedImage: NSImage? // 🔥 新增：缓存解码后的图片
    
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
            if let url = URL(string: item.text) {
                return url.lastPathComponent
            }
            return item.text
        default:
            return item.text
        }
    }
    
    private var dynamicTextColor: Color {
        if let bgColor = cachedBackgroundColor {
            return bgColor.isDarkColor ? .white : .black.opacity(0.8)
        }
        return .black.opacity(0.8)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contentTypeTitle)
                    .font(.system(size: 11, weight: .bold))
                Text(Formatters.formatRelativeTime(item.creationTime))
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: cachedBackgroundColor ?? .white)
        )
    }
    
    private var contentDisplayView: some View {
        switch item.contentType {
        case .image:
            AnyView(imageContentView)
        default:
            AnyView(textContentView)
        }
    }
    
    // 🔥 修改：使用异步加载好的 cachedImage
    private var imageContentView: some View {
        if let nsImage = cachedImage {
            return AnyView(
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 180)
                    .cornerRadius(8)
            )
        } else {
            // 图片加载失败或正在加载时的占位符
            return AnyView(
                VStack(alignment: .leading) {
                    Text(item.text.isEmpty ? "正在加载图片..." : item.text)
                        .lineLimit(8)
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.5))
                }
            )
        }
    }
    
    private var textContentView: some View {
        Group {
            if let attrString = cachedAttributedString {
                RichTextView(
                    attributedString: attrString,
                    isEditable: false,
                    backgroundColor: cachedBackgroundColor
                )
                .allowsHitTesting(false)
            } else {
                Text(contentText.prefix(300))
                    .lineLimit(8)
                    .font(.system(size: 12))
                    .foregroundColor(dynamicTextColor)
                    .multilineTextAlignment(.leading)
            }
        }
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
        .gesture(TapGesture(count: 2).onEnded { _ in onTapDouble() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { _ in onTapSelect() })
        .contentShape(Rectangle())
        // 🔥 修改：统一调用数据解析逻辑
        .task(id: item.id) { await loadPreviewData() }
    }
    
    // 🔥 核心修复：统一解析逻辑，兼容新旧数据格式
    private func loadPreviewData() async {
        guard let archivedData = item.additionalData else {
            self.cachedBackgroundColor = .white
            return
        }
        
        // 1. 解包数据
        // 这里的关键是：我们要把归档数据变成一个可读的字典
        var foundDict: [String: Data]? = nil
        
        // 尝试解析为新版结构 [[String: Data]] (Navicat 修复版)
        if let multiItems = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [[String: Data]] {
            // 对于预览，我们通常取第一个包含有效数据的 Item
            foundDict = multiItems.first
        }
        // 尝试解析为旧版结构 [String: Data] (兼容老数据)
        else if let singleDict = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [String: Data] {
            foundDict = singleDict
        }
        
        guard let dataDict = foundDict else {
            self.cachedBackgroundColor = .white
            return
        }
        
        // 2. 根据类型提取内容
        if item.contentType == .image {
            // 🔥 图片提取逻辑
            // 常见的图片类型标识符
            let imageTypes = [
                NSPasteboard.PasteboardType.tiff.rawValue,
                NSPasteboard.PasteboardType.png.rawValue,
                "public.jpeg",
                "public.jpeg-2000"
            ]
            
            // 查找是否存在图片数据
            for type in imageTypes {
                if let imageData = dataDict[type], let img = NSImage(data: imageData) {
                    self.cachedImage = img
                    // 图片背景通常设为透明或微灰，这里设为白色即可
                    self.cachedBackgroundColor = .white
                    return
                }
            }
        } else {
            // 🔥 RTF 富文本提取逻辑
            if let rtfData = dataDict[NSPasteboard.PasteboardType.rtf.rawValue] ?? dataDict["public.rtf"] {
                let result = await RTFHelper.parseAsync(data: rtfData)
                self.cachedAttributedString = result.0
                self.cachedBackgroundColor = result.1
            } else {
                self.cachedBackgroundColor = .white
            }
        }
    }
}
