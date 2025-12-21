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

struct PreviewView: View {
    let itemId: UUID
    @ObservedObject var manager: ClipboardManager
    var onClose: () -> Void
    @State private var content: String = "加载中..."
    @State private var item: ClipboardItem?
    @State private var scale: CGFloat = 1.0

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
                    // 文本内容使用ScrollView和TextEditor支持滚动和选中
                    ScrollView {
                        TextEditor(text: .constant(content))
                            .font(.system(size: 12, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.clear)
                            .lineSpacing(4)
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
            }
        }
    }
}
