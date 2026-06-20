# 抬头 HeadUp

一个使用 AirPods 头部运动数据提醒你避免长时间低头的原生 macOS 菜单栏 App。

## 系统要求

- macOS 14 或更高版本
- 支持头部追踪的 AirPods，并已连接到 Mac
- 首次运行时允许“运动与健身”及通知权限

## 运行

在 Codex 中点击项目的 **Run**，或者执行：

```bash
./script/build_and_run.sh
```

构建产物位于 `dist/HeadUp.app`。首次使用请点击菜单栏图标，戴好 AirPods 后进行校准：

Run 脚本会对本地 bundle 做 ad-hoc 签名（等同于 Xcode 的 **Sign to Run Locally**），以确保运动权限和本地通知能识别稳定的 App 身份。

1. 坐直并平视屏幕 2 秒。
2. 按日常看键盘的幅度自然低头 2 秒。
3. App 会自动学习低头方向，之后在持续超过阈值时提醒。

## 开发验证

```bash
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --telemetry
```

遥测只记录启动、AirPods 连接、校准阶段和提醒事件，不记录连续角度数据。

如果系统通知被关闭，设置页会显示入口，App 会改用置顶 HUD 和系统提示音提醒。设置页的“测试提醒”可以随时验证提醒链路。

设置窗口是按需打开的单例窗口。菜单栏的“设置…”会激活 App、将窗口移动到当前 Space 并置于最前方。

## 能力边界

AirPods 只能提供头部姿态。App 可以判断持续低头，但无法仅凭 AirPods 判断含胸、弯腰、肩膀位置或坐姿/站姿，也不属于医疗设备。
