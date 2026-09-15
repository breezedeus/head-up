import Foundation

struct MotionSample {
    let pitch: Double
    let roll: Double
    let yaw: Double
    let sensorTimestamp: TimeInterval
    let timestamp: Date
}

enum HeadphoneActivity: Equatable {
    case stationary
    case walking
    case running
    case unknown

    var isMoving: Bool { self == .walking || self == .running }

    var diagnosticDescription: String {
        switch self {
        case .stationary: return "stationary"
        case .walking: return "walking"
        case .running: return "running"
        case .unknown: return "unknown"
        }
    }
}

enum CalibrationStage: Equatable {
    case idle
    case upright
    case lookDown

    var instruction: String {
        switch self {
        case .idle: return ""
        case .upright: return L10n.text("请坐直并平视屏幕")
        case .lookDown: return L10n.text("现在请自然低头")
        }
    }
}

enum PostureStatus: Equatable {
    case unavailable
    case disconnected
    case permissionDenied
    case needsCalibration
    case paused
    case moving
    case calibrating(CalibrationStage)
    case good
    case caution
    case warning

    var title: String {
        switch self {
        case .unavailable: return L10n.text("等待头部追踪")
        case .disconnected: return L10n.text("等待 AirPods")
        case .permissionDenied: return L10n.text("需要运动与健身权限")
        case .needsCalibration: return L10n.text("请先校准")
        case .paused: return L10n.text("监测已暂停")
        case .moving: return L10n.text("移动中")
        case .calibrating(let stage): return stage.instruction
        case .good: return L10n.text("姿势良好")
        case .caution: return L10n.text("正在低头")
        case .warning: return L10n.text("注意低头")
        }
    }
}

extension PostureStatus {
    var menuBarIconName: String {
        switch self {
        case .disconnected, .permissionDenied:
            return "menu-disconnected"
        case .unavailable:
            return "menu-calibrating"
        case .needsCalibration, .calibrating:
            return "menu-calibrating"
        case .paused:
            return "menu-paused"
        case .moving:
            return "menu-moving"
        case .good:
            return "menu-good"
        case .caution:
            return "menu-caution"
        case .warning:
            return "menu-warning"
        }
    }
}

struct PostureReading {
    let angle: Double
    let sustainedDuration: TimeInterval
    let isBeyondThreshold: Bool
    let isWarning: Bool
    let shouldNotify: Bool
}
