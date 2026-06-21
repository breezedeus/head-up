# HeadUp

[简体中文](README.md) · [English](README.en.md)

HeadUp is a native macOS menu bar app that uses motion data from compatible AirPods to help you avoid keeping your head lowered for too long.

The dashboard shows your current downward head angle, reminder countdown, posture history for the last 60 minutes, daily good-posture percentage, and reminder count. All posture processing and storage stay on your Mac.

## Requirements

- macOS 14 or later
- AirPods that support head tracking and are connected to the Mac
- Motion & Fitness permission when monitoring is first enabled; system notifications are optional

## Releases

The project does not currently provide a publicly distributed build signed with Developer ID and notarized by Apple. For development and testing, build the app from source. Future signed releases will be published on [GitHub Releases](https://github.com/breezedeus/head-up/releases) together with SHA-256 checksum files.

## Build and run

Use the **Run** action in Codex, or run:

```bash
./script/build_and_run.sh
```

The development app is created at `dist/HeadUp.app`. The script applies an ad-hoc signature, similar to Xcode's **Sign to Run Locally**, so macOS can associate Motion & Fitness permission and local notifications with a stable app identity.

On first launch, HeadUp presents a short setup guide. Connect and wear your AirPods, then calibrate from the menu bar panel:

1. Sit upright and look straight at the screen for two seconds.
2. Lower your head naturally, as you would when looking at the keyboard, for two seconds.
3. HeadUp learns your downward direction and starts monitoring sustained low-head posture.

You can reopen the guide from the menu in the top-right corner of the dashboard. See [SUPPORT.md](SUPPORT.md) for troubleshooting and issue-reporting guidance.

## Features

- Calibrated low-head detection using AirPods head-motion data
- Configurable angle threshold, reminder delay, and cooldown
- Floating reminder HUD with an optional system notification
- Automatic reminder suppression while walking or running on macOS 15 or later
- Recent 60-minute posture timeline and persistent daily summaries
- Launch-at-login option and privacy-safe diagnostic information for support
- Connection liveness checks that avoid reporting AirPods as connected without real connection evidence

## Development checks

```bash
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --telemetry
```

Telemetry records lifecycle events, verified AirPods connection changes, calibration stages, and reminders. It does not log a continuous stream of head-angle values.

## Distribution

The release pipeline supports a universal `arm64`/`x86_64` build, Hardened Runtime, Developer ID signing, Apple notarization, SHA-256 checksums, and archived dSYM files. It will not publish an official installer until Developer ID credentials are configured. See [RELEASING.md](RELEASING.md) for the release process and [PRIVACY.md](PRIVACY.md) for data-handling details.

## Privacy and limitations

HeadUp processes posture data locally and does not include analytics, advertising, accounts, or cloud synchronization.

AirPods provide head-motion information, not full-body posture. HeadUp can detect sustained downward head posture, but AirPods alone cannot determine whether you are sitting or standing or measure your spine, shoulders, hips, or back support. HeadUp is a wellness utility, not a medical device. See [AirPods posture-related capabilities](docs/AIRPODS_CAPABILITIES.md) for the API audit and product boundaries.
