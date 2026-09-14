import AppKit
import SwiftUI

struct PrivacyOverlayView: View {
    @ObservedObject var settings: ScreenPrivacySettings
    @ObservedObject var content: PrivacyOverlayContentModel
    let displaysInformation: Bool
    let onPause: () -> Void

    var body: some View {
        ZStack {
            if settings.backgroundStyle == .blur {
                BackdropBlurView()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }

            Color.black.opacity(settings.backgroundStyle == .blur ? settings.dimOpacity : 0.72)

            if displaysInformation {
                TimelineView(.periodic(from: .now, by: settings.showsSeconds ? 1 : 30)) { context in
                    contentView(date: context.date)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func contentView(date: Date) -> some View {
        VStack(spacing: 18) {
            Spacer()

            if settings.showsTime {
                Text(date, format: settings.showsSeconds
                     ? .dateTime.hour().minute().second()
                     : .dateTime.hour().minute())
                    .font(.system(size: 76, weight: .light, design: .rounded))
                    .monospacedDigit()
            }

            if settings.showsDate {
                Text(date, format: .dateTime.year().month(.wide).day().weekday(.wide))
                    .font(.title2.weight(.medium))
            }

            if settings.showsWeather {
                Label(content.weatherText ?? "天气暂不可用", systemImage: content.weatherSymbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if settings.showsCustomText, !settings.customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(settings.customText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .frame(maxWidth: 620)
                    .padding(.top, 8)
            }

            if let message = content.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }

            Spacer()

            Button("暂停屏幕保护") {
                onPause()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.escape, modifiers: [])

            Text("按 Esc 也可以恢复屏幕")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 36)
        }
        .padding(40)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}

private struct BackdropBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .fullScreenUI
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}
