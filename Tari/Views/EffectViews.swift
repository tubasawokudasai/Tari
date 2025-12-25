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
        
        // 关键：文本视图必须绘制背景
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor ?? .textBackgroundColor
        
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
            textView.backgroundColor = backgroundColor ?? .textBackgroundColor
        }
    }
}

// MARK: - RTF Helper for rich text parsing
// MARK: - 改进后的 RTF Helper
struct RTFHelper {
    static func parseAsync(data: Data) async -> (NSAttributedString?, NSColor?) {
        return await Task.detached(priority: .userInitiated) {
            var docAttributes: NSDictionary? = nil
            guard let attrString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: &docAttributes
            ) else {
                return (nil, nil)
            }
            
            let mutableAttrString = NSMutableAttributedString(attributedString: attrString)
            let length = mutableAttrString.length
            
            // 1. 分析文本主要亮度，决定是否需要切换背景色
            // 如果大部分文字都是深色的（例如来自 Xcode 浅色模式），我们需要给它一个浅色背景
            let isMostlyDarkText = attrString.isTextMostlyDark()
            
            // 2. 决定最终的背景色
            // 如果原本 RTF 带背景色（例如网页复制），优先用原本的
            var finalBgColor: NSColor? = docAttributes?[NSAttributedString.DocumentAttributeKey.backgroundColor] as? NSColor
            
            if finalBgColor == nil {
                if isMostlyDarkText {
                    // 如果文字主要是深色，建议使用浅灰色/白色背景，这样语法高亮看得最清楚
                    finalBgColor = NSColor(white: 0.95, alpha: 0.9)
                } else {
                    // 如果文字主要是浅色（暗黑模式代码），或者没有颜色，使用深色玻璃背景
                    finalBgColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.5)
                }
            }
            
            // 3. 智能调整文字颜色
            // 只有当我们在“深色背景”下，且遇到“纯黑色”或“默认颜色”时，才将其改为白色
            // 这样可以保留原本的语法高亮颜色
            if !isMostlyDarkText { // 在深色背景模式下
                mutableAttrString.enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { attributes, range, _ in
                    let currentColor = attributes[.foregroundColor] as? NSColor
                    
                    // 如果没有颜色（默认），或者是纯黑色
                    if currentColor == nil || (currentColor?.isBlackOrVeryDark ?? false) {
                        mutableAttrString.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.9), range: range)
                    }
                    // 如果原本有颜色（比如语法高亮），就保持不动
                }
            }
            
            return (mutableAttrString, finalBgColor)
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
    @State private var item: ClipboardItem?
    @State private var scale: CGFloat = 1.0
    @State private var attributedString: NSAttributedString?
    @State private var detectedBackgroundColor: NSColor?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("剪贴板预览").font(.headline).padding(.leading)
                Spacer()
            }
            .frame(height: 40)
            .background(
            GlassEffectContainer(spacing: 50) {
                Color.clear
                    .glassEffect(in: Rectangle())
            }
        )
            
            if let item = item {
                switch item.contentType {
                case .image:
                    // 图片预览 - 使用单一ScrollView解决嵌套滑动问题
                    if let imageData = item.additionalData, let nsImage = NSImage(data: imageData) {
                        ScrollView([.horizontal, .vertical]) {
                            VStack {
                                HStack {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: nsImage.size.width * scale, height: nsImage.size.height * scale)
                                        .padding()
                                }
                            }
                        }
                        .gesture(MagnificationGesture()
                            .onChanged { value in
                                scale = value
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("无法加载图片")
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .text, .fileURL, .unknown:
                    Group {
                        if let attributedString = attributedString {
                            // 直接使用RichTextView，它内部已经带了滚动条
                            RichTextView(attributedString: attributedString, isEditable: false, backgroundColor: detectedBackgroundColor)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                TextEditor(text: .constant(content))
                                    .font(.system(size: 12, design: .monospaced))
                                    // ✅ 修复点：根据 detectedBackgroundColor 调整文字颜色
                                    // 如果 detectedBackgroundColor 为 nil，TextEditor 默认会适配系统颜色，通常没问题
                                    // 但如果你强制了背景色，这里最好显式设置前景色
                                    .foregroundColor(
                                        (detectedBackgroundColor?.isDarkColor ?? false) ? .white : .primary
                                    )
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.clear)
                                    .lineSpacing(4)
                            }
                        }
                    }
                }
            } else {
                ScrollView {
                    Text("加载中...")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(
            GlassEffectContainer(spacing: 100) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 16))
            }
        )
        .task {
            if let foundItem = manager.items.first(where: { $0.id == itemId }) {
                self.item = foundItem
                self.content = foundItem.text
                
                if let rtfData = foundItem.additionalData {
                    let result = await RTFHelper.parseAsync(data: rtfData)
                    self.attributedString = result.0
                    self.detectedBackgroundColor = result.1
                }
            }
        }
    }
}
