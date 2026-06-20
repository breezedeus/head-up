import SwiftUI

private struct GaugeArc: Shape {
    let progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + (180 * min(max(progress, 0), 1))),
            clockwise: false
        )
        return path
    }
}

struct PostureGauge: View {
    let angle: Double
    let status: PostureStatus
    let duration: TimeInterval

    private var progress: Double { min(max(angle / 30, 0), 1) }
    private var accent: Color { status == .warning ? .orange : .green }

    var body: some View {
        ZStack(alignment: .bottom) {
            GaugeArc(progress: 1)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 14, lineCap: .round))

            GaugeArc(progress: progress)
                .stroke(
                    AngularGradient(colors: [.green, .yellow, .orange], center: .center),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )

            VStack(spacing: 4) {
                Label(status.title, systemImage: status == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(accent)

                Text("\(Int(angle.rounded()))°")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())

                Text(duration > 0 ? "已持续 \(HeadUpFormatters.duration(duration))" : "相对校准角度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)
        }
        .frame(width: 280, height: 145)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("低头角度 \(Int(angle.rounded())) 度，\(status.title)")
    }
}
