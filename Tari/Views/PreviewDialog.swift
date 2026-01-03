//
//  PreviewDialog.swift
//  Tari
//
//  Created by wjb on 2025/12/25.
//

import SwiftUI
import AppKit

struct PreviewDialog: View {
    let itemID: UUID
    var onClose: () -> Void
    
    @State private var contentType: ClipboardContentType = .text
    @State private var content: String = "加载中..."
    @State private var attributedString: NSAttributedString?
    @State private var detectedBackgroundColor: NSColor?
    @State private var previewImage: NSImage? // 用于存储解析后的图片
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏 (保持原样)
            HStack {
                Text(contentType == .image ? "图片预览" : "文本预览")
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
                if contentType == .image {
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
        .task(id: itemID) {
            await loadPreviewData()
        }
        .onDisappear {
            // 释放资源，避免内存泄漏
            previewImage = nil
            attributedString = nil
            detectedBackgroundColor = nil
        }
    }
    
    private func loadPreviewData() async {
        // 1. 先获取轻量级列表项信息
        guard let listItem = ClipboardDataStore.shared.fetchListItemById(id: itemID) else { return }
        
        // 更新基本信息
        self.content = listItem.text
        self.contentType = listItem.contentType
        
        // 2. 按需加载完整数据
        guard let archivedData = ClipboardDataStore.shared.fetchArchivedData(id: itemID) else { return }
        
        // 🟢 关键修复：解析 [[String: Data]]
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
