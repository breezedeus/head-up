import AppKit
import SwiftUI

struct PrivacyOverlayView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var settings: ScreenPrivacySettings
    @ObservedObject var content: PrivacyOverlayContentModel
    let displaysInformation: Bool
    let onPause: () -> Void
    /// Present only on displays that can act as a recenter reference.
    var onRecenter: (() -> Void)?

    /// The target has to sit on the true center of the screen, since tapping it means
    /// "I am facing the center of this display". Everything else yields that band to it.
    private var reservesCenter: Bool { onRecenter != nil }

    private enum Target {
        static let buttonWidth: CGFloat = 168
        static let buttonHeight: CGFloat = 104
        static let captionWidth: CGFloat = 320
        /// Fixed so the block's height is known here rather than measured, which is what
        /// lets the readout above it be placed without guessing. Two caption lines.
        static let captionHeight: CGFloat = 34
        static let spacing: CGFloat = 12
        /// The caption is mirrored above the button (hidden), so the block is symmetric
        /// about the button and half its height reaches from the screen center.
        static var halfHeight: CGFloat { buttonHeight / 2 + spacing + captionHeight }
        /// Breathing room between the block and whatever sits above it.
        static let clearance: CGFloat = 28
    }

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

            // In its own centered layer rather than in the content stack: tapping it
            // supplies the calibration pose, so it has to sit at the true center of the
            // screen for the pose to mean "facing this display's center".
            if let onRecenter {
                recenterTarget(action: onRecenter)
            }
        }
        .ignoresSafeArea()
    }

    private func recenterTarget(action: @escaping () -> Void) -> some View {
        // The caption is mirrored above the button, hidden, so the button itself lands on
        // the exact center of the screen. Letting the caption sit only below would push
        // the button up by half its height, and that bias would tilt every boundary the
        // recenter derives from the tap — unlike head jitter, it would not average out.
        VStack(spacing: Target.spacing) {
            recenterCaption.hidden()
            Button(action: action) {
                VStack(spacing: 8) {
                    Image(systemName: "scope").font(.system(size: 34, weight: .light))
                    Text(L10n.text("对准这里")).font(.callout.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: Target.buttonWidth, height: Target.buttonHeight)
                .background(Color.accentColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                )
            }
            // Drawn rather than `.borderedProminent`: the overlay panel is usually not the
            // key window, and a prominent button renders desaturated in that state, which
            // made the one action on this screen look disabled.
            .buttonStyle(.plain)
            recenterCaption
        }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
    }

    private var recenterCaption: some View {
        Text(L10n.text("正视这个按钮并点按，即可用已保存的校准恢复保护"))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .frame(width: Target.captionWidth, height: Target.captionHeight)
    }

    private func contentView(date: Date) -> some View {
        GeometryReader { geo in
            VStack(spacing: 18) {
                if reservesCenter {
                    // Centered in the space the target leaves free above itself, rather
                    // than pinned to the top: keeps the readout off the target's band on
                    // a short screen without stranding it against the top edge on a tall
                    // one. The padding is symmetric, so the screen center is also the
                    // center of this reader's box.
                    FittedVertically(
                        limit: max(0, geo.size.height / 2 - Target.halfHeight - Target.clearance)
                    ) {
                        readout(date: date)
                    }
                    Spacer(minLength: 0)
                } else {
                    Spacer()
                    readout(date: date)
                    Spacer()
                }

                Button(L10n.text("暂停屏幕保护")) {
                    onPause()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.escape, modifiers: [])

                Text(L10n.text("按 Esc 也可以恢复屏幕"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(40)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }

    @ViewBuilder
    private func readout(date: Date) -> some View {
        VStack(spacing: 18) {
            if settings.showsTime {
                Text(date.formatted(settings.showsSeconds
                     ? .dateTime.hour().minute().second().locale(localization.locale)
                     : .dateTime.hour().minute().locale(localization.locale)))
                    .font(.system(size: 76, weight: .light, design: .rounded))
                    .monospacedDigit()
            }

            if settings.showsDate {
                Text(date.formatted(.dateTime.year().month(.wide).day().weekday(.wide).locale(localization.locale)))
                    .font(.title2.weight(.medium))
            }

            if settings.showsWeather {
                Label(content.weatherText ?? L10n.text("天气暂不可用"), systemImage: content.weatherSymbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if settings.showsCustomText, !settings.customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(settings.customText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineLimit(reservesCenter ? 2 : 5)
                    .frame(maxWidth: 620)
                    .padding(.top, 8)
            }

            if let message = content.message {
                Label(L10n.text(message), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }
        }
    }
}

private struct NaturalHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Shrinks its content to fit `limit`, and only then.
///
/// `frame(maxHeight:)` alone is not enough: it bounds the layout box while the content
/// keeps its natural height and spills out of both ends, which on a short screen pushed
/// the clock off the top of the overlay. Measuring first means the content adapts to
/// whatever the user has switched on instead of relying on per-screen font sizes.
private struct FittedVertically<Content: View>: View {
    let limit: CGFloat
    @ViewBuilder var content: Content
    @State private var naturalHeight: CGFloat = 0

    private var scale: CGFloat {
        guard limit > 0, naturalHeight > limit else { return 1 }
        return limit / naturalHeight
    }

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: NaturalHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(NaturalHeightKey.self) { naturalHeight = $0 }
            // Visual only, so the measurement above stays the natural height and cannot
            // feed back into itself.
            .scaleEffect(scale)
            .frame(maxWidth: .infinity, maxHeight: limit)
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
