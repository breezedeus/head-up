import AppKit
import SwiftUI
import Testing
@testable import HeadUp

@MainActor
struct ScreenPrivacyStoreTests {
    private func sample(_ time: Double, yaw: Double, pitch: Double = 0) -> MotionSample {
        .init(pitch: pitch, roll: 0, yaw: yaw, sensorTimestamp: time, timestamp: Date(timeIntervalSince1970: time))
    }

    @Test func perDisplayCalibrationCommitsOnlyAfterAllScreensFinish() async throws {
        let name = "HeadUpTests.displays.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.keepCoveredOnTrackingLoss = false
        let store = ScreenPrivacyStore(settings: settings, displaysProvider: {
            [.init(id: "a", name: "内建显示屏"), .init(id: "b", name: "外接显示屏")]
        })
        store.handleTrackingAvailabilityChanged(true)
        store.startCalibration()
        var time = 0.0
        for center in [-30.0, 30.0] {
            for (yaw, pitch) in [(center, 0.0), (center + 15, 0), (center - 15, 0), (center, 15), (center, -15)] {
                store.beginCalibrationCapture(delaySeconds: 0)
                await Task.yield()
                // Let the capture task enter its sampling phase.
                for _ in 0..<10 where !store.isCapturingCalibration { await Task.yield() }
                #expect(store.isCapturingCalibration)
                for i in 0...20 { store.handle(sample(time + Double(i) / 10, yaw: yaw, pitch: pitch)) }
                time += 3
            }
            if center == -30 {
                #expect(settings.displayProfiles.isEmpty)
                #expect(store.selectedDisplayID == "b")
                #expect(store.calibrationStage == .center)
            }
        }
        #expect(store.calibrationStage == .idle)
        #expect(settings.displayProfiles.count == 2)
        #expect(abs(settings.displayProfiles[0].calibration.centerYaw + 30) < 0.001)
        #expect(abs(settings.displayProfiles[1].calibration.centerYaw - 30) < 0.001)
        #expect(settings.isEnabled)
        store.startCalibration()
        store.cancelCalibration()
        #expect(settings.displayProfiles.count == 2)
        store.handleTrackingAvailabilityChanged(false)
        store.handle(sample(100, yaw: 80))
        // Losing tracking costs only the per-connection yaw datum, so this asks for a
        // recenter rather than discarding the calibration that was just saved.
        #expect(!store.needsSessionCalibration)
        #expect(store.needsRecenter)
        #expect(store.status == .needsRecenter)
        #expect(settings.displayProfiles.count == 2)
    }

    /// Removing and refitting an earbud used to force a full recalibration on a
    /// multi-display setup, which read as "my settings were wiped".
    /// A recenter reads the pose being held now. With the stream down there is no such
    /// pose, and the buffered ones describe where the head was when the earbud came out —
    /// nothing prunes them by wall-clock time. Accepting a tap there would anchor every
    /// boundary to that stale pose while reporting success.
    @Test func recenterRefusesWhileTrackingIsDown() throws {
        let name = "HeadUpTests.recenterOffline.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.keepCoveredOnTrackingLoss = true
        let profile = ScreenPrivacyCalibrationProfile(
            centerYaw: 0, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
            leftAngle: 20, rightAngle: 20, upAngle: 15, downAngle: 15)
        settings.saveDisplayProfiles([.init(id: "a", name: "内建", calibration: profile)])
        settings.isEnabled = true
        let store = ScreenPrivacyStore(settings: settings, displaysProvider: {
            [.init(id: "a", name: "内建")]
        })
        store.handleTrackingAvailabilityChanged(true)
        for i in 0...20 { store.handle(sample(1 + Double(i) / 20, yaw: 70)) }
        #expect(store.recenter(referenceDisplayID: "a"))

        // The earbud comes out. Steady poses at 70° are still in the buffer.
        store.handleTrackingAvailabilityChanged(false)
        #expect(store.needsRecenter)
        #expect(store.status == .trackingLost)
        #expect(!store.recenter(referenceDisplayID: "a"))
        // Refused, so the datum is still missing rather than quietly set from stale data.
        #expect(store.needsRecenter)
        store.beginRecenterCountdown()
        #expect(store.recenterCountdown == 0)

        // Resuming while still disconnected must report the dead sensor, not the missing
        // datum: `needsRecenter` puts a recenter action in the dashboard, and that action
        // is refused as long as tracking is down.
        store.togglePause()
        #expect(store.status == .paused)
        store.togglePause()
        #expect(store.status == .trackingLost)

        // Reconnecting makes it work again, off poses from this connection.
        store.handleTrackingAvailabilityChanged(true)
        for i in 0...20 { store.handle(sample(10 + Double(i) / 20, yaw: -50)) }
        #expect(store.recenter(referenceDisplayID: "a"))
        #expect(!store.needsRecenter)
        // Facing where the recenter was taken is inside the work area.
        store.handle(sample(12, yaw: -50))
        #expect(store.status == .watching)
    }

