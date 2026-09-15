import Foundation

enum ScreenPrivacyPhase: Equatable {
    case watching
    case waitingToCover
    case covered
    case waitingToReveal
}

struct ScreenPrivacyThresholds: Equatable {
    var hideDelay: TimeInterval
    var revealDelay: TimeInterval
    var hysteresis: Double
}

struct ScreenPrivacyReading: Equatable {
    let phase: ScreenPrivacyPhase
    let horizontalOffset: Double
    let verticalOffset: Double

    var isCovered: Bool {
        phase == .covered || phase == .waitingToReveal
    }
}

struct ScreenPrivacyCalibrationProfile: Codable, Equatable {
    let centerYaw: Double
    let centerPitch: Double
    let leftYawDirection: Double
    let upPitchDirection: Double
    var leftAngle: Double
    var rightAngle: Double
    var upAngle: Double
    var downAngle: Double

    static let minimumBoundaryAngle = 5.0

    static func make(
        centerYaw: Double,
        centerPitch: Double,
        leftYaw: Double,
        rightYaw: Double,
        upPitch: Double,
        downPitch: Double
    ) -> ScreenPrivacyCalibrationProfile? {
        let leftDelta = normalizedAngle(leftYaw - centerYaw)
        let rightDelta = normalizedAngle(rightYaw - centerYaw)
        let upDelta = normalizedAngle(upPitch - centerPitch)
        let downDelta = normalizedAngle(downPitch - centerPitch)

        guard leftDelta.isFinite, rightDelta.isFinite, upDelta.isFinite, downDelta.isFinite,
              abs(leftDelta) >= minimumBoundaryAngle,
              abs(rightDelta) >= minimumBoundaryAngle,
              abs(upDelta) >= minimumBoundaryAngle,
              abs(downDelta) >= minimumBoundaryAngle,
              leftDelta.sign != rightDelta.sign,
              upDelta.sign != downDelta.sign else {
            return nil
        }

        return ScreenPrivacyCalibrationProfile(
            centerYaw: centerYaw,
            centerPitch: centerPitch,
            leftYawDirection: leftDelta >= 0 ? 1 : -1,
            upPitchDirection: upDelta >= 0 ? 1 : -1,
            leftAngle: abs(leftDelta),
            rightAngle: abs(rightDelta),
            upAngle: abs(upDelta),
            downAngle: abs(downDelta)
        )
    }

    func offsets(yaw: Double, pitch: Double) -> (horizontal: Double, vertical: Double) {
        (
            Self.normalizedAngle(yaw - centerYaw) * leftYawDirection,
            Self.normalizedAngle(pitch - centerPitch) * upPitchDirection
        )
    }

    func recentered(yaw: Double, pitch: Double) -> ScreenPrivacyCalibrationProfile {
        ScreenPrivacyCalibrationProfile(
            centerYaw: yaw,
            centerPitch: pitch,
            leftYawDirection: leftYawDirection,
            upPitchDirection: upPitchDirection,
            leftAngle: leftAngle,
            rightAngle: rightAngle,
            upAngle: upAngle,
            downAngle: downAngle
        )
    }

    static func normalizedAngle(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: 360)
        if result >= 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

enum ScreenPrivacyCalibrationStage: CaseIterable, Equatable {
    case idle
    case center
    case left
    case right
    case up
    case down

    var title: String {
        switch self {
        case .idle: return ""
        case .center: return L10n.text("正视工作区中心")
        case .left: return L10n.text("看向最左侧工作位置")
        case .right: return L10n.text("看向最右侧工作位置")
        case .up: return L10n.text("看向最高工作位置")
        case .down: return L10n.text("看向最低工作位置")
        }
    }

    var sequenceNumber: Int {
        switch self {
        case .idle: return 0
        case .center: return 1
        case .left: return 2
        case .right: return 3
        case .up: return 4
        case .down: return 5
        }
    }

    var next: ScreenPrivacyCalibrationStage {
        switch self {
        case .idle: return .center
        case .center: return .left
        case .left: return .right
        case .right: return .up
        case .up: return .down
        case .down: return .idle
        }
    }
}

enum ScreenPrivacyRuntimeStatus: Equatable {
    case disabled
    case needsCalibration
    /// Saved calibration is still valid; only this connection's yaw datum is missing,
    /// so a one-tap recenter is enough instead of a full recalibration.
    case needsRecenter
    case calibrating(ScreenPrivacyCalibrationStage)
    case watching
    case coveringSoon
    case covered
    case revealingSoon
    case paused
    case trackingLost

    var title: String {
        switch self {
        case .disabled: return L10n.text("屏幕保护未开启")
        case .needsCalibration: return L10n.text("需要校准工作区")
        case .needsRecenter: return L10n.text("需要重新对准中心")
        case .calibrating(let stage): return stage.title
        case .watching: return L10n.text("屏幕保护已就绪")
        case .coveringSoon: return L10n.text("头部已离开工作区")
        case .covered: return L10n.text("屏幕已保护")
        case .revealingSoon: return L10n.text("正在恢复屏幕")
        case .paused: return L10n.text("屏幕保护已暂停")
        case .trackingLost: return L10n.text("头部追踪暂时中断")
        }
    }
}

enum ScreenPrivacyBackgroundStyle: String, CaseIterable, Identifiable {
    case blur
    case solid

    var id: String { rawValue }
    var title: String { self == .blur ? L10n.text("模糊并压暗") : L10n.text("纯色遮挡") }
}


struct ScreenPrivacyDisplayProfile: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    var calibration: ScreenPrivacyCalibrationProfile
}

extension ScreenPrivacyCalibrationProfile {
    func contains(yaw: Double, pitch: Double, inset: Double = 0) -> Bool {
        let offset = offsets(yaw: yaw, pitch: pitch)
        return offset.horizontal <= max(0, leftAngle - inset)
            && offset.horizontal >= -max(0, rightAngle - inset)
            && offset.vertical <= max(0, upAngle - inset)
            && offset.vertical >= -max(0, downAngle - inset)
    }
}
