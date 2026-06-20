import AppKit
import SwiftUI

@MainActor
final class ReminderHUDController {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(angle: Double) {
        let panel = panel ?? makePanel()
        let content = ReminderHUDView(angle: angle)
        panel.contentView = NSHostingView(rootView: content)
        position(panel)

        dismissWorkItem?.cancel()
        panel.orderFrontRegardless()
        HeadUpLog.reminders.notice("Fallback reminder HUD presented")

        let workItem = DispatchWorkItem { [weak panel] in
            panel?.orderOut(nil)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 104),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 48
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct ReminderHUDView: View {
    let angle: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.fill.turn.down")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(.orange.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("抬头一下")
                    .font(.title3.weight(.semibold))
                Text("已持续低头 · 当前约 \(Int(angle.rounded()))°")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("下巴轻轻抬一点，肩膀放松")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 340, height: 104)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}
