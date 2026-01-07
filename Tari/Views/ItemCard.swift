import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import Accelerate

// MARK: - 1. 全局缓存管理器
class IconColorCache {
    static let shared = IconColorCache()
    private let cache = NSCache<NSData, NSColor>()
    private init() { cache.countLimit = 200 }
    
    func color(for data: Data) -> Color? {
        if let nsColor = cache.object(forKey: data as NSData) { return Color(nsColor: nsColor) }
        return nil
    }
    
    func save(_ color: Color, for data: Data) {
        let nsColor = NSColor(color)
        cache.setObject(nsColor, forKey: data as NSData)
    }
}

struct ItemCard: View, Equatable {
    let item: ClipboardListItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    let lastWakeUpTime: Date
    
    @State private var tempImage: NSImage?
    @State private var tempAppIcon: NSImage?
    @State private var tempThemeColor: Color = Color.blue
    
    private let dataStore = ClipboardDataStore.shared
    
    static func == (lhs: ItemCard, rhs: ItemCard) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSelected == rhs.isSelected && lhs.lastWakeUpTime == rhs.lastWakeUpTime
    }

    // MARK: - 逻辑处理 (修复 URL 报错)
    private var isDirectory: Bool {
        // 剪贴板路径处理：先尝试从 string 初始化，如果失败则视为普通路径
        let url = URL(string: item.text) ?? URL(fileURLWithPath: item.text)
        return url.pathExtension.isEmpty
    }

    private var cleanDisplayPath: String {
        // 将 file:///Users/xxx/Downloads 转换为 ~/Downloads
        let rawPath = URL(string: item.text)?.path ?? item.text
        let userHome = "/Users/\(NSUserName())"
        if rawPath.hasPrefix(userHome) {
            return rawPath.replacingOccurrences(of: userHome, with: "~")
        }
        return rawPath
    }

    private var contentTypeTitle: String {
        switch item.contentType {
        case .text: return "文本"
        case .fileURL: return isDirectory ? "文件夹" : "文件"
        case .image: return "图片"
        default: return "未知"
        }
    }
    
    private var relativeTimeString: String {
        Formatters.formatRelativeTime(item.creationTime, now: lastWakeUpTime)
    }

    // MARK: - Header View
    private var headerView: some View {
        let fixedHeaderHeight: CGFloat = 52
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contentTypeTitle)
                    .font(.system(size: 14, weight: .bold))
                Text(relativeTimeString)
                    .font(.system(size: 10))
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            .padding(.leading, 14)
            
            Spacer()
            
            if let appIcon = tempAppIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: fixedHeaderHeight, height: fixedHeaderHeight)
                    .scaleEffect(1.4)
                    .offset(x: 2)
                    .clipped()
            }
        }
        .frame(height: fixedHeaderHeight)
        .background(tempThemeColor)
    }
    
    // MARK: - Content View (精简布局：图标 + 路径)
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 大图标区域
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tempThemeColor.opacity(0.08))
                    .frame(height: 120)
                
                Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 56))
                    .foregroundColor(tempThemeColor)
            }
            
            // 纯路径显示
            Text(cleanDisplayPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary.opacity(0.7))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 4)
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    @ViewBuilder
    private var contentDisplayView: some View {
        switch item.contentType {
        case .image:
            if let nsImage = tempImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
            }
        case .fileURL:
            contentView // 使用上面定义的精简版布局
        case .text:
            Text(item.text.prefix(300))
                .font(.system(size: 12))
                .lineLimit(10)
        default:
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            if item.contentType == .fileURL {
                contentView
            } else {
                VStack {
                    contentDisplayView
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 260, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.blue : Color.black.opacity(0.1), lineWidth: isSelected ? 3 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
        .gesture(TapGesture(count: 2).onEnded { onTapDouble() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { onTapSelect() })
        .id(lastWakeUpTime.timeIntervalSince1970)
        .task(id: item.id) { await loadPreviewData() }
    }
    
    private func loadPreviewData() async {
        if let appIcon = await AppIconProvider.shared.icon(for: item.appName) {
            tempAppIcon = appIcon
            if let dominantColor = appIcon.dominantColor() {
                tempThemeColor = Color(nsColor: dominantColor)
            }
        }
        
        if item.contentType == .image, let archivedData = dataStore.fetchArchivedData(id: item.id) {
            // 解析归档的图片数据
            var foundDict: [String: Data]? = nil
            do {
                // 支持新格式 [[String: Data]]
                if let newFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [[String: Data]] {
                    foundDict = newFormat.first
                }
                // 支持旧格式 [String: Data]
                else if let oldFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [String: Data] {
                    foundDict = oldFormat
                }
            } catch {
                print("解析剪贴板数据失败: \(error)")
            }
            
            // 提取实际图片数据
            if let dataDict = foundDict {
                // 尝试获取PNG或TIFF格式的图片数据
                if let pngData = dataDict[NSPasteboard.PasteboardType.png.rawValue] {
                    tempImage = ImageDownsampler.downsample(imageData: pngData, to: CGSize(width: 240, height: 180))
                } else if let tiffData = dataDict[NSPasteboard.PasteboardType.tiff.rawValue] {
                    tempImage = ImageDownsampler.downsample(imageData: tiffData, to: CGSize(width: 240, height: 180))
                }
            }
        }
    }
}

// MARK: - Dominant Color Extension
extension NSImage {
    func dominantColor() -> NSColor? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let cgImage = self.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else { return nil }
        
        // 极简采样逻辑
        let width = 20, height = 20
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let rawData = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * bytesPerPixel)
        
        guard let context = CGContext(data: rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            rawData.deallocate(); return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, count: CGFloat = 0
        for i in 0..<(width * height) {
            let offset = i * bytesPerPixel
            let alpha = CGFloat(rawData[offset + 3])
            if alpha > 128 {
                r += CGFloat(rawData[offset])
                g += CGFloat(rawData[offset + 1])
                b += CGFloat(rawData[offset + 2])
                count += 1
            }
        }
        rawData.deallocate()
        
        if count == 0 { return NSColor.systemBlue }
        return NSColor(red: r/count/255, green: g/count/255, blue: b/count/255, alpha: 1.0)
    }
}