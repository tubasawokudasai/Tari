import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct ItemCard: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    
    @State private var cachedAttributedString: NSAttributedString?
    @State private var cachedBackgroundColor: NSColor?
    
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
    
    // 🔥 计算属性：智能文字颜色
    // 根据背景色决定文字颜色：深色背景->白字，浅色背景->黑字
    private var dynamicTextColor: Color {
        if let bgColor = cachedBackgroundColor {
            return bgColor.isDarkColor ? .white : .black.opacity(0.8)
        }
        // 🔴 关键修复：当 cachedBackgroundColor 为 nil 时（加载中或纯文本默认），
        // 因为我们在下面的 background modifier 里 fallback 到了 .white，
        // 所以这里的文字必须强制为 .black，绝对不能用 .primary！
        // 否则：深色模式下 -> 背景白(fallback) + 文字白(primary) = 看不见
        return .black.opacity(0.8)
    }

    // 分解复杂的body为多个计算属性，帮助编译器进行类型检查
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
            HStack {
                Spacer()
                contentFooterText
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 🎨 背景色逻辑：
        // 1. 如果有解析出的背景色（RTF），用它
        // 2. 如果是纯文本，默认用白色 (或者根据需求改成 Color(NSColor.textBackgroundColor))
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
        Group {
            if let attrString = cachedAttributedString {
                RichTextView(
                    attributedString: attrString,
                    isEditable: false,
                    backgroundColor: cachedBackgroundColor
                )
                .allowsHitTesting(false) // 禁用交互，点击穿透到卡片
            } else {
                // 📝 纯文本模式 (无格式文本)：
                // 这里必须使用 dynamicTextColor，不能写死 .black
                Text(contentText.prefix(300))
                    .lineLimit(8)
                    .font(.system(size: 12))
                    .foregroundColor(dynamicTextColor) // ✅ 修复点：动态颜色
                    .multilineTextAlignment(.leading)
            }
        }
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
        .gesture(TapGesture(count: 2).onEnded { _ in onTapDouble() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { _ in onTapSelect() })
        .contentShape(Rectangle()) // 确保点击区域完整
        .task(id: item.id) { await loadRichText() }
    }
    
    private func loadRichText() async {
        // 1. 如果是纯文本且没有 RTF 数据，我们需要手动设置一个默认背景
        if item.contentType == .text && item.additionalData == nil {
            // 设定纯文本的默认背景（例如白色，或者随系统）
            self.cachedBackgroundColor = .white
            return
        }
        
        guard item.contentType == .text || item.contentType == .unknown,
              let rtfData = item.additionalData else { return }
        let result = await RTFHelper.parseAsync(data: rtfData)
        self.cachedAttributedString = result.0
        self.cachedBackgroundColor = result.1
    }
}
