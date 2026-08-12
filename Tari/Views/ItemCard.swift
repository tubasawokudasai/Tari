import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import Accelerate

// MARK: - 1. 全局缓存管理器
class IconColorCache {
    static let shared = IconColorCache()
    private let cache = NSCache<NSData, NSColor>()
    
    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 🔴 限制缓存总大小为 50MB
    }
    
    func color(for data: Data) -> Color? {
        if let nsColor = cache.object(forKey: data as NSData) { return Color(nsColor: nsColor) }
        return nil
    }
    
    func save(_ color: Color, for data: Data) {
        let nsColor = NSColor(color)
        cache.setObject(nsColor, forKey: data as NSData, cost: data.count)
    }
}

// MARK: - Extended Content Type
enum ExtendedContentType {
    case text, image, file, link, code
    
    var title: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .link: return "链接"
        case .code: return "代码"
        }
    }
    
    func colors(scheme: ColorScheme) -> (Color, Color) {
        let isDark = scheme == .dark
        switch self {
        case .text:
            return isDark ? (Color(hex: "10b981").opacity(0.15), Color(hex: "34d399")) : (Color(hex: "d1fae5"), Color(hex: "047857"))
        case .image, .file:
            return isDark ? (Color(hex: "6366f1").opacity(0.2), Color(hex: "818cf8")) : (Color(hex: "dbeafe"), Color(hex: "1d4ed8"))
        case .link:
            return isDark ? (Color(hex: "3b82f6").opacity(0.15), Color(hex: "60a5fa")) : (Color(hex: "e0f2fe"), Color(hex: "0369a1"))
        case .code:
            return isDark ? (Color(hex: "f59e0b").opacity(0.15), Color(hex: "fbbf24")) : (Color(hex: "fef3c7"), Color(hex: "b45309"))
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct ItemCard: View, Equatable {
    let item: ClipboardListItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    let lastWakeUpTime: Date
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var tempImage: NSImage?
    @State private var tempAppIcon: NSImage?
    @State private var tempThemeColor: Color = Color.blue
    
    private let dataStore = ClipboardDataStore.shared
    
    static func == (lhs: ItemCard, rhs: ItemCard) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSelected == rhs.isSelected && lhs.lastWakeUpTime == rhs.lastWakeUpTime
    }

    private var extendedType: ExtendedContentType {
        if item.contentType == .image { return .image }
        if item.contentType == .fileURL { return .file }
        
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Link check
        if let url = URL(string: text), (url.scheme == "http" || url.scheme == "https"), url.host != nil {
            if !text.contains(where: { $0.isWhitespace }) {
                return .link
            }
        }
        
        // 2. Code check
        let codeApps = ["Xcode", "Code", "WebStorm", "IntelliJ IDEA", "Android Studio", "Cursor", "Zed", "Sublime Text", "Terminal", "iTerm"]
        if let app = item.appName, codeApps.contains(where: { app.contains($0) }) {
            return .code
        }
        
        let codeKeywords = ["func ", "var ", "let ", "struct ", "class ", "import ", "const ", "=>", "return ", "def ", "function "]
        let containsCode = codeKeywords.contains { text.contains($0) }
        if containsCode && text.contains("{") && text.contains("}") {
            return .code
        }
        
        return .text
    }

    private var fileURLs: [String] {
        if item.contentType == .fileURL {
            return item.text.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        return []
    }
    
    private var isMultipleFiles: Bool { return fileURLs.count > 1 }

    private var cleanDisplayPath: String {
        if isMultipleFiles { return "多个文件" }
        let path = fileURLs.first ?? item.text
        let rawPath = URL(string: path)?.path ?? path
        let userHome = "/Users/\(NSUserName())"
        if rawPath.hasPrefix(userHome) {
            return rawPath.replacingOccurrences(of: userHome, with: "~")
        }
        return rawPath
    }
    
    private var isDirectory: Bool {
        if isMultipleFiles { return false }
        let path = fileURLs.first ?? item.text
        let url = URL(string: path) ?? URL(fileURLWithPath: path)
        return url.pathExtension.isEmpty
    }

    // MARK: - Views
    
    private var typeBadge: some View {
        let colors = extendedType.colors(scheme: colorScheme)
        return Text(extendedType.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(colors.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.0)
            .cornerRadius(6)
    }
    
    @ViewBuilder
    private var previewArea: some View {
        let isDark = colorScheme == .dark
        switch extendedType {
        case .image:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color(hex: "0d0e15") : Color(hex: "f1f5f9"))
                if let nsImage = tempImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(4)
                        .padding(8)
                } else {
                    Text("🖼️ 原型截图") // Fallback / placeholder as in SVG
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? .white.opacity(0.2) : Color(hex: "64748b"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        case .link:
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    let urlString = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(urlString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDark ? Color(hex: "60a5fa") : Color(hex: "2563eb"))
                        .lineLimit(2)
                    if let host = URL(string: urlString)?.host {
                        Text(host)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(isDark ? .white.opacity(0.3) : Color(hex: "64748b"))
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            
            
        case .code:
            Text(item.text.prefix(200))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isDark ? Color(hex: "f3f4f6").opacity(0.6) : Color(hex: "334155"))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                
        case .text:
            VStack(alignment: .leading, spacing: 4) {
                let lines = item.text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                if let firstLine = lines.first {
                    Text(firstLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isDark ? .white.opacity(0.9) : Color(hex: "0f172a"))
                        .lineLimit(1)
                }
                if lines.count > 1 {
                    Text(lines.dropFirst().joined(separator: "\n").prefix(150))
                        .font(.system(size: 11))
                        .foregroundColor(isDark ? .white.opacity(0.4) : Color(hex: "475569"))
                        .lineLimit(3)
                } else {
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            
        case .file:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: 24))
                        .foregroundColor(tempThemeColor)
                    Text(cleanDisplayPath)
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? .white.opacity(0.8) : Color(hex: "334155"))
                        .lineLimit(2)
                }
                if isMultipleFiles {
                    Text("共 \(fileURLs.count) 个文件")
                        .font(.system(size: 10))
                        .foregroundColor(isDark ? .white.opacity(0.4) : Color(hex: "64748b"))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }
    
    private var displayAppName: String {
        guard let appName = item.appName else { return "未知来源" }
        if appName.contains(".") {
            return appName.components(separatedBy: ".").last ?? appName
        }
        return appName
    }
    
    private var footerView: some View {
        let isDark = colorScheme == .dark
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let exactTime = formatter.string(from: item.creationTime)
        
        return VStack(spacing: 0) {
            Divider()
                .background(isDark ? Color.white.opacity(0.06) : Color(hex: "f1f5f9"))
                .padding(.bottom, 8)
                
            HStack(spacing: 6) {
                if let appIcon = tempAppIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(tempThemeColor)
                        .frame(width: 16, height: 16)
                }
                
                Text(displayAppName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.6) : Color(hex: "334155"))
                    
                Spacer()
                
                Text(exactTime)
                    .font(.system(size: 10))
                    .foregroundColor(isDark ? .white.opacity(0.3) : Color(hex: "94a3b8"))
            }
        }
    }

    var body: some View {
        let isDark = colorScheme == .dark
        let cardBgColor = isDark ? Color(hex: "181a26") : .white
        let borderColor = isSelected ? (isDark ? Color(hex: "6366f1") : Color(hex: "2563eb")) : (isDark ? Color.white.opacity(0.08) : Color(hex: "e2e8f0"))
        let glowColor = isDark ? Color(hex: "6366f1").opacity(0.5) : Color(hex: "2563eb").opacity(0.25)
        
        VStack(alignment: .leading, spacing: 0) {
            typeBadge
            
            previewArea
                .padding(.top, 8)
            
            Spacer(minLength: 0)
            
            footerView
        }
        .padding(12)
        .frame(width: 190, height: 190)
        .background(cardBgColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        // Active Glow
        .shadow(color: isSelected ? glowColor : .clear, radius: isDark ? 8 : 6, x: 0, y: 0)
        // General Drop Shadow
        .shadow(color: isDark ? Color.black.opacity(0.6) : Color(hex: "0f172a").opacity(0.06), radius: isDark ? 12 : 8, x: 0, y: isDark ? 8 : 4)
        
        // Opacity for older items (just a visual tweak)
        .opacity(isSelected ? 1.0 : (isDark ? 0.8 : 0.9))
        
        .gesture(TapGesture(count: 2).onEnded { onTapDouble() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { onTapSelect() })
        .id("\(item.id)-\(lastWakeUpTime.timeIntervalSince1970)")
        .task(id: item.id) { await loadPreviewData() }
    }
    
    private func loadPreviewData() async {
        if Task.isCancelled { return }
        
        if let appIcon = await AppIconProvider.shared.icon(for: item.appName) {
            tempAppIcon = appIcon
            if let dominantColor = appIcon.dominantColor() {
                tempThemeColor = Color(nsColor: dominantColor)
            }
        }
        
        if item.contentType == .image {
            autoreleasepool {
                guard let archivedData = dataStore.fetchArchivedData(id: item.id) else { return }
                var foundDict: [String: Data]? = nil
                do {
                    if let newFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [[String: Data]] {
                        foundDict = newFormat.first
                    } else if let oldFormat = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSData.self], from: archivedData) as? [String: Data] {
                        foundDict = oldFormat
                    }
                } catch { return }
                guard let dataDict = foundDict else { return }
                
                var targetData: Data?
                if let png = dataDict[NSPasteboard.PasteboardType.png.rawValue] { targetData = png }
                else if let tiff = dataDict[NSPasteboard.PasteboardType.tiff.rawValue] { targetData = tiff }
                else if let jpeg = dataDict["public.jpeg"] { targetData = jpeg }
                
                if let imageData = targetData {
                    let thumbnail = createThumbnail(from: imageData, maxPixelSize: 300)
                    DispatchQueue.main.async { self.tempImage = thumbnail }
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

private func createThumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
    let options = [
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(maxPixelSize), height: CGFloat(maxPixelSize)))
}