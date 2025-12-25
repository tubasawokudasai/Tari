//
//  PreviewDialog.swift
//  Tari
//
//  Created by wjb on 2025/12/25.
//

import SwiftUI
import AppKit

struct PreviewDialog: View {
    let item: ClipboardItem
    var onClose: () -> Void
    // 移除 ObservedObject clipboard，因为只用来复制，我们可以简化依赖
    var clipboard: ClipboardManager?
  
    @State private var content: String = "加载中..."
    @State private var attributedString: NSAttributedString?
    @State private var detectedBackgroundColor: NSColor?
    @State private var scale: CGFloat = 1.0
  
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏
            HStack {
                Text(item.contentType == .image ? "图片预览" : "文本预览")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
              
                Spacer()
              
                // 关闭按钮
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.black.opacity(0.2))
          
            Divider()
                .background(Color.white.opacity(0.1))
          
            // 内容区域
            if item.contentType == .image, let data = item.additionalData, let nsImage = NSImage(data: data) {
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(height: 300) // 图片固定高度区域
            } else {
                // 文本内容区域
                Group {
                    if let attributedString = attributedString {
                        // 使用detectedBackgroundColor，如果为nil则使用深色半透明背景
                        let bgColor = detectedBackgroundColor ?? NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.5)
                        RichTextView(attributedString: attributedString, isEditable: false, backgroundColor: bgColor)
                            .frame(height: 300)
                    } else {
                        ScrollView {
                            Text(content)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineSpacing(4)
                        }
                        .frame(height: 300)
                    }
                }
                .onAppear {
                    print("DEBUG: Rendering text content, attributedString = \(attributedString != nil)")
                }
            }
          
            Divider()
                .background(Color.white.opacity(0.1))
          
            // 底部元数据栏
            HStack {
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.5))
            .background(Color.black.opacity(0.2))
        }
        .frame(width: 450) // 固定宽度
        .background(
            // 这里实现深色毛玻璃背景
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        // 加上边框高亮
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(12)
        .task {
            print("DEBUG: PreviewDialog.task called for item: \(item.id), contentType: \(item.contentType)")
            print("DEBUG: Item text: \(item.text)")
            print("DEBUG: Item has additionalData: \(item.additionalData != nil)")
          
            self.content = item.text
            if let rtfData = item.additionalData, item.contentType == .text {
                print("DEBUG: Processing RTF data for text item")
                let result = await RTFHelper.parseAsync(data: rtfData)
                print("DEBUG: RTFHelper.parseAsync result: attributedString = \(result.0 != nil)")
                self.attributedString = result.0
                // 使用RTFHelper返回的背景色
                self.detectedBackgroundColor = result.1
            } else if item.contentType == .text {
                print("DEBUG: Processing plain text item, no additionalData")
            }
        }
    }
}
