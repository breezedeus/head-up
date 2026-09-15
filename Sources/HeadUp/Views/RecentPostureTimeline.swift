import SwiftUI

struct RecentPostureTimeline: View {
    @ObservedObject private var localization = AppLocalization.shared
    let bins: [PostureBinState]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.text("最近 60 分钟"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: 10) {
                    legend(color: .green, text: L10n.text("良好"))
                    legend(color: .orange, text: L10n.text("低头"))
                }
            }

            HStack(spacing: 3) {
                ForEach(Array(bins.enumerated()), id: \.offset) { _, state in
                    Capsule(style: .continuous)
                        .fill(color(for: state))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("最近 60 分钟姿态时间线"))

            HStack {
                Text(L10n.text("60 分钟前"))
                Spacer()
                Text(L10n.text("30 分钟前"))
                Spacer()
                Text(L10n.text("现在"))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func color(for state: PostureBinState) -> Color {
        switch state {
        case .empty: return Color.secondary.opacity(0.14)
        case .good: return .green
        case .warning: return .orange
        }
    }
}
