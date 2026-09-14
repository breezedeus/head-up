import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: PostureStore
    @ObservedObject private var privacyStore: ScreenPrivacyStore

    init(store: PostureStore) {
        self.store = store
        self.privacyStore = store.privacyStore
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 410)
    }

    private var header: some View {
        VStack(spacing: 11) {
            HStack {
                Text(L10n.text("抬头"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    HeadUpWindowPresenter.present(id: HeadUpWindowID.settings, using: openWindow)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help(L10n.text("设置"))
                .accessibilityLabel(L10n.text("打开设置"))

                Menu {
                    Button(L10n.text("测试提醒")) { store.testReminder() }
                    Button(store.privacySettings.isEnabled ? L10n.text("关闭屏幕保护") : L10n.text("开启屏幕保护")) {
                        store.setScreenPrivacyEnabled(!store.privacySettings.isEnabled)
                    }
                    if store.privacySettings.isEnabled {
                        Button(store.privacyStore.status == .paused ? L10n.text("继续屏幕保护") : L10n.text("暂停屏幕保护")) {
                            store.privacyStore.togglePause()
                        }
                    }
                    Button(L10n.text("使用指南")) {
                        HeadUpWindowPresenter.present(id: HeadUpWindowID.guide, using: openWindow)
                    }
                    Button(L10n.text("查看更新")) { NSWorkspace.shared.open(HeadUpLinks.releases) }
                    Divider()
                    Button(L10n.text("退出抬头")) { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(L10n.text("更多操作"))
            }

            HStack(spacing: 8) {
                Image(systemName: "airpodspro")
                Circle()
                    .fill(store.isConnected ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(store.connectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if privacyStore.calibrationStage != .idle {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    PostureGauge(angle: store.angle, status: store.status,
                                 duration: store.sustainedDuration, threshold: store.settings.threshold)
                        .scaleEffect(0.55)
                        .frame(width: 100, height: 65)
                    Text(statusHeadline).font(.headline).foregroundStyle(statusColor)
                    Spacer()
                    Button(L10n.text("姿态校准")) {
                        privacyStore.cancelCalibration()
                        store.startCalibration()
                    }
                    .controlSize(.small)
                    .disabled(!store.isConnected || privacyStore.isCapturingCalibration || privacyStore.captureCountdown > 0)
                }.padding(16)
                Divider()
                ScreenPrivacyCalibrationView(store: privacyStore)
            }
        } else if store.calibrationStage != .idle {
            calibrationView
                .padding(20)
        } else if store.status == .permissionDenied {
            permissionView
                .padding(20)
        } else {
            dashboardContent
        }
    }

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                PostureGauge(
                    angle: store.angle,
                    status: store.status,
                    duration: store.sustainedDuration,
                    threshold: store.settings.threshold
                )

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Image(nsImage: HeadUpIconResource.image(named: store.status.menuBarIconName, pointHeight: 19))
                            .renderingMode(.template)
                        Text(statusHeadline)
                    }
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(statusColor)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text("提醒阈值 {0}°", "\(Int(store.settings.threshold))"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 16)

            actionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 18)

            Divider()

            ScreenPrivacyDashboardCard(store: store.privacyStore)
            .padding(16)

            Divider()

            RecentPostureTimeline(bins: store.recentPostureBins)
                .padding(16)

            Divider()

            todaySummary
                .padding(16)

            HStack {
                Text(L10n.text("姿态数据仅保存在本机"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(L10n.text("设置…")) {
                    HeadUpWindowPresenter.present(id: HeadUpWindowID.settings, using: openWindow)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.25))
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button {
                store.startCalibration()
            } label: {
                Label(L10n.text("姿态校准"), systemImage: "scope")
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.isConnected)

            Divider().frame(height: 28)

            Button {
                store.isMonitoring.toggle()
            } label: {
                Label(
                    store.isMonitoring ? L10n.text("暂停") : L10n.text("继续"),
                    systemImage: store.isMonitoring ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("今日"))
                .font(.subheadline.weight(.medium))

            HStack {
                summaryItem(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: L10n.text("良好姿势"),
                    value: store.goodPosturePercentage.map { "\($0)%" } ?? "—"
                )
                Divider().frame(height: 38)
                summaryItem(
                    icon: "bell.fill",
                    color: .orange,
                    title: L10n.text("提醒触发"),
                    value: L10n.text("{0} 次", "\(store.remindersToday)")
                )
            }
        }
    }

    private func summaryItem(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calibrationView: some View {
        VStack(spacing: 16) {
            Image(nsImage: HeadUpIconResource.image(
                named: store.calibrationStage == .upright ? "menu-good" : "menu-caution",
                pointHeight: 38
            ))
                .renderingMode(.template)
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
            VStack(spacing: 5) {
                Text(store.calibrationStage.instruction).font(.headline)
                Text(store.calibrationStage == .upright ? L10n.text("保持 2 秒，不要移动") : L10n.text("像平时看键盘那样低头"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: store.calibrationProgress)
                .frame(width: 240)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text(L10n.text("需要运动与健身权限")).font(.headline)
            HStack {
                Button(L10n.text("打开系统设置")) { store.openMotionPrivacySettings() }
                Button(L10n.text("重新检测")) { store.retryMotionAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var statusHeadline: String {
        switch store.status {
        case .warning: return L10n.text("下巴轻轻抬一点")
        case .caution: return L10n.text("检测到低头")
        case .good: return L10n.text("姿势良好")
        default: return store.status.title
        }
    }

    private var statusDetail: String {
        switch store.status {
        case .warning:
            return L10n.text("已持续 {0}", "\(HeadUpFormatters.duration(store.sustainedDuration))")
        case .caution:
            let remaining = max(0, store.settings.reminderDelay - store.sustainedDuration)
            return L10n.text("再持续 {0} 秒将提醒", "\(Int(remaining.rounded(.up)))")
        case .good:
            return L10n.text("保持得不错，肩膀也放松一点")
        case .paused:
            return L10n.text("继续后恢复姿态记录")
        case .moving:
            return L10n.text("行走或跑步时会自动暂停姿态提醒")
        case .disconnected:
            return L10n.text("戴上并连接支持头部追踪的 AirPods")
        case .unavailable:
            return L10n.text("AirPods 仍已连接；正在等待头部运动数据恢复")
        case .needsCalibration:
            return store.calibrationError ?? L10n.text("完成校准后开始监测")
        default:
            return L10n.text("完成校准后开始监测")
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .warning, .caution: return .orange
        case .good: return .green
        case .moving: return .blue
        default: return .secondary
        }
    }

}

private struct ScreenPrivacyDashboardCard: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var store: ScreenPrivacyStore
    @ObservedObject var settings: ScreenPrivacySettings

    init(store: ScreenPrivacyStore) {
        self.store = store
        settings = store.settings
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 38, height: 38)
                .background(iconColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(store.status.title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Button(actionTitle) { performAction() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                if store.status != .disabled && store.status != .needsCalibration {
                    Button(L10n.text("校准屏幕")) { store.startCalibration() }
                        .buttonStyle(.plain).font(.caption2)
                }
            }
        }
    }

    private var iconName: String {
        switch store.status {
        case .watching: return "checkmark.shield.fill"
        case .covered, .revealingSoon: return "eye.slash.fill"
        case .trackingLost: return "exclamationmark.shield.fill"
        default: return "shield"
        }
    }

    private var iconColor: Color {
        switch store.status {
        case .watching: return .green
        case .covered, .trackingLost, .coveringSoon: return .orange
        default: return .secondary
        }
    }

    private var detail: String {
        switch store.status {
        case .watching:
            return L10n.text("水平 {0}° · 垂直 {1}°", "\(signed(store.horizontalOffset))", "\(signed(store.verticalOffset))")
        default:
            return store.statusDetail
        }
    }

    private var actionTitle: String {
        switch store.status {
        case .disabled, .needsCalibration: return L10n.text("校准屏幕")
        case .paused: return L10n.text("继续")
        default: return L10n.text("暂停")
        }
    }

    private func performAction() {
        switch store.status {
        case .disabled, .needsCalibration:
            store.startCalibration()
        default:
            store.togglePause()
        }
    }

    private func signed(_ value: Double) -> String {
        value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(0)))
    }
}
