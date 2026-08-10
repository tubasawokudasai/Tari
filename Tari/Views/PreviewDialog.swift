import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreviewDialog: View {
    let itemID: UUID
    var onClose: () -> Void
    
    @State private var contentType: ClipboardContentType = .text
    @State private var content: String = "加载中..."
    @State private var attributedString: NSAttributedString?
    @State private var detectedBackgroundColor: NSColor?
    @State private var previewImage: NSImage?
    @State private var isLoading = true

    // 添加用于图片缩放和平移的状态变量
    @State private var zoomScale: CGFloat = 1.0
    @State private var currentMagnification: CGFloat = 1.0
    
    @State private var imageOffset: CGSize = .zero
    @State private var currentOffset: CGSize = .zero
    
    // 动态调整窗口尺寸
    @State private var targetSize: CGSize = CGSize(width: 500, height: 420)
    
    // 用于确保ScrollView知道它内部内容的ID，以便scrollTo
    private let imageContentID = "imageContent"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                headerView
                
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.03))
                
                footerView
            }
            
            closeButton
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: targetSize)
        .task(id: itemID) {
            await loadPreviewData()
        }
        .onChange(of: itemID) { _ in
            resetImagePreviewState()
        }
    }
    
    // MARK: - Subviews
    
    private var headerIconName: String {
        switch contentType {
        case .image: return "photo.fill"
        case .fileURL: return isDirectory ? "folder.fill" : "doc.fill"
        default: return "doc.text.fill"
        }
    }
    
    private var headerTitle: String {
        switch contentType {
        case .image: return "图片预览"
        case .fileURL: return isDirectory ? "文件夹预览" : "文件预览"
        default: return "内容预览"
        }
    }

    private var headerView: some View {
        HStack {
            Image(systemName: headerIconName)
                .foregroundColor(.secondary)
            Text(headerTitle)
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
            } else if contentType == .fileURL {
                filePreviewer
            } else {
                textPreviewer
            }
        }
    }
    
    private var isDirectory: Bool {
        let url = URL(string: content) ?? URL(fileURLWithPath: content)
        return url.pathExtension.isEmpty
    }

    private var cleanDisplayPath: String {
        let rawPath = URL(string: content)?.path ?? content
        let userHome = "/Users/\(NSUserName())"
        if rawPath.hasPrefix(userHome) {
            return rawPath.replacingOccurrences(of: userHome, with: "~")
        }
        return rawPath
    }
    
    private var filePreviewer: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 160, height: 160)
                
                Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
            }
            
            Text(cleanDisplayPath)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Modified imagePreviewer with Zoom and Pan
    private func imagePreviewer(_ img: NSImage) -> some View {
        GeometryReader { outerGeometry in // 获取 ScrollView 的可用尺寸
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: outerGeometry.size.width * zoomScale * currentMagnification,
                        height: outerGeometry.size.height * zoomScale * currentMagnification
                    )
                    .offset(x: imageOffset.width + currentOffset.width, y: imageOffset.height + currentOffset.height)
                    .id(imageContentID) // 给图片内容一个ID，方便scrollTo
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    // *** 关键改动: contentShape 确保手势识别区域 ***
                    .contentShape(Rectangle()) // 确保即使图片很小，手势识别区域也覆盖了容器
                    // 动画效果
                    .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: zoomScale * currentMagnification)
                    .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: imageOffset)
                    // *** 关键改动: 手势直接附加到 Image 上，并使用 .gesture(...).simultaneousGesture(...) ***
                    .gesture(
                        MagnificationGesture() // 捏合缩放手势
                            .onChanged { value in
                                self.currentMagnification = value
                                // 调试输出
                                print("MagnificationGesture onChanged: value=\(value), currentMagnification=\(self.currentMagnification)")
                            }
                            .onEnded { value in
                                self.zoomScale *= value
                                self.currentMagnification = 1.0 // 重置手势的瞬时缩放
                                // 缩放限制
                                self.zoomScale = max(0.2, self.zoomScale) // 最小缩放0.2倍
                                self.zoomScale = min(5.0, self.zoomScale) // 最大缩放5.0倍
                                // 调试输出
                                print("MagnificationGesture onEnded: value=\(value), zoomScale=\(self.zoomScale)")
                            }
                    )
                    .simultaneousGesture(
                        DragGesture() // 拖动平移手势
                            .onChanged { value in
                                self.currentOffset = value.translation
                                // 调试输出
                                print("DragGesture onChanged: translation=\(value.translation)")
                            }
                            .onEnded { value in
                                self.imageOffset = CGSize(width: self.imageOffset.width + value.translation.width,
                                                          height: self.imageOffset.height + value.translation.height)
                                self.currentOffset = .zero
                                // 调试输出
                                print("DragGesture onEnded: imageOffset=\(self.imageOffset)")
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2) // 双击手势用于重置或放大
                            .onEnded { _ in
                                withAnimation {
                                    if zoomScale == 1.0 && imageOffset == .zero { // 如果已经是默认状态，放大到某个固定倍数
                                        zoomScale = 2.0
                                        imageOffset = .zero // 确保偏移也归零，放大到中心
                                    } else { // 否则重置
                                        resetImagePreviewState()
                                    }
                                }
                                // 调试输出
                                print("TapGesture (double) onEnded: zoomScale=\(self.zoomScale), imageOffset=\(self.imageOffset)")
                            }
                    )
            } // End of ScrollView
            // 使用 ScrollViewReader 在双击复位时滚动到内容中心
            .overlay(
                ScrollViewReader { proxy in
                    Color.clear.onChange(of: zoomScale) { _ in
                        print("Zoom scale changed to \(zoomScale)")
                        // 当缩放变化或重置时，尝试滚动到内容中心 (需要一定的延迟才能让ScrollView内容尺寸计算完成)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation {
                                proxy.scrollTo(imageContentID, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: itemID) { _ in // 确保切换图片时也滚动到中心
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation {
                                proxy.scrollTo(imageContentID, anchor: .center)
                            }
                        }
                    }
                }
            )
        } // End of GeometryReader
        .onAppear(perform: resetImagePreviewState) // 视图出现时重置状态
    }


    private var textPreviewer: some View {
        ZStack {
            if let attrString = attributedString {
                // 对于富文本，使用解析出来的背景色以保证对比度
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: detectedBackgroundColor ?? NSColor(white: 0.95, alpha: 1.0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                
                RichTextView(attributedString: attrString, isEditable: false, backgroundColor: nil)
                    .padding(12)
            } else {
                VisualEffectView(material: .selection, blendingMode: .withinWindow)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )

                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineSpacing(4)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
    
    private var footerView: some View {
        HStack {
            if contentType == .image, let img = previewImage {
                Text("\(Int(img.size.width)) × \(Int(img.size.height)) px")
            } else if contentType == .fileURL {
                Text(isDirectory ? "文件夹" : "文件")
            } else {
                Text("\(content.count) 字符")
            }
            Spacer()
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

    // MARK: - Logic and State Reset
    private func calculateTargetSize() {
        let maxWidth: CGFloat = 800
        // 允许更高的预览高度，只要屏幕上方有空间，就充分利用（最高放宽到 850）
        let maxHeight: CGFloat = min(850, PreviewWindowManager.shared.availableHeight)
        let minWidth: CGFloat = 360
        let minHeight: CGFloat = 200
        
        var newWidth: CGFloat = 500
        var newHeight: CGFloat = 420
        
        if contentType == .image, let img = previewImage {
            let headerFooterHeight: CGFloat = 72 // 44 + 28
            let imgW = img.size.width
            let imgH = img.size.height
            
            if imgW > 0 && imgH > 0 {
                let imgRatio = imgW / imgH
                let maxImgWidth = maxWidth
                let maxImgHeight = maxHeight - headerFooterHeight
                let maxImgRatio = maxImgWidth / maxImgHeight
                
                if imgRatio > maxImgRatio {
                    newWidth = maxWidth
                    newHeight = (maxWidth / imgRatio) + headerFooterHeight
                } else {
                    newHeight = maxHeight
                    newWidth = (maxHeight - headerFooterHeight) * imgRatio
                }
            }
        } else if contentType == .fileURL {
            newWidth = 400
            newHeight = 300
        } else {
            // Text or unknown
            if content.count > 1000 {
                newWidth = 700
                newHeight = 550
            } else if content.count < 150 {
                newWidth = 400
                newHeight = 250
            } else {
                newWidth = 500
                newHeight = 420
            }
        }
        
        newWidth = max(minWidth, min(newWidth, maxWidth))
        newHeight = max(minHeight, min(newHeight, maxHeight))
        
        self.targetSize = CGSize(width: newWidth, height: newHeight)
    }

    private func loadPreviewData() async {
        isLoading = true
        defer { 
            isLoading = false 
            calculateTargetSize()
        }
        
        // 重置所有预览状态，确保切换item时不会残留之前的内容
        self.attributedString = nil
        self.previewImage = nil
        self.detectedBackgroundColor = nil
        resetImagePreviewState() // 在加载新数据前重置图片预览状态
        
        guard let listItem = ClipboardDataStore.shared.fetchListItemById(id: itemID) else {
            self.content = "未找到内容"
            self.contentType = .text
            return
        }
        
        self.content = listItem.text
        self.contentType = listItem.contentType
        
        guard let archivedData = ClipboardDataStore.shared.fetchArchivedData(id: itemID) else {
            // 如果没有归档数据，确保显示普通文本内容
            return
        }
        
        var foundDict: [String: Data]? = nil
        if let multiItems = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [[String: Data]] {
            foundDict = multiItems.first
        } else if let singleDict = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [String: Data] {
            foundDict = singleDict
        }
        
        guard let dataDict = foundDict else { return }
        
        // 如果是文件路径，尝试判断是否是图片并直接加载
        if listItem.contentType == .fileURL {
            var targetURL: URL?
            if let fileURLData = dataDict["public.file-url"],
               let fileURLString = String(data: fileURLData, encoding: .utf8) {
                targetURL = URL(string: fileURLString)
            } else {
                targetURL = URL(string: listItem.text) ?? URL(fileURLWithPath: listItem.text)
            }
            
            if let url = targetURL,
               let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                if let img = NSImage(contentsOf: url) {
                    self.previewImage = img
                    self.contentType = .image
                    resetImagePreviewState()
                    return
                }
            }
        }
        
        if listItem.contentType == .image {
            let imageTypes = [NSPasteboard.PasteboardType.tiff.rawValue, NSPasteboard.PasteboardType.png.rawValue, "public.jpeg"]
            for type in imageTypes {
                if let imageData = dataDict[type], let img = NSImage(data: imageData) {
                    self.previewImage = img
                    // 当图片加载成功后，确保重置图片预览状态
                    resetImagePreviewState()
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
    
    private func resetImagePreviewState() {
        zoomScale = 1.0
        currentMagnification = 1.0
        imageOffset = .zero
        currentOffset = .zero
    }
}

// 扩展 CGSize 以支持加法运算
extension CGSize: Equatable {
    public static func == (lhs: CGSize, rhs: CGSize) -> Bool {
        return lhs.width == rhs.width && lhs.height == rhs.height
    }

    public static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
