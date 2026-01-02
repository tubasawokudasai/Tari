import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import Accelerate

// MARK: - 1. 全局缓存管理器 (新增部分)
// 使用 Actor 保证线程安全，防止多个线程同时读写崩溃
// 修改 IconColorCache
class IconColorCache { // 改为 Class，因为 NSCache 是引用类型
    static let shared = IconColorCache()
    
    // 使用 NSCache，Key 和 Value 必须是 AnyObject
    private let cache = NSCache<NSData, NSColor>()
    
    private init() {
        // 设置缓存限制，例如最多缓存 200 个图标颜色，或者限制总成本
        cache.countLimit = 200
    }
    
    func color(for data: Data) -> Color? {
        // Data 转 NSData 以便作为 Key
        if let nsColor = cache.object(forKey: data as NSData) {
            return Color(nsColor: nsColor)
        }
        return nil
    }
    
    func save(_ color: Color, for data: Data) {
        let nsColor = NSColor(color)
        cache.setObject(nsColor, forKey: data as NSData)
    }
}

struct ItemCard: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let onTapSelect: () -> Void
    let onTapDouble: () -> Void
    
    @State private var cachedAttributedString: NSAttributedString?
    @State private var cachedBackgroundColor: NSColor?
    @State private var cachedImage: NSImage?
    @State private var cachedAppIcon: NSImage?
    @State private var cachedThemeColor: Color = Color.black.opacity(0.8)
    
    static func == (lhs: ItemCard, rhs: ItemCard) -> Bool {
        return lhs.item.id == rhs.item.id && lhs.isSelected == rhs.isSelected
    }

    private var contentTypeTitle: String {
        switch item.contentType {
        case .text: return "文本"
        case .fileURL: return "文件"
        case .image: return "图片"
        default: return "未知"
        }
    }
    
    private var contentText: String {
        switch item.contentType {
        case .fileURL:
            if let url = URL(string: item.text) { return url.lastPathComponent }
            return item.text
        default: return item.text
        }
    }
    
    private var dynamicTextColor: Color {
        if let bgColor = cachedBackgroundColor {
            return bgColor.isDarkColor ? .white : .black.opacity(0.8)
        }
        return .black.opacity(0.8)
    }

    // MARK: - Header View
    private var headerView: some View {
        let fixedHeaderHeight: CGFloat = 52
        
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contentTypeTitle)
                    .font(.system(size: 14, weight: .bold))
                Text(Formatters.formatRelativeTime(item.creationTime))
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            .foregroundColor(.white)
            .padding(.leading, 12)
            .frame(maxHeight: .infinity)
            
            Spacer(minLength: 0)
            
            if let appIcon = cachedAppIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: fixedHeaderHeight, height: fixedHeaderHeight)
                    .scaleEffect(1.40)
                    .offset(x: 2, y: 0)
                    .clipped()
            }
        }
        .frame(height: fixedHeaderHeight)
        .background(cachedThemeColor)
    }
    
    // MARK: - Content View
    private var contentView: some View {
        VStack(alignment: .leading) {
            contentDisplayView
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: cachedBackgroundColor ?? .white)
        )
    }
    
    @ViewBuilder
    private var contentDisplayView: some View {
        switch item.contentType {
        case .image: imageContentView
        default: textContentView
        }
    }
    
    @ViewBuilder
    private var imageContentView: some View {
        if let nsImage = cachedImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 180)
                .cornerRadius(8)
        } else {
            placeholderView
        }
    }
    
    @ViewBuilder
    private var textContentView: some View {
        if let attrString = cachedAttributedString {
            RichTextView(
                attributedString: attrString,
                isEditable: false,
                backgroundColor: cachedBackgroundColor
            )
            .allowsHitTesting(false)
        } else {
            Text(contentText.prefix(300))
                .lineLimit(8)
                .font(.system(size: 12))
                .foregroundColor(dynamicTextColor)
                .multilineTextAlignment(.leading)
        }
    }

    private var placeholderView: some View {
        VStack(alignment: .leading) {
            Text(item.text.isEmpty ? "正在加载..." : item.text)
                .lineLimit(8)
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.5))
        }
    }
    
    private var footerOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isSelected ? Color.blue : Color.black.opacity(0.1), lineWidth: isSelected ? 4 : 0.5)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            contentView
        }
        .frame(width: 260, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(footerOverlay)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .gesture(TapGesture(count: 2).onEnded { _ in onTapDouble() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { _ in onTapSelect() })
        .contentShape(Rectangle())
        .task(id: item.id) { await loadPreviewData() }
    }
    
    // MARK: - 2. 修改后的数据加载逻辑 (接入缓存)
    private func loadPreviewData() async {
        // 1. 图标处理
        if let appIconData = item.appIcon {
            // 将纯计算/内存操作放入 Task
            let (icon, color) = await Task.detached {
                return autoreleasepool { () -> (NSImage?, Color?) in
                    let thumb = ImageDownsampler.downsample(imageData: appIconData, to: CGSize(width: 52, height: 52))
                    
                    // 查缓存
                    if let cached = IconColorCache.shared.color(for: appIconData) {
                        return (thumb, cached)
                    }
                    
                    // 计算颜色
                    let calcThumb = ImageDownsampler.downsample(imageData: appIconData, to: CGSize(width: 24, height: 24))
                    let rawColor = calcThumb?.dominantColor()
                    // ... 你的颜色转换逻辑 ...
                    let finalColor = rawColor != nil ? Color(nsColor: rawColor!) : nil
                    
                    if let c = finalColor {
                        IconColorCache.shared.save(c, for: appIconData)
                    }
                    
                    return (thumb, finalColor)
                }
            }.value
            
            if let i = icon { self.cachedAppIcon = i }
            if let c = color { self.cachedThemeColor = c }
        }
        
        // 2. 内容图片处理
        guard let archivedData = item.additionalData else { return }
        
        if item.contentType == .image {
            let thumb = await Task.detached {
                return autoreleasepool { () -> NSImage? in
                     // ... 解档逻辑 ...
                     // ... 找到 imageData ...
                     // return ImageDownsampler.downsample(...)
                     return nil // 占位
                }
            }.value
            if let t = thumb { self.cachedImage = t }
        }
    }
    
    // 辅助扩展，让 autoreleasepool 支持 async
    func autoreleasepool<T>(block: () throws -> T) rethrows -> T {
        return try ObjectiveC.autoreleasepool(invoking: block)
    }
}

