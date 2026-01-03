import SwiftUI
import AppKit

struct PreviewDialog: View {
    let itemID: UUID
    var onClose: () -> Void
    
    @State private var contentType: ClipboardContentType = .text
    @State private var content: String = "加载中..."
    @State private var attributedString: NSAttributedString?
    @State private var detectedBackgroundColor: NSColor?
    @State private var previewImage: NSImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 1. 全局背景：使用厚的材质感
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 2. 自定义导航头部
                headerView
                
                // 3. 主内容区
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.03)) // 微弱的凹陷感
                
                // 4. 底部状态栏
                footerView
            }
            
            // 右上角关闭按钮（悬浮式，更有设计感）
            closeButton
        }
        .frame(width: 500, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6) // 加深一点阴影以提升悬浮感
        .padding(30)
        .task(id: itemID) {
            await loadPreviewData()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Image(systemName: contentType == .image ? "photo.fill" : "doc.text.fill")
                .foregroundColor(.secondary)
            Text(contentType == .image ? "图片预览" : "内容预览")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
    
    private var contentArea: some View {
    Group {
        if isLoading {
            ProgressView().controlSize(.small)
        } else if contentType == .image, let nsImage = previewImage {
            imagePreviewer(nsImage)
        } else {
            textPreviewer
        }
    }
}
    
    private func imagePreviewer(_ img: NSImage) -> some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(20)
        }
    }
    
    private var textPreviewer: some View {
    ZStack {
        // 使用一个带有微弱毛玻璃效果的容器
        VisualEffectView(material: .selection, blendingMode: .withinWindow)
            .cornerRadius(12)
            // 关键：增加一个极细的白色半透明边框，增加高级感
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )

        if let attrString = attributedString {
            RichTextView(attributedString: attrString, isEditable: false, backgroundColor: nil)
                .padding(12) // 内部文字边距
        } else {
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85)) // 稍微柔和一点的黑色
                    .lineSpacing(4) // 增加行间距，提升阅读体验
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
    .padding(.horizontal, 16) // 外部与边缘的间距
    .padding(.top, 4)
    .padding(.bottom, 12)
}
    
    private var footerView: some View {
        HStack {
            if contentType == .image, let img = previewImage {
                Text("\(Int(img.size.width)) × \(Int(img.size.height)) px")
            } else {
                Text("\(content.count) 字符")
            }
            Spacer()
            Text("按 ESC 退出")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary.opacity(0.7))
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(Color.primary.opacity(0.03))
    }
    
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.secondary)
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(12)
    }

    // MARK: - Logic (保持原有的解析逻辑)
    private func loadPreviewData() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let listItem = ClipboardDataStore.shared.fetchListItemById(id: itemID) else { return }
        self.content = listItem.text
        self.contentType = listItem.contentType
        
        guard let archivedData = ClipboardDataStore.shared.fetchArchivedData(id: itemID) else { return }
        
        // 解析代码逻辑保持不变...
        var foundDict: [String: Data]? = nil
        if let multiItems = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [[String: Data]] {
            foundDict = multiItems.first
        } else if let singleDict = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [String: Data] {
            foundDict = singleDict
        }
        
        guard let dataDict = foundDict else { return }
        
        if listItem.contentType == .image {
            let imageTypes = [NSPasteboard.PasteboardType.tiff.rawValue, NSPasteboard.PasteboardType.png.rawValue, "public.jpeg"]
            for type in imageTypes {
                if let imageData = dataDict[type], let img = NSImage(data: imageData) {
                    self.previewImage = img
                    break
                }
            }
        } else {
            if let rtfData = dataDict[NSPasteboard.PasteboardType.rtf.rawValue] ?? dataDict["public.rtf"] {
                let result = await RTFHelper.parseAsync(data: rtfData)
                self.attributedString = result.0
                self.detectedBackgroundColor = result.1
            }
        }
    }
}