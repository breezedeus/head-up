import Foundation

struct MotionSample {
    let pitch: Double
    let roll: Double
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
        case .upright: return "请坐直并平视屏幕"
        case .lookDown: return "现在请自然低头"
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
        case .unavailable: return "设备不支持头部追踪"
        case .disconnected: return "等待 AirPods"
        case .permissionDenied: return "需要运动与健身权限"
        case .needsCalibration: return "请先校准"
        case .paused: return "监测已暂停"
        case .moving: return "移动中"
        case .calibrating(let stage): return stage.instruction
        case .good: return "姿势良好"
        case .caution: return "正在低头"
        case .warning: return "注意低头"
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
