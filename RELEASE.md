# HeadUp 0.2.2 [2026-06-27]

This release fixes the packaged app startup failure seen when moving the app to another Mac.

## Fixes

- Fixed a release packaging issue where the Swift Package Manager resource bundle was not copied into `HeadUp.app`.
- The packaged app now includes `HeadUp_HeadUp.bundle` under `Contents/Resources`, allowing `Bundle.module` resources to load correctly at runtime.
- Fixed the symptom where Finder launch appeared to do nothing because the app crashed early with `Fatal error: unable to find bundle named HeadUp_HeadUp`.

## Packaging

- Updated `script/package_release.sh` to copy the generated SwiftPM resource bundle into the release app bundle.
- Updated `script/build_and_run.sh` to use the same resource bundle layout as release builds.
- Improved release build preflight messaging for missing Xcode build tools.

## Verification

- `bash -n script/package_release.sh`
- `bash -n script/build_and_run.sh`
- Confirmed the generated release resource bundle exists at `.build/apple/Products/Release/HeadUp_HeadUp.bundle`.
