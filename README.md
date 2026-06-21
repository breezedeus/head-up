# 抬头 HeadUp

[简体中文](README.md) · [English](README.en.md)

一个使用 AirPods 头部运动数据提醒你避免长时间低头的原生 macOS 菜单栏 App。

当前面板包含实时低头角度、提醒倒计时、最近 60 分钟姿态时间线，以及按日期持久化的今日良好率和提醒触发次数。所有姿态数据仅保存在本机。

## 系统要求

- macOS 14 或更高版本
- 支持头部追踪的 AirPods，并已连接到 Mac
- 首次使用监测时允许“运动与健身”权限；系统通知为可选项

## 安装发行版

项目目前尚未提供经过 Developer ID 签名和 Apple 公证的公开发行包。开发测试请从源码构建；未来的正式版本会发布到 [GitHub Releases](https://github.com/breezedeus/head-up/releases)，并提供对应的 `.sha256` 校验文件。

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

首次启动会显示简短的使用指南；之后可从菜单栏面板右上角的菜单再次打开。问题排查与反馈方式见 [SUPPORT.md](SUPPORT.md)。

## 开发验证

```bash
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --telemetry
```

遥测只记录启动、AirPods 连接、校准阶段和提醒事件，不记录连续角度数据。

## 发布

发布流水线已支持通用 Release 二进制、Developer ID、Hardened Runtime 和 Apple 公证，但在配置开发者证书前不会发布正式安装包。完整步骤见 [RELEASING.md](RELEASING.md)，隐私说明见 [PRIVACY.md](PRIVACY.md)。

如果系统通知被关闭，设置页会显示入口，App 会改用置顶 HUD 和系统提示音提醒。设置页的“测试提醒”可以随时验证提醒链路。

设置窗口是按需打开的单例窗口。菜单栏的“设置…”会激活 App、将窗口移动到当前 Space 并置于最前方。

## 能力边界

AirPods 只能提供头部姿态。App 可以判断持续低头，但无法仅凭 AirPods 判断含胸、弯腰、肩膀位置或坐姿/站姿，也不属于医疗设备。
