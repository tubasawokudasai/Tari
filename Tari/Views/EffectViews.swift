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
            var detectedBgColor: NSColor?
            // 1. 优先使用文档自带背景
            if let docBg = docAttributes?[NSAttributedString.DocumentAttributeKey.backgroundColor] as? NSColor {
                detectedBgColor = docBg
            }
            // 2. 只有文字明显是浅色时，才给深色背景
            else if attrString.suggestsDarkBackground() {
                detectedBgColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            }
            // 3. 默认情况强制使用纯白背景，防止"深色模式下的黑字"问题
            else {
                detectedBgColor = NSColor.white
            }
            return (attrString, detectedBgColor)
        }.value
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
