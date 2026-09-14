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
        #expect(store.needsSessionCalibration)
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
