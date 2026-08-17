import Foundation

struct Formatters {
    /// 静态复用的相对时间格式器
    static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        // 如果 App 主要为中文界面，固定 zh_CN locale 可避免系统为英文时出现 "3 hours ago" 与 "昨天" 混用的情况；
        // 也可通过 systemIsChinese 动态判断。这里统一使用 zh_CN locale 保证全中文一致性。
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    /// 格式化相对时间
    /// - Parameters:
    ///   - date: 目标日期
    ///   - now: 基准时间，默认 Date()
    /// - Returns: 格式化后的相对时间字符串
    static func formatRelativeTime(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        
        // 1. 小于 1 分钟统一显示为“刚刚”
        if interval < 60 {
            return "刚刚"
        }
        
        let calendar = Calendar.current
        
        // 2. 今天：“3分钟前” / “2小时前”
        if calendar.isDateInToday(date) {
            return relativeDateTimeFormatter.localizedString(for: date, relativeTo: now)
        }
        
        // 3. 昨天：“昨天 16:39”
        if calendar.isDateInYesterday(date) {
            let timeStr = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            return "昨天 \(timeStr)"
        }
        
        // 4. 更早时间：同年显示“MM-dd HH:mm”，跨年显示“yyyy-MM-dd HH:mm”
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        } else {
            return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
    }
}



