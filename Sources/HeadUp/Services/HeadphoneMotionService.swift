import CoreMotion
import Foundation

final class HeadphoneMotionService: NSObject, CMHeadphoneMotionManagerDelegate {
    enum ServiceError: LocalizedError {
        case motionUnavailable
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .motionUnavailable: return "当前没有可用的 AirPods 头部运动数据"
            case .permissionDenied: return "运动与健身权限已关闭"
            }
        }
    }

    var onSample: ((MotionSample) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onTrackingAvailabilityChanged: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private var manager = CMHeadphoneMotionManager()
    private let audioConnectionService = HeadphoneAudioConnectionService()
    private var hasLoggedFirstSample = false
    private var motionStartInFlight = false
    private var motionUpdateGate = MotionUpdateGate()
    var motionUpdatesEnabled: Bool { motionUpdateGate.isEnabled }
    private var reportedConnected = false
    private var reportedTrackingAvailable = false
    private var connectionEvidence: ConnectionEvidence = .none
    private var connectionWatchdog: DispatchWorkItem?
    private var audioConnectionPoller: DispatchSourceTimer?
    private var motionSamplePoller: DispatchSourceTimer?
    private var livenessRestartCount = 0
    private let connectionTimeout: TimeInterval = 5
    private let audioConnectionQueue = DispatchQueue(
        label: "com.king.headup.audio-connection",
        qos: .utility
    )

    override init() {
        super.init()
        configureMotionManager()
    }

    func start() {
        let authorization = CMHeadphoneMotionManager.authorizationStatus()
        if authorization == .denied || authorization == .restricted {
            HeadUpLog.motion.error("Headphone motion authorization denied or restricted")
            onError?(ServiceError.permissionDenied)
            return
        }

        logMotionManagerState("start")
        HeadUpLog.motion.notice("Starting headphone connection monitoring")
        manager.startConnectionStatusUpdates()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasCompatibleHeadphones = Self.hasInitialConnectionEvidence(
                isDeviceMotionAvailable: self.manager.isDeviceMotionAvailable,
                hasAudioConnectionEvidence: self.audioConnectionService.hasConnectedCompatibleHeadphones()
            )
            self.updateVerifiedConnection(
                hasCompatibleHeadphones,
                evidence: hasCompatibleHeadphones ? .audioRoute : .none,
                force: true
            )
            self.updateTrackingAvailability(false, force: true)
            if hasCompatibleHeadphones, self.motionUpdatesEnabled {
                self.armConnectionWatchdog()
            }
            self.startAudioConnectionPolling()
        }
        startMotionUpdatesIfAvailable()
    }

    func stop() {
        audioConnectionPoller?.cancel()
        audioConnectionPoller = nil
        motionSamplePoller?.cancel()
        motionSamplePoller = nil
        connectionWatchdog?.cancel()
        connectionWatchdog = nil
        motionStartInFlight = false
        livenessRestartCount = 0
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        hasLoggedFirstSample = false
    }

    func restart() {
        HeadUpLog.motion.notice("Restarting headphone motion session")
        motionUpdateGate.prepareForMonitoringRestart()
        stop()
        start()
    }

    func setMotionUpdatesEnabled(_ enabled: Bool) {
        motionUpdateGate.setEnabled(enabled)
        if enabled {
            startMotionUpdatesIfAvailable()
        } else {
            connectionWatchdog?.cancel()
            connectionWatchdog = nil
            motionStartInFlight = false
            motionSamplePoller?.cancel()
            motionSamplePoller = nil
            manager.stopDeviceMotionUpdates()
            HeadUpLog.motion.notice("Headphone device-motion updates paused")
        }
    }

    private func startMotionUpdatesIfAvailable() {
        guard motionUpdatesEnabled else { return }
        guard manager.isDeviceMotionAvailable else {
            logMotionManagerState("motion-unavailable")
            HeadUpLog.motion.notice("Headphone motion is currently unavailable")
            motionStartInFlight = false
            DispatchQueue.main.async { [weak self] in
                self?.updateTrackingAvailability(false)
            }
            return
        }

        guard !manager.isDeviceMotionActive else { return }
        guard !motionStartInFlight else { return }

        logMotionManagerState("before-start-device-motion")
        motionStartInFlight = true
        HeadUpLog.motion.notice("Starting headphone device-motion updates; waiting for connection evidence")

        manager.startDeviceMotionUpdates()
        logMotionManagerState("after-start-device-motion")
        startMotionSamplePolling()
    }

    private func startMotionSamplePolling() {
        motionSamplePoller?.cancel()
        let poller = DispatchSource.makeTimerSource(queue: .main)
        poller.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
        poller.setEventHandler { [weak self] in
            self?.processLatestDeviceMotion()
        }
        motionSamplePoller = poller
        poller.resume()
    }

    private func processLatestDeviceMotion() {
        guard motionUpdatesEnabled, manager.isDeviceMotionActive else { return }
        guard let attitude = manager.deviceMotion?.attitude else { return }

        if !hasLoggedFirstSample {
            hasLoggedFirstSample = true
            HeadUpLog.motion.notice("Received first headphone motion sample")
        }

        let radiansToDegrees = 180.0 / Double.pi
        let sample = MotionSample(
            pitch: attitude.pitch * radiansToDegrees,
            roll: attitude.roll * radiansToDegrees,
            timestamp: Date()
        )

        motionStartInFlight = false
        livenessRestartCount = 0
        updateVerifiedConnection(true, evidence: .motionSample)
        updateTrackingAvailability(true)
        armConnectionWatchdog()
        onSample?(sample)
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        HeadUpLog.motion.notice("Motion-capable headphones connected")
        startMotionUpdatesIfAvailable()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.livenessRestartCount = 0
            self.updateVerifiedConnection(true, evidence: .coreMotionEvent)
            self.updateTrackingAvailability(false)
            if self.motionUpdatesEnabled {
                self.armConnectionWatchdog()
            }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        HeadUpLog.motion.notice("Motion-capable headphones disconnected")
        hasLoggedFirstSample = false
        motionStartInFlight = false
        livenessRestartCount = 0
        motionSamplePoller?.cancel()
        motionSamplePoller = nil
        manager.stopDeviceMotionUpdates()
        DispatchQueue.main.async { [weak self] in
            self?.connectionWatchdog?.cancel()
            self?.connectionWatchdog = nil
            self?.updateTrackingAvailability(false)
            self?.updateVerifiedConnection(false, evidence: .none)
        }
    }

    private func updateVerifiedConnection(
        _ connected: Bool,
        evidence: ConnectionEvidence,
        force: Bool = false
    ) {
        connectionEvidence = connected ? connectionEvidence.merged(with: evidence) : .none
        guard force || reportedConnected != connected else { return }
        reportedConnected = connected
        onConnectionChanged?(connected)
    }

    static func hasInitialConnectionEvidence(
        isDeviceMotionAvailable: Bool,
        hasAudioConnectionEvidence: Bool
    ) -> Bool {
        isDeviceMotionAvailable || hasAudioConnectionEvidence
    }

    private func updateTrackingAvailability(_ available: Bool, force: Bool = false) {
        guard force || reportedTrackingAvailable != available else { return }
        reportedTrackingAvailable = available
        onTrackingAvailabilityChanged?(available)
    }

    private func armConnectionWatchdog() {
        connectionWatchdog?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.motionUpdatesEnabled, self.reportedConnected else { return }
            HeadUpLog.motion.notice("No headphone motion samples within liveness window; restarting motion updates")
            self.logMotionManagerState("liveness-timeout")
            self.updateTrackingAvailability(false)
            self.restartMotionUpdatesAfterLivenessTimeout()
        }
        connectionWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionTimeout, execute: workItem)
    }

    private func configureMotionManager() {
        manager.delegate = self
    }

    private func startAudioConnectionPolling() {
        audioConnectionPoller?.cancel()
        pollAudioConnectionOnce()

        let poller = DispatchSource.makeTimerSource(queue: audioConnectionQueue)
        poller.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
        poller.setEventHandler { [weak self] in
            self?.pollAudioConnectionOnce()
        }
        audioConnectionPoller = poller
        poller.resume()
    }

    private func pollAudioConnectionOnce() {
        let hasAudioEvidence = audioConnectionService.hasConnectedCompatibleHeadphones()
        DispatchQueue.main.async { [weak self] in
            self?.applyAudioConnectionEvidence(hasAudioEvidence)
        }
    }

    private func applyAudioConnectionEvidence(_ hasAudioEvidence: Bool) {
        if hasAudioEvidence {
            let wasConnected = reportedConnected
            updateVerifiedConnection(true, evidence: .audioRoute)
            if motionUpdatesEnabled {
                startMotionUpdatesIfAvailable()
                if !wasConnected {
                    armConnectionWatchdog()
                }
            }
        } else if connectionEvidence == .audioRoute {
            updateTrackingAvailability(false)
            updateVerifiedConnection(false, evidence: .none)
        }
    }

    private func restartMotionUpdatesAfterLivenessTimeout() {
        connectionWatchdog?.cancel()
        connectionWatchdog = nil
        hasLoggedFirstSample = false
        motionStartInFlight = false
        livenessRestartCount += 1
        motionSamplePoller?.cancel()
        motionSamplePoller = nil
        manager.stopDeviceMotionUpdates()
        if livenessRestartCount >= 2 {
            rebuildMotionManagerForRecovery()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.motionUpdatesEnabled, self.reportedConnected else { return }
            self.startMotionUpdatesIfAvailable()
            if !self.reportedTrackingAvailable {
                self.armConnectionWatchdog()
            }
        }
    }

    private func rebuildMotionManagerForRecovery() {
        HeadUpLog.motion.notice("Rebuilding headphone motion manager after repeated liveness timeouts")
        manager.delegate = nil
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        manager = CMHeadphoneMotionManager()
        configureMotionManager()
        manager.startConnectionStatusUpdates()
        logMotionManagerState("after-rebuild-motion-manager")
    }

    private func logMotionManagerState(_ context: StaticString) {
        let authorization = CMHeadphoneMotionManager.authorizationStatus()
        let hasDeviceMotion = manager.deviceMotion != nil
        HeadUpLog.motion.notice(
            "Motion manager state [\(context)]; authorization=\(Self.authorizationDescription(authorization), privacy: .public), available=\(self.manager.isDeviceMotionAvailable, privacy: .public), active=\(self.manager.isDeviceMotionActive, privacy: .public), latestMotion=\(hasDeviceMotion, privacy: .public), startInFlight=\(self.motionStartInFlight, privacy: .public)"
        )
    }

    private static func authorizationDescription(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    private enum ConnectionEvidence {
        case none
        case audioRoute
        case coreMotionEvent
        case motionSample

        private var priority: Int {
            switch self {
            case .none: return 0
            case .audioRoute: return 1
            case .coreMotionEvent: return 2
            case .motionSample: return 3
            }
        }

        func merged(with other: ConnectionEvidence) -> ConnectionEvidence {
            other.priority > priority ? other : self
        }
    }
}

struct MotionUpdateGate {
    private(set) var isEnabled = true

    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    mutating func prepareForMonitoringRestart() {
        isEnabled = true
    }
}
