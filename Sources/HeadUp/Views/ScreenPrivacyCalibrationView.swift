import SwiftUI

/// Inline calibration stays in the menu popover, including display selection.
struct ScreenPrivacyCalibrationView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var store: ScreenPrivacyStore
    private let steps: [ScreenPrivacyCalibrationStage] = [.center, .left, .right, .up, .down]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label(L10n.text("屏幕保护"), systemImage: "display").font(.headline)
                Spacer()
                Text(L10n.text("正在校准")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                    ForEach(store.calibrationDisplays) { display in
                        Button {
                            store.selectCalibrationDisplay(display.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(display.name).lineLimit(1)
                                if store.completedDisplayIDs.contains(display.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(store.selectedDisplayID == display.id ? Color.primary.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isCapturingCalibration || store.captureCountdown > 0)
                    }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 6) {
                Text(instruction).font(.title3.weight(.semibold))
                Text(store.captureCountdown > 0 ? L10n.text("请转向目标位置，倒计时后保持 2 秒") : L10n.text("自然转头，准备好后开始采集"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            targetDiagram
                .frame(height: 150)
                .accessibilityLabel(L10n.text("当前采集位置：{0}", "\(shortTitle(store.calibrationStage))"))
            HStack {
                ForEach(steps, id: \.self) { step in
                    VStack(spacing: 6) {
                        Image(systemName: step.sequenceNumber < store.calibrationStage.sequenceNumber ? "checkmark.circle.fill" : (step == store.calibrationStage ? "record.circle" : "circle"))
                            .font(.title3)
                            .foregroundStyle(step.sequenceNumber <= store.calibrationStage.sequenceNumber ? Color.green : Color.secondary)
                        Text(shortTitle(step)).font(.caption)
                            .foregroundStyle(step == store.calibrationStage ? .primary : .secondary)
                    }.frame(maxWidth: .infinity)
                }
            }
            if let error = store.calibrationError {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !store.canCapture {
                Text(L10n.text("请先连接支持头部追踪的 AirPods")).font(.caption).foregroundStyle(.orange)
            }
            if store.isCapturingCalibration {
                ProgressView(value: store.calibrationProgress).tint(.green)
                Text(L10n.text("正在采集，请保持不动…")).font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Button { store.previousCalibrationStep() } label: { Image(systemName: "chevron.left") }
                        .help(L10n.text("上一步"))
                        .disabled(store.calibrationStage == .center || store.captureCountdown > 0)
                    Button {
                        store.beginCalibrationCapture()
                    } label: {
                        Text(store.captureCountdown > 0 ? L10n.text("{0} 秒后采集", "\(store.captureCountdown)") : L10n.text("开始采集 · 保持 2 秒"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(!store.canCapture || store.captureCountdown > 0)
                    Button(L10n.text("取消")) { store.cancelCalibration() }
                }.controlSize(.large)
            }
            if store.isCapturingCalibration { Button(L10n.text("取消校准")) { store.cancelCalibration() }.buttonStyle(.plain).font(.caption) }
            Text(L10n.text("3 秒准备时间 · 采集完成时声音提示")).font(.caption2).foregroundStyle(.secondary)
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("自动微调 · 每 10 秒检查"))
                    Text(L10n.text("仅使用当前屏幕内的有效样本")).foregroundStyle(.secondary)
                }
                Spacer()
            }.font(.caption2)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private var targetDiagram: some View {
        ZStack {
            Image(systemName: "display")
                .resizable().scaledToFit().fontWeight(.ultraLight).foregroundStyle(.secondary.opacity(0.5))
                .frame(width: 230, height: 150)
            ForEach(steps, id: \.self) { step in
                Image(systemName: step.sequenceNumber < store.calibrationStage.sequenceNumber ? "checkmark.circle.fill" : "circle.fill")
                    .font(.system(size: step == store.calibrationStage ? 20 : 14))
                    .foregroundStyle(step.sequenceNumber <= store.calibrationStage.sequenceNumber ? Color.green : Color.secondary)
                    .offset(x: point(step).x, y: point(step).y - 14)
            }
        }
    }
    private func point(_ step: ScreenPrivacyCalibrationStage) -> CGPoint {
        switch step {
        case .left: return CGPoint(x: -80, y: 0)
        case .right: return CGPoint(x: 80, y: 0)
        case .up: return CGPoint(x: 0, y: -43)
        case .down: return CGPoint(x: 0, y: 43)
        default: return .zero
        }
    }
    private func shortTitle(_ step: ScreenPrivacyCalibrationStage) -> String {
        switch step {
        case .center: return L10n.text("中心")
        case .left: return L10n.text("左侧")
        case .right: return L10n.text("右侧")
        case .up: return L10n.text("上沿")
        case .down: return L10n.text("下沿")
        case .idle: return ""
        }
    }
    private var instruction: String {
        switch store.calibrationStage {
        case .center: return L10n.text("正视这块屏幕的中心")
        case .left: return L10n.text("看向这块屏幕的左侧边缘")
        case .right: return L10n.text("看向这块屏幕的右侧边缘")
        case .up: return L10n.text("看向这块屏幕的上沿")
        case .down: return L10n.text("看向这块屏幕的下沿")
        case .idle: return L10n.text("屏幕校准已完成")
        }
    }
}
