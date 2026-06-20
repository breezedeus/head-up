import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: PostureStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainContent
            Divider()
            todaySummary
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("抬头")
                    .font(.title2.weight(.semibold))
                Label(store.connectionText, systemImage: "airpodspro")
                    .font(.caption)
                    .foregroundStyle(store.isConnected ? .secondary : .tertiary)
            }
            Spacer()
            Circle()
                .fill(store.isConnected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
                .accessibilityLabel(store.isConnected ? "已连接" : "未连接")
        }
        .padding(16)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 16) {
            if store.calibrationStage != .idle {
                calibrationView
            } else if store.status == .permissionDenied {
                permissionView
            } else {
                PostureGauge(
                    angle: store.angle,
                    status: store.status,
                    duration: store.sustainedDuration
                )
            }

            HStack(spacing: 10) {
                Button {
                    store.startCalibration()
                } label: {
                    Label("重新校准", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.isConnected || store.calibrationStage != .idle)

                Button {
                    store.isMonitoring.toggle()
                } label: {
                    Label(store.isMonitoring ? "暂停" : "继续", systemImage: store.isMonitoring ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }

    private var calibrationView: some View {
        VStack(spacing: 12) {
            Image(systemName: store.calibrationStage == .upright ? "person.fill.checkmark" : "person.fill.turn.down")
                .font(.system(size: 42))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
            Text(store.calibrationStage.instruction)
                .font(.headline)
            Text(store.calibrationStage == .upright ? "保持 2 秒，不要移动" : "像平时看键盘那样低头")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: store.calibrationProgress)
                .frame(width: 220)
        }
        .frame(height: 145)
    }

    private var permissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("需要运动与健身权限")
                .font(.headline)
            Button("打开系统设置") {
                store.openMotionPrivacySettings()
            }
        }
        .frame(height: 145)
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                summaryItem(icon: "checkmark.circle.fill", color: .green, title: "良好姿势", value: "\(store.goodPosturePercentage)%")
                Divider().frame(height: 34)
                summaryItem(icon: "bell.fill", color: .orange, title: "提醒触发", value: "\(store.remindersToday) 次")
            }
        }
        .padding(16)
    }

    private func summaryItem(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline).foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button {
                SettingsWindowPresenter.present(using: openWindow)
            } label: {
                Label("设置…", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Button("退出抬头") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}
