import OSLog

enum HeadUpLog {
    static let lifecycle = Logger(subsystem: "com.king.headup", category: "Lifecycle")
    static let motion = Logger(subsystem: "com.king.headup", category: "Motion")
    static let activity = Logger(subsystem: "com.king.headup", category: "Activity")
    static let calibration = Logger(subsystem: "com.king.headup", category: "Calibration")
    static let reminders = Logger(subsystem: "com.king.headup", category: "Reminders")
    static let windowing = Logger(subsystem: "com.king.headup", category: "Windowing")
}
