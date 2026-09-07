import Foundation

public enum ResetCopy {
    public static func format(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "resetting now" }
        if seconds < 60 { return "in \(max(1, Int(seconds.rounded())))s" }
        if seconds < 3600 {
            let minutes = Int((seconds / 60).rounded())
            return "in \(minutes) min"
        }
        if seconds < 36 * 3600 {
            let hours = Int((seconds / 3600).rounded())
            return "in \(hours) hr"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEE h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: date)
    }
}