    @Test func recenterRestoresSavedProfilesAfterReconnect() throws {
        let name = "HeadUpTests.recenter.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.keepCoveredOnTrackingLoss = false
        let profile = { (center: Double) in
            ScreenPrivacyCalibrationProfile(
                centerYaw: center, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
                leftAngle: 20, rightAngle: 20, upAngle: 15, downAngle: 15)
        }
        settings.saveDisplayProfiles([
            .init(id: "a", name: "内建", calibration: profile(0)),
            .init(id: "b", name: "外接", calibration: profile(-40)),
        ])
        settings.isEnabled = true
        let store = ScreenPrivacyStore(settings: settings, displaysProvider: {
            [.init(id: "a", name: "内建"), .init(id: "b", name: "外接")]
        })
        store.handleTrackingAvailabilityChanged(true)
        // A fresh connection: the datum is unknown, so protection waits for a recenter.
        #expect(store.needsRecenter)
        store.handle(sample(0, yaw: 70))
        #expect(store.status == .needsRecenter)

        // The user faces display "a" and taps its target. The datum here is 70° off
        // from the saved centerYaw of 0.
        for i in 0...20 { store.handle(sample(1 + Double(i) / 20, yaw: 70)) }
        #expect(store.recenter(referenceDisplayID: "a"))
        #expect(!store.needsRecenter)
        #expect(store.status == .watching)

        // Facing "a" is inside the work area, and the saved 40° gap to "b" still holds,
        // so facing "b" is inside as well — without recalibrating either screen.
        store.handle(sample(3, yaw: 70))
        #expect(store.status == .watching)
        store.handle(sample(4, yaw: 30))
        #expect(store.status == .watching)
        // Beyond both work areas, protection still fires.
        store.handle(sample(5, yaw: 160))
        store.handle(sample(6, yaw: 160))
        #expect(store.status != .watching)
        // Saved profiles were never rewritten.
        #expect(settings.displayProfiles.map(\.calibration.centerYaw) == [0, -40])
    }

