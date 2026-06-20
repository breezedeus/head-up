import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PostureStore
    @ObservedObject var settings: AppSettings

    init(store: PostureStore) {
        self.store = store
        settings = store.settings
    }

    var body: some View {
        Form {
            Section("姿势判断") {
                LabeledContent("低头阈值") {
                    HStack {
                        Slider(value: $settings.threshold, in: 8...30, step: 1)
                            .frame(width: 180)
                        Text("\(Int(settings.threshold))°")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                LabeledContent("持续多久后提醒") {
                    Picker("", selection: $settings.reminderDelay) {
                        Text("10 秒").tag(10.0)
                        Text("20 秒").tag(20.0)
                        Text("30 秒").tag(30.0)
                        Text("60 秒").tag(60.0)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                LabeledContent("提醒冷却时间") {
                    Picker("", selection: $settings.cooldown) {
                        Text("1 分钟").tag(60.0)
                        Text("3 分钟").tag(180.0)
                        Text("5 分钟").tag(300.0)
                        Text("10 分钟").tag(600.0)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            Section("通知") {
                Toggle(
                    "低头持续过久时发送系统通知",
                    isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { enabled in
                            settings.notificationsEnabled = enabled
                            if enabled { store.refreshNotificationAuthorization() }
                        }
                    )
                )

                if store.notificationsAllowed == false {
                    LabeledContent {
                        Button("打开通知设置") {
                            store.openNotificationSettings()
                        }
                    } label: {
                        Label("系统通知已关闭，将改用提示音", systemImage: "bell.slash.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Button("测试提醒") {
                    store.testReminder()
                }
            }

            Section {
                Text("抬头只根据 AirPods 的头部方向判断低头程度，不是医疗设备，也无法单独判断背部或肩膀姿势。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 310)
    }
}
