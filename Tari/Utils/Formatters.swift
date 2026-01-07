import Foundation

struct Formatters {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    // 用于格式化“昨天 HH:mm”和“MM-dd HH:mm”中的时间部分
    private static let hourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // 用于格式化“MM-dd HH:mm”中的日期和时间
    private static let monthDayHourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    static func formatRelativeTime(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        
        // 1. 刚刚（小于1分钟）
        if interval < 60 {
            return "刚刚"
        }
        
        // 使用 Calendar 来判断是否是今天、昨天
        let calendar = Calendar.current // 获取当前日历
        
        // 检查是否是今天
        if calendar.isDateInToday(date) {
            // 如果是今天，使用 RelativeDateTimeFormatter
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full
            relativeFormatter.locale = Locale(identifier: "zh_CN")
            // 对于今天的时间，RelativeDateTimeFormatter 会返回"X分钟前"或"X小时前"
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        
        // 检查是否是昨天
        if calendar.isDateInYesterday(date) {
            // 如果是昨天，显示"昨天 HH:mm"
            return "昨天 \(Formatters.hourMinuteFormatter.string(from: date))"
        }
        
        // 超过昨天，显示"MM-dd HH:mm"
        // 注意：这里我们不再需要 RelativeDateTimeFormatter，而是直接用 DateFormatter 来处理
        return Formatters.monthDayHourMinuteFormatter.string(from: date)
    }
}
