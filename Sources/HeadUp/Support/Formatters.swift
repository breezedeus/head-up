import Foundation

enum HeadUpFormatters {
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return L10n.text("{0} 秒", "\(seconds)") }
        return L10n.text("{0} 分 {1} 秒", "\(seconds / 60)", "\(seconds % 60)")
    }
}
