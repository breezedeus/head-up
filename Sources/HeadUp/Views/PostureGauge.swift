import SwiftUI

private struct GaugeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        return path
    }
}

struct PostureGauge: View {
    let angle: Double
    let status: PostureStatus
    let duration: TimeInterval
    let threshold: Double

    private var progress: Double { min(max(angle / 30, 0), 1) }
    private var safeProgress: Double { min(max(threshold / 30, 0), 1) }

    private var accent: Color {
        switch status {
        case .warning, .caution: return .orange
        case .paused, .disconnected, .unavailable: return .secondary
        default: return .green
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GaugeArc()
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 10, lineCap: .round))

            GaugeArc()
                .trim(from: 0, to: safeProgress)
                .stroke(.green.opacity(0.28), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            GaugeArc()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .animation(.smooth(duration: 0.25), value: progress)

            VStack(spacing: 0) {
                Text("\(Int(angle.rounded()))°")
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("低头角度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 1)
        }
        .frame(width: 176, height: 108)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("低头角度 \(Int(angle.rounded())) 度，阈值 \(Int(threshold)) 度")
    }
}
