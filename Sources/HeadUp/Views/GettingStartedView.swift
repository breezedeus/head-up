import AppKit
import SwiftUI

struct GettingStartedView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    private let primaryAction: (() -> Void)?

    init(primaryAction: (() -> Void)? = nil) {
        self.primaryAction = primaryAction
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 82, height: 82)
                    .accessibilityHidden(true)
                Text("欢迎使用抬头")
                    .font(.largeTitle.weight(.semibold))
                Text("用 AirPods 提醒持续低头，也能在你转开时保护屏幕。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                step("1", title: "安装并连接", detail: "先将抬头移入“应用程序”，再戴上支持头部追踪的 AirPods。")
                step("2", title: "完成两步校准", detail: "先坐直平视，再像平时看键盘一样自然低头。")
                step("3", title: "按需开启屏幕保护", detail: "在设置中校准左右、仰头和低头边界；转出工作区后会遮挡所有屏幕。")
            }

            Label("姿态数据只在本机处理和保存", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Link("隐私说明", destination: HeadUpLinks.privacy)
                Spacer()
                Button("开始使用") {
                    if let primaryAction {
                        primaryAction()
                    } else {
                        dismissWindow(id: HeadUpWindowID.guide)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 540, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Text(number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.blue, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
