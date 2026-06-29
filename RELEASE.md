# HeadUp Releases

## HeadUp 0.2.3 [2026-06-29]

### Fixes

- Fixed startup connection detection when compatible AirPods are already connected before HeadUp starts.

## HeadUp 0.2.2 [2026-06-27]

This release fixes the packaged app startup failure seen when moving the app to another Mac.

### Fixes

- Fixed a release packaging issue where the Swift Package Manager resource bundle was not copied into `HeadUp.app`.
- The packaged app now includes `HeadUp_HeadUp.bundle` under `Contents/Resources`, allowing `Bundle.module` resources to load correctly at runtime.
- Fixed the symptom where Finder launch appeared to do nothing because the app crashed early with `Fatal error: unable to find bundle named HeadUp_HeadUp`.

### Packaging

- Updated `script/package_release.sh` to copy the generated SwiftPM resource bundle into the release app bundle.
- Updated `script/build_and_run.sh` to use the same resource bundle layout as release builds.
- Improved release build preflight messaging for missing Xcode build tools.

### Verification

- `bash -n script/package_release.sh`
- `bash -n script/build_and_run.sh`
- Confirmed the generated release resource bundle exists at `.build/apple/Products/Release/HeadUp_HeadUp.bundle`.

## HeadUp 0.1.0

- AirPods head-motion posture monitoring and two-stage calibration.
- Sustained low-head reminders with local notification and HUD fallback.
- Recent 60-minute posture timeline and persistent daily summaries.
- Walking/running suppression using headphone activity data on macOS 15+.
- Menu bar dashboard, settings window, launch-at-login option, and local-only storage.
- First-launch guide, permission retry, version information, update link, and support entry points.
- Applications-folder guidance, privacy-safe diagnostic copy, and archived dSYM symbols for release support.
- Fixed a false connected state when Core Motion was listening without an AirPods connection, and cancel calibration immediately on disconnect.
