import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct KeyEventView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> NSEvent?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.setupMonitor()
        }
        return view
    }

    // 🔴 关键修复：这里必须更新 parent，否则闭包里的 State (如 isSearchFocused) 永远是旧值
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator {
        var parent: KeyEventView
        var monitor: Any?

        init(parent: KeyEventView) {
            self.parent = parent
        }

        func setupMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // 这里调用 parent 时，因为 updateNSView 的存在，parent 永远是最新的
                return self?.parent.onKeyDown(event)
            }
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

// MARK: - NSColor extension for brightness detection
extension NSColor {
    /// 判断颜色是否属于“深色” (用于决定上面的文字是用白色还是黑色)
    var isDarkColor: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        // 亮度公式 (Luminance)
        let brightness = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return brightness < 0.5 // 亮度小于 0.5 认为是深色背景
    }
}

// MARK: - NSAttributedString 扩展，用于检测富文本是否适合深色背景
extension NSAttributedString {
    /// 判断这段富文本是否看起来像在深色背景上（即文字主要为浅色）
    func suggestsDarkBackground() -> Bool {
        guard length > 0 else { return false }
        var isLightText = false
        enumerateAttribute(.foregroundColor,
                           in: NSRange(location: 0, length: min(length, 20)),
                           options: []) { value, _, stop in
            if let color = value as? NSColor,
               let rgb = color.usingColorSpace(.sRGB) {
                let brightness = 0.299 * rgb.redComponent
                               + 0.587 * rgb.greenComponent
                               + 0.114 * rgb.blueComponent
                if brightness > 0.7 {
                    isLightText = true
                    stop.pointee = true
                }
            }
        }
        return isLightText
    }
}

// MARK: - 可配置背景的 RichTextView
struct RichTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let isEditable: Bool
    let backgroundColor: NSColor?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false // scrollView 背景透明，实际内容背景由 textView 绘制

        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        
        // 关键：文本视图不绘制自己的背景，由外部容器统一管理
        textView.drawsBackground = false
        
        // 允许 TextView 随容器拉伸
        textView.autoresizingMask = [.width, .height]
        
        textView.textStorage?.setAttributedString(attributedString)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            // 只有当内容真正改变时才更新，避免循环刷新
            if textView.attributedString() != attributedString {
                textView.textStorage?.setAttributedString(attributedString)
            }
            // 不再设置背景色，由外部容器统一管理
        }
    }
}

// MARK: - RTF Helper for rich text parsing
// MARK: - 改进后的 RTF Helper
struct RTFHelper {
    static func parseAsync(data: Data) async -> (NSAttributedString?, NSColor?) {
        // 检查取消
        if Task.isCancelled { return (nil, nil) }
        
        return Task.detached(priority: .userInitiated) {
            return autoreleasepool {
                var docAttributes: NSDictionary? = nil
                guard let attrString = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: &docAttributes
                ) else {
                    return (nil, nil)
                }
                
                // 如果发现 parse 出来的 string 长度极长，进行截断以节省渲染内存
                let limit = 5000
                let finalString: NSAttributedString
                if attrString.length > limit {
                    finalString = attrString.attributedSubstring(from: NSRange(location: 0, length: limit))
                } else {
                    finalString = attrString
                }
                
                let mutableAttrString = NSMutableAttributedString(attributedString: finalString)
                let length = mutableAttrString.length
                
                // 1. 分析文本主要亮度，决定是否需要切换背景色
                // 如果大部分文字都是深色的（例如来自 Xcode 浅色模式），我们需要给它一个浅色背景
                let isMostlyDarkText = finalString.isTextMostlyDark()
                
                // 2. 决定最终的背景色
                // 如果原本 RTF 带背景色（例如网页复制），优先用原本的
                var finalBgColor: NSColor? = docAttributes?[NSAttributedString.DocumentAttributeKey.backgroundColor] as? NSColor
                
                if finalBgColor == nil {
                    if isMostlyDarkText {
                        // 如果文字主要是深色，建议使用浅灰色/白色背景，这样语法高亮看得最清楚
                        finalBgColor = NSColor(white: 0.95, alpha: 1.0)
                    } else {
                        // 如果文字主要是浅色，也使用浅色背景，确保在任何情况下都有良好的可读性
                        finalBgColor = NSColor(white: 0.95, alpha: 1.0)
                    }
                }
                
                // 3. 智能调整文字颜色
                // 由于我们使用浅色背景，确保所有文字都有良好的对比度
                mutableAttrString.enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { attributes, range, _ in
                    let currentColor = attributes[.foregroundColor] as? NSColor
                    
                    // 如果没有颜色（默认），使用黑色
                    if currentColor == nil {
                        mutableAttrString.addAttribute(.foregroundColor, value: NSColor.black, range: range)
                    } else if !isMostlyDarkText {
                        // 如果文字主要是浅色，确保在浅色背景上有足够对比度
                        let brightness = currentColor?.brightnessComponent ?? 0
                        if brightness > 0.7 { // 如果颜色太浅
                            mutableAttrString.addAttribute(.foregroundColor, value: NSColor.black, range: range)
                        }
                    }
                    // 如果原本有颜色且对比度足够，就保持不动
                }
                
                return (mutableAttrString, finalBgColor)
            }
        }.value
    }
}

