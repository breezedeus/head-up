import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PostureStore

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem { Label("通用", systemImage: "gearshape") }
            PostureSettingsView(store: store)
                .tabItem { Label("姿态提醒", systemImage: "figure.stand") }
            ScreenPrivacySettingsView(store: store.privacyStore, isConnected: store.isConnected)
                .tabItem { Label("屏幕保护", systemImage: "eye.slash") }
            PrivacyContentSettingsView(store: store.privacyStore)
                .tabItem { Label("遮挡内容", systemImage: "clock") }
        }
        .frame(width: 570, height: 540)
        .scenePadding()
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: PostureStore
    @State private var confirmsDataReset = false
    @State private var diagnosticsCopied = false

    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                if let error = store.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if !HeadUpAppInfo.isInstalledInApplications {
                    Label("建议先将抬头移到“应用程序”文件夹，登录启动会更稳定", systemImage: "folder.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section("数据") {
                Button("清除姿态历史…", role: .destructive) { confirmsDataReset = true }
            }
            Section("关于") {
                LabeledContent("版本", value: HeadUpAppInfo.versionDescription)
                Button("使用指南") { HeadUpWindowPresenter.present(id: HeadUpWindowID.guide, using: openWindow) }
                Link("隐私说明", destination: HeadUpLinks.privacy)
                Link("反馈问题", destination: HeadUpLinks.issues)
                Link("查看更新", destination: HeadUpLinks.releases)
                Button(diagnosticsCopied ? "诊断信息已复制" : "复制诊断信息") {
                    store.copyDiagnosticInfo()
                    diagnosticsCopied = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("清除姿态历史？", isPresented: $confirmsDataReset) {
            Button("清除", role: .destructive) { store.clearPostureHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除今日统计和最近 60 分钟时间线，校准与提醒设置会保留。")
        }
    }
}

private struct PostureSettingsView: View {
    @ObservedObject var store: PostureStore
    @ObservedObject var settings: AppSettings

    init(store: PostureStore) {
        self.store = store
        settings = store.settings
    }

    var body: some View {
        Form {
            Section("姿势判断") {
                angleSlider("低头阈值", value: $settings.threshold, range: 8...30)
                LabeledContent("持续多久后提醒") {
                    Picker("", selection: $settings.reminderDelay) {
                        Text("10 秒").tag(10.0); Text("20 秒").tag(20.0)
                        Text("30 秒").tag(30.0); Text("60 秒").tag(60.0)
                    }.labelsHidden().frame(width: 110)
                }
                LabeledContent("提醒冷却时间") {
                    Picker("", selection: $settings.cooldown) {
                        Text("1 分钟").tag(60.0); Text("3 分钟").tag(180.0)
                        Text("5 分钟").tag(300.0); Text("10 分钟").tag(600.0)
                    }.labelsHidden().frame(width: 110)
                }
            }
            Section("通知") {
                Toggle("声音提醒", isOn: $settings.audibleRemindersEnabled)
                Toggle("同时发送系统通知", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { enabled in
                        settings.notificationsEnabled = enabled
                        if enabled { store.refreshNotificationAuthorization() }
                    }
                ))
                if store.notificationsAllowed == false {
                    LabeledContent {
                        Button("打开通知设置") { store.openNotificationSettings() }
                    } label: {
                        Label("系统通知已关闭，将改用提示音", systemImage: "bell.slash.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Button("测试提醒") { store.testReminder() }
            }
            Section {
                Text("姿态提醒只根据 AirPods 的头部方向判断低头程度，不是医疗设备。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func angleSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 1).frame(width: 220)
                Text("\(Int(value.wrappedValue))°").monospacedDigit().frame(width: 36, alignment: .trailing)
            }
        }
    }
}

private struct ScreenPrivacySettingsView: View {
    @ObservedObject var store: ScreenPrivacyStore
    @ObservedObject var settings: ScreenPrivacySettings
    let isConnected: Bool

    init(store: ScreenPrivacyStore, isConnected: Bool) {
        self.store = store
        settings = store.settings
        self.isConnected = isConnected
    }

    var body: some View {
        Form {
            Section {
                Toggle("转开视线时保护屏幕", isOn: Binding(
                    get: { settings.isEnabled },
                    set: { store.setEnabled($0) }
                ))
                HStack(spacing: 10) {
                    Image(systemName: statusSymbol).foregroundStyle(statusColor).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.status.title).font(.subheadline.weight(.medium))
                        Text(store.statusDetail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.status == .paused { Button("继续") { store.togglePause() } }
                }
            }
            Section("工作区校准") {
                if store.calibrationStage == .idle {
                    LabeledContent("当前头部偏移") {
                        Text("水平 \(signed(store.horizontalOffset))°  ·  垂直 \(signed(store.verticalOffset))°")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Button(settings.isEnabled ? "重新校准五个方向…" : "校准并开启…") {
                        store.startCalibration()
                    }
                    .disabled(!isConnected)
                    if !isConnected {
                        Text("请先连接支持头部追踪的 AirPods").font(.caption).foregroundStyle(.orange)
                    }
                    if let error = store.calibrationError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } else {
                    CalibrationStepView(store: store)
                }
            }
            Section("允许角度") {
                angleSlider("向左", value: $settings.leftAngle, range: 5...85)
                angleSlider("向右", value: $settings.rightAngle, range: 5...85)
                angleSlider("向上", value: $settings.upAngle, range: 5...60)
                angleSlider("向下", value: $settings.downAngle, range: 5...60)
                Text("任一方向越过边界都会触发保护。向下边界可留大一些，避免看键盘时误触。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("响应") {
                delayPicker("转开后遮挡", selection: $settings.hideDelay, values: [0.3, 0.5, 0.8, 1.2, 2])
                delayPicker("回正后恢复", selection: $settings.revealDelay, values: [0.1, 0.3, 0.5, 0.8, 1.2])
                Toggle("追踪中断时保持遮挡", isOn: $settings.keepCoveredOnTrackingLoss)
            }
        }
        .formStyle(.grouped)
    }

    private var statusSymbol: String {
        switch store.status {
        case .watching: return "checkmark.shield.fill"
        case .covered, .revealingSoon: return "eye.slash.fill"
        case .trackingLost: return "airpodspro.chargingcase.wireless"
        case .calibrating: return "scope"
        default: return "shield"
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .watching: return .green
        case .covered, .coveringSoon, .trackingLost: return .orange
        case .calibrating: return .blue
        default: return .secondary
        }
    }

    private func angleSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 1).frame(width: 220)
                Text("\(Int(value.wrappedValue))°").monospacedDigit().frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func delayPicker(_ title: String, selection: Binding<Double>, values: [Double]) -> some View {
        LabeledContent(title) {
            Picker("", selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(value < 1 ? "\(Int(value * 1000)) 毫秒" : "\(value.formatted()) 秒").tag(value)
                }
            }.labelsHidden().frame(width: 120)
        }
    }

    private func signed(_ value: Double) -> String {
        value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(0)))
    }
}

private struct CalibrationStepView: View {
    @ObservedObject var store: ScreenPrivacyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle().fill(.blue.opacity(0.14)).frame(width: 42, height: 42)
                    Image(systemName: stageSymbol).foregroundStyle(.blue).font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(store.calibrationStage.sequenceNumber) / 5 步")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(store.calibrationStage.title).font(.headline)
                }
                Spacer()
                Button("取消") { store.cancelCalibration() }
            }
            Text("保持自然工作姿势约 1 秒，不需要转到颈部极限。")
                .font(.caption).foregroundStyle(.secondary)
            if store.isCapturingCalibration {
                ProgressView(value: store.calibrationProgress)
            } else {
                Button("采集这个方向") { store.beginCalibrationCapture() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private var stageSymbol: String {
        switch store.calibrationStage {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        default: return "display"
        }
    }
}

private struct PrivacyContentSettingsView: View {
    @ObservedObject var store: ScreenPrivacyStore
    @ObservedObject var settings: ScreenPrivacySettings
    @ObservedObject var overlayContent: PrivacyOverlayContentModel

    init(store: ScreenPrivacyStore) {
        self.store = store
        settings = store.settings
        overlayContent = store.overlayContent
    }

    var body: some View {
        Form {
            Section("背景") {
                Picker("遮挡方式", selection: $settings.backgroundStyle) {
                    ForEach(ScreenPrivacyBackgroundStyle.allCases) { style in Text(style.title).tag(style) }
                }
                if settings.backgroundStyle == .blur {
                    LabeledContent("压暗程度") {
                        Slider(value: $settings.dimOpacity, in: 0.1...0.75, step: 0.05).frame(width: 240)
                    }
                }
            }
            Section("日期与时间") {
                Toggle("显示时间", isOn: $settings.showsTime)
                Toggle("显示日期", isOn: $settings.showsDate)
                Toggle("显示秒数", isOn: $settings.showsSeconds).disabled(!settings.showsTime)
            }
            Section("天气") {
                Toggle("显示天气", isOn: $settings.showsWeather)
                TextField("城市，例如：上海", text: $settings.weatherCity).disabled(!settings.showsWeather)
                if settings.showsWeather {
                    HStack {
                        Button("更新天气") { store.refreshWeather(force: true) }
                        if let weatherText = overlayContent.weatherText {
                            Text(weatherText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("天气由 Open-Meteo 提供；开启后只会发送所填城市用于查询天气。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("自定义文字") {
                Toggle("显示自定义文字", isOn: $settings.showsCustomText)
                TextField("例如：请联系我后再查看屏幕", text: $settings.customText, axis: .vertical)
                    .lineLimit(2...4).disabled(!settings.showsCustomText)
            }
            Section("显示位置") {
                Toggle("在所有屏幕显示信息", isOn: $settings.infoOnAllDisplays)
                Text("关闭时，其他屏幕仍会遮挡，只在主屏显示时间等内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(store.isPreviewing ? "退出全屏预览" : "全屏预览遮挡效果") {
                    store.isPreviewing ? store.stopPreviewOrOverlay() : store.showPreview()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
    }
}