// MARK: - NSImage Extension (稳定纯色版)
extension NSImage {
    /// 提取主导色 - 无随机性，高性能
    func dominantColor() -> NSColor? {
        var imageRect = CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height)
        guard let cgImage = self.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else { return nil }
        
        // 1. 极速缩放 (24x24)
        let resizeWidth = 24
        let resizeHeight = 24
        
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
        
        var sourceBuffer = vImage_Buffer()
        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }
        defer { free(sourceBuffer.data) }
        
        var destBuffer = vImage_Buffer()
        error = vImageBuffer_Init(&destBuffer, vImagePixelCount(resizeHeight), vImagePixelCount(resizeWidth), 32, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }
        defer { free(destBuffer.data) }
        
        error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else { return nil }
        
        // 2. 提取像素
        let baseAddress = destBuffer.data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = destBuffer.rowBytes
        var pixels: [SIMD4<Float>] = []
        pixels.reserveCapacity(resizeWidth * resizeHeight)
        
        for y in 0..<resizeHeight {
            let rowStart = baseAddress.advanced(by: y * rowBytes)
            for x in 0..<resizeWidth {
                let offset = x * 4
                let b = Float(rowStart[offset])
                let g = Float(rowStart[offset + 1])
                let r = Float(rowStart[offset + 2])
                let a = Float(rowStart[offset + 3])
                
                if a > 100 {
                    pixels.append(SIMD4<Float>(r, g, b, a))
                }
            }
        }
        
        guard !pixels.isEmpty else { return nil }
        
        // 3. K-Means (无随机性)
        let k = 4
        let maxIterations = 5
        
        var centroids = [SIMD4<Float>]()
        let step = max(1, pixels.count / k)
        for i in 0..<k {
            let index = min(i * step, pixels.count - 1)
            centroids.append(pixels[index])
        }
        
        var clusters = [Int](repeating: 0, count: pixels.count)
        
        for _ in 0..<maxIterations {
            for (i, pixel) in pixels.enumerated() {
                var minDist = Float.greatestFiniteMagnitude
                var clusterIdx = 0
                for (j, centroid) in centroids.enumerated() {
                    let dr = pixel.x - centroid.x
                    let dg = pixel.y - centroid.y
                    let db = pixel.z - centroid.z
                    let dist = dr*dr + dg*dg + db*db
                    if dist < minDist {
                        minDist = dist
                        clusterIdx = j
                    }
                }
                clusters[i] = clusterIdx
            }
            
            var sums = [SIMD4<Float>](repeating: .zero, count: k)
            var counts = [Int](repeating: 0, count: k)
            for (i, idx) in clusters.enumerated() {
                sums[idx] += pixels[i]
                counts[idx] += 1
            }
            for j in 0..<k {
                if counts[j] > 0 { centroids[j] = sums[j] / Float(counts[j]) }
            }
        }
        
        // 4. 评分
        var bestCentroid: SIMD4<Float>? = nil
        var maxScore: Float = -1.0
        
        var counts = [Int](repeating: 0, count: k)
        for idx in clusters { counts[idx] += 1 }
        let totalPixelCount = Float(pixels.count)
        
        for i in 0..<k {
            let count = Float(counts[i])
            if count == 0 { continue }
            
            let r = centroids[i].x / 255.0
            let g = centroids[i].y / 255.0
            let b = centroids[i].z / 255.0
            
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let delta = maxC - minC
            let saturation = maxC == 0 ? 0 : delta / maxC
            let brightness = maxC
            
            var score = count / totalPixelCount
            
            if brightness > 0.90 || brightness < 0.15 {
                score *= 0.1
            }
            
            if saturation > 0.25 && brightness > 0.2 && brightness < 0.9 {
                score *= 5.0
            }
            
            if score > maxScore {
                maxScore = score
                bestCentroid = centroids[i]
            }
        }
        
        if bestCentroid == nil {
            let maxIndex = counts.firstIndex(of: counts.max() ?? 0) ?? 0
            bestCentroid = centroids[maxIndex]
        }
        
        let final = bestCentroid!
        return NSColor(
            red: CGFloat(final.x) / 255.0,
            green: CGFloat(final.y) / 255.0,
            blue: CGFloat(final.z) / 255.0,
            alpha: 1.0
        )
    }
}