// MARK: - 辅助扩展
extension NSAttributedString {
    /// 采样判断文本是否主要由深色构成
    func isTextMostlyDark() -> Bool {
        guard length > 0 else { return false }
        var darkScore = 0
        var sampleCount = 0
        
        // 只采样前 500 个字符以提高性能
        let checkLength = min(length, 500)
        
        enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: checkLength), options: []) { value, range, _ in
            if let color = value as? NSColor {
                if color.isBlackOrVeryDark {
                    darkScore += range.length
                }
            } else {
                // 没有颜色属性通常默认为黑色
                darkScore += range.length
            }
            sampleCount += range.length
        }
        
        return Double(darkScore) / Double(sampleCount) > 0.5
    }
}

extension NSColor {
    /// 判断颜色是否接近黑色
    var isBlackOrVeryDark: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return true } // 无法转换通常假设为黑
        let brightness = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return brightness < 0.3 // 阈值可以调节
    }
}

struct PreviewView: View {
    let itemId: UUID
    @ObservedObject var manager: ClipboardManager
    var onClose: () -> Void
    @State private var content: String = "加载中..."
    @State private var item: ClipboardListItem?
    @State private var scale: CGFloat = 1.0
    @State private var attributedString: NSAttributedString?
    @State private var detectedBackgroundColor: NSColor?
    @State private var previewImage: NSImage? // 新增：用于存储解析后的图片

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("剪贴板预览").font(.headline).padding(.leading)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.trailing)
            }
            .frame(height: 40)
            .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow))
            
            if let item = item {
                switch item.contentType {
                case .image:
                    if let nsImage = previewImage {
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: nsImage.size.width * scale, height: nsImage.size.height * scale)
                                .padding()
                        }
                        .gesture(MagnificationGesture()
                            .onChanged { value in
                                scale = value
                            }
                        )
                    } else {
                        VStack {
                            ProgressView()
                            Text("解析图片中...")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                case .text, .fileURL, .unknown:
                    if let attrString = attributedString {
                        RichTextView(attributedString: attrString, isEditable: false, backgroundColor: nil)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: detectedBackgroundColor ?? NSColor(white: 0.95, alpha: 1.0)))
                            )
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(content)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                ProgressView("正在查找条目...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .task {
            await loadData()
        }
    }

    // 🔴 核心修复：同步 ItemCard 的多层级数据解析逻辑
    private func loadData() async {
        guard let foundItem = manager.items.first(where: { $0.id == itemId }) else { return }
        self.item = foundItem
        self.content = foundItem.text
        
        // 使用ClipboardDataStore获取完整的archivedData
        guard let archivedData = ClipboardDataStore.shared.fetchArchivedData(id: foundItem.id) else {
            self.detectedBackgroundColor = nil
            return
        }

        // 1. 解析数据字典 (支持 [[String: Data]] 和 [String: Data])
        var foundDict: [String: Data]? = nil
        do {
            // 使用新的 API 尝试解析新格式 [[String: Data]]
            if let newFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [[String: Data]] {
                foundDict = newFormat.first
            }
            // 使用新的 API 尝试解析旧格式 [String: Data]
            else if let oldFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [String: Data] {
                foundDict = oldFormat
            }
        } catch {
            print("解析剪贴板数据失败: \(error)")
        }

        guard let dataDict = foundDict else { return }

        // 2. 根据类型提取内容
        if foundItem.contentType == .image {
            let imageTypes = [
                NSPasteboard.PasteboardType.tiff.rawValue,
                NSPasteboard.PasteboardType.png.rawValue,
                "public.jpeg"
            ]
            for type in imageTypes {
                if let imageData = dataDict[type], let img = NSImage(data: imageData) {
                    self.previewImage = img
                    self.detectedBackgroundColor = .white
                    break
                }
            }
        } else {
            // RTF 解析
            if let rtfData = dataDict[NSPasteboard.PasteboardType.rtf.rawValue] ?? dataDict["public.rtf"] {
                let result = await RTFHelper.parseAsync(data: rtfData)
                self.attributedString = result.0
                self.detectedBackgroundColor = result.1
            }
        }
    }
}
