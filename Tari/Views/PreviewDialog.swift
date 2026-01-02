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
    var clipboard: ClipboardManager?
    
    @State private var content: String = "加载中..."
    @State private var attributedString: NSAttributedString?
    @State private var detectedBackgroundColor: NSColor?
    @State private var previewImage: NSImage? // 新增：用于存储解析后的图片
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏 (保持原样)
            HStack {
                Text(item.contentType == .image ? "图片预览" : "文本预览")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6)).padding(6)
                        .background(Color.white.opacity(0.1)).clipShape(Circle())
                }.buttonStyle(.plain)
            }
            .padding(12).background(Color.black.opacity(0.2))
            
            Divider().background(Color.white.opacity(0.1))
            
            // 内容区域
            Group {
                if item.contentType == .image {
                    if let nsImage = previewImage {
                        GeometryReader { geo in
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }.frame(height: 300)
                    } else {
                        ProgressView().frame(height: 300)
                    }
                } else {
                    if let attributedString = attributedString {
                        let bgColor = detectedBackgroundColor ?? NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.5)
                        RichTextView(attributedString: attributedString, isEditable: false, backgroundColor: bgColor)
                            .frame(height: 300)
                    } else {
                        ScrollView {
                            Text(content)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }.frame(height: 300)
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            HStack { Spacer() }.background(Color.black.opacity(0.2))
        }
        .frame(width: 450)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(RoundedRectangle(cornerRadius: 12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .task {
            await loadPreviewData()
        }
    }
    
    private func loadPreviewData() async {
        self.content = item.text
        guard let archivedData = item.additionalData else { return }
        
        // 🟢 关键修复：解析 [[String: Data]]
        var foundDict: [String: Data]? = nil
        if let multiItems = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [[String: Data]] {
            foundDict = multiItems.first
        } else if let singleDict = try? NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? [String: Data] {
            foundDict = singleDict
        }
        
        guard let dataDict = foundDict else { return }
        
        if item.contentType == .image {
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
