import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: PostureStore

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
                Text("抬头")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    HeadUpWindowPresenter.present(id: HeadUpWindowID.settings, using: openWindow)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("设置")

                Menu {
                    Button("测试提醒") { store.testReminder() }
                    Button("使用指南") {
                        HeadUpWindowPresenter.present(id: HeadUpWindowID.guide, using: openWindow)
                    }
                    Button("查看更新") { NSWorkspace.shared.open(HeadUpLinks.releases) }
                    Divider()
                    Button("退出抬头") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
        if store.calibrationStage != .idle {
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
                    Label(statusHeadline, systemImage: statusSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(statusColor)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("提醒阈值 \(Int(store.settings.threshold))°")
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

            RecentPostureTimeline(bins: store.recentPostureBins)
                .padding(16)

            Divider()

            todaySummary
                .padding(16)

            HStack {
                Text("姿态数据仅保存在本机")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("设置…") {
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
                Label("重新校准", systemImage: "scope")
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
                    store.isMonitoring ? "暂停" : "继续",
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
            Text("今日")
                .font(.subheadline.weight(.medium))

            HStack {
                summaryItem(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "良好姿势",
                    value: store.goodPosturePercentage.map { "\($0)%" } ?? "—"
                )
                Divider().frame(height: 38)
                summaryItem(
                    icon: "bell.fill",
                    color: .orange,
                    title: "提醒触发",
                    value: "\(store.remindersToday) 次"
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
            Image(systemName: store.calibrationStage == .upright ? "person.fill.checkmark" : "person.fill.turn.down")
                .font(.system(size: 38))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
            VStack(spacing: 5) {
                Text(store.calibrationStage.instruction).font(.headline)
                Text(store.calibrationStage == .upright ? "保持 2 秒，不要移动" : "像平时看键盘那样低头")
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
            Text("需要运动与健身权限").font(.headline)
            HStack {
                Button("打开系统设置") { store.openMotionPrivacySettings() }
                Button("重新检测") { store.retryMotionAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var statusHeadline: String {
        switch store.status {
        case .warning: return "下巴轻轻抬一点"
        case .caution: return "检测到低头"
        case .good: return "姿势良好"
        default: return store.status.title
        }
    }

    private var statusDetail: String {
        switch store.status {
        case .warning:
            return "已持续 \(HeadUpFormatters.duration(store.sustainedDuration))"
        case .caution:
            let remaining = max(0, store.settings.reminderDelay - store.sustainedDuration)
            return "再持续 \(Int(remaining.rounded(.up))) 秒将提醒"
        case .good:
            return "保持得不错，肩膀也放松一点"
        case .paused:
            return "继续后恢复姿态记录"
        case .moving:
            return "行走或跑步时会自动暂停姿态提醒"
        case .disconnected:
            return "戴上并连接支持头部追踪的 AirPods"
        case .needsCalibration:
            return store.calibrationError ?? "完成校准后开始监测"
        default:
            return "完成校准后开始监测"
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

    private var statusSymbol: String {
        switch store.status {
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "arrow.down.forward.circle.fill"
        case .good: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .moving: return "figure.walk.circle.fill"
        default: return "info.circle.fill"
        }
    }
}