    /// Tapping the target twice must not compound the offset.
    @Test func recenteringIsIdempotent() throws {
        let name = "HeadUpTests.recenterTwice.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.saveDisplayProfiles([.init(id: "a", name: "内建", calibration: .init(
            centerYaw: 0, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
            leftAngle: 20, rightAngle: 20, upAngle: 15, downAngle: 15))])
        settings.isEnabled = true
        let store = ScreenPrivacyStore(settings: settings, displaysProvider: {
            [.init(id: "a", name: "内建")]
        })
        store.handleTrackingAvailabilityChanged(true)
        for i in 0...20 { store.handle(sample(Double(i) / 20, yaw: 55)) }
        #expect(store.recenter(referenceDisplayID: "a"))
        store.handle(sample(2, yaw: 55))
        let first = store.horizontalOffset
        for i in 0...20 { store.handle(sample(3 + Double(i) / 20, yaw: 55)) }
        #expect(store.recenter(referenceDisplayID: "a"))
        store.handle(sample(5, yaw: 55))
        #expect(abs(store.horizontalOffset - first) < 0.001)
        #expect(store.status == .watching)
    }

    /// A moving head cannot supply a datum.
    @Test func recenterRefusesAnUnsteadyPose() throws {
        let name = "HeadUpTests.recenterMoving.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.saveDisplayProfiles([.init(id: "a", name: "内建", calibration: .init(
            centerYaw: 0, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
            leftAngle: 20, rightAngle: 20, upAngle: 15, downAngle: 15))])
        settings.isEnabled = true
        let store = ScreenPrivacyStore(settings: settings, displaysProvider: {
            [.init(id: "a", name: "内建")]
        })
        store.handleTrackingAvailabilityChanged(true)
        for i in 0...20 { store.handle(sample(Double(i) / 20, yaw: Double(i) * 6)) }
        #expect(!store.recenter(referenceDisplayID: "a"))
        #expect(store.needsRecenter)
        #expect(store.calibrationError != nil)
    }

    @Test func perDisplayAnglesAreAdjustableWithoutRecalibration() throws {
        let name = "HeadUpTests.angles.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        let profile = ScreenPrivacyCalibrationProfile(
            centerYaw: 0, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
            leftAngle: 23, rightAngle: 16, upAngle: 12, downAngle: 14
        )
        settings.saveDisplayProfiles([.init(id: "a", name: "内建显示屏", calibration: profile)])
        let store = ScreenPrivacyStore(settings: settings, displaysProvider: {
            [.init(id: "a", name: "内建显示屏")]
        })
        store.setDisplayAngle(id: "a", edge: \.leftAngle, value: 31)
        #expect(store.displayProfiles.first?.calibration.leftAngle == 31)
        #expect(settings.displayProfiles.first?.calibration.leftAngle == 31)
        // Values below the minimum boundary are clamped instead of saved.
        store.setDisplayAngle(id: "a", edge: \.rightAngle, value: 1)
        #expect(store.displayProfiles.first?.calibration.rightAngle == ScreenPrivacyCalibrationProfile.minimumBoundaryAngle)
        // Unknown displays are ignored.
        store.setDisplayAngle(id: "missing", edge: \.leftAngle, value: 40)
        #expect(store.displayProfiles.count == 1)
    }

    /// The single-profile path used to skip drift correction entirely and rely on
    /// recentering after a dropout, so a long uninterrupted session slowly drifted its
    /// work area out from under the user.
    @Test func singleProfilePathCorrectsDrift() throws {
        let name = "HeadUpTests.singleDrift.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.saveCalibrationProfile(.init(
            centerYaw: 0, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
            leftAngle: 18, rightAngle: 18, upAngle: 15, downAngle: 15))
        settings.isEnabled = true
        settings.leftAngle = 18
        settings.rightAngle = 18
        settings.upAngle = 15
        settings.downAngle = 15
        let store = ScreenPrivacyStore(settings: settings, displaysProvider: { [] })
        store.handleTrackingAvailabilityChanged(true)
        // The first sample re-establishes the per-connection yaw datum, so drift is
        // measured from there.
        store.handle(sample(0, yaw: 0))
        // 10° of drift over four minutes while the head holds still.
        for i in 1...480 {
            let t = Double(i) * 0.5
            store.handle(sample(t, yaw: min(10, t * (10.0 / 200))))
        }
        let status = try #require(store.driftStatusByID.values.first)
        #expect(status.yawCorrection > 5)
        // The work area followed the drift instead of covering the screen.
        #expect(store.status == .watching)
        #expect(abs(store.horizontalOffset) < 5)
    }

    /// A changed display layout invalidates the saved geometry, so no single offset can
    /// restore it. Recentering must refuse rather than paper over a real move.
    @Test func recenterRefusesWhenTheLayoutItselfChanged() async throws {
        let name = "HeadUpTests.recenterLayout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.keepCoveredOnTrackingLoss = false
        settings.saveDisplayProfiles([.init(id: "a", name: "内建", calibration: .init(
            centerYaw: 0, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
            leftAngle: 20, rightAngle: 20, upAngle: 15, downAngle: 15))])
        settings.isEnabled = true
        // A private center: posting on the shared one would cancel the in-flight
        // calibration of every other store alive in this test process.
        let center = NotificationCenter()
        let store = ScreenPrivacyStore(
            settings: settings,
            displaysProvider: { [.init(id: "a", name: "内建")] },
            notificationCenter: center
        )
        store.handleTrackingAvailabilityChanged(true)
        for i in 0...20 { store.handle(sample(Double(i) / 20, yaw: 40)) }
        // Baseline: a plain reconnect can still be recentered.
        #expect(store.recenter(referenceDisplayID: "a"))

        // A screen-parameter change marks the saved geometry stale.
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await Task.yield()
        for _ in 0..<20 where !store.needsSessionCalibration { await Task.yield() }
        #expect(store.needsSessionCalibration)

        for i in 0...20 { store.handle(sample(10 + Double(i) / 20, yaw: 40)) }
        #expect(!store.recenter(referenceDisplayID: "a"))
        store.beginRecenterCountdown()
        #expect(store.recenterCountdown == 0)
        #expect(store.status == .needsCalibration)
    }

    @Test func cancellationStopsPendingCountdown() async throws {
        let name = "HeadUpTests.cancel.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ScreenPrivacyStore(settings: ScreenPrivacySettings(defaults: defaults), displaysProvider: {
            [.init(id: "a", name: "内建显示屏")]
        })
        store.handleTrackingAvailabilityChanged(true)
        store.startCalibration()
        store.beginCalibrationCapture()
        store.cancelCalibration()
        await Task.yield()
        #expect(store.captureCountdown == 0)
        #expect(!store.isCapturingCalibration)
        #expect(store.calibrationStage == .idle)
    }

    @Test func renderCalibrationPreviewWhenRequested() async throws {
        guard let output = ProcessInfo.processInfo.environment["HEADUP_CALIBRATION_PREVIEW"] else { return }
        _ = NSApplication.shared
        let name = "HeadUpTests.preview.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ScreenPrivacyStore(settings: ScreenPrivacySettings(defaults: defaults), displaysProvider: {
            [.init(id: "a", name: "内建显示屏"), .init(id: "b", name: "外接显示屏")]
        })
        store.handleTrackingAvailabilityChanged(true)
        store.startCalibration()
        store.beginCalibrationCapture(delaySeconds: 0)
        for _ in 0..<10 where !store.isCapturingCalibration { await Task.yield() }
        for i in 0...20 { store.handle(sample(Double(i) / 10, yaw: 0)) }
        let view = ScreenPrivacyCalibrationView(store: store)
            .frame(width: 410).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cgImage = try #require(renderer.cgImage)
        let data = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: output))
    }
}
