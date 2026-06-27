# Releasing HeadUp

HeadUp supports direct distribution with a Developer ID Application certificate and Apple notarization.

## Prerequisites

1. Install the full Xcode app and select it:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```

2. Install a valid **Developer ID Application** certificate in the login keychain.
3. Store notary credentials once:

   ```bash
   xcrun notarytool store-credentials headup-notary \
     --apple-id "APPLE_ID" \
     --team-id "TEAM_ID" \
     --password "APP_SPECIFIC_PASSWORD"
   ```

## Build, sign, notarize, and package

```bash
HEADUP_SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" \
HEADUP_NOTARY_PROFILE="headup-notary" \
./script/package_release.sh
```

The script creates a universal `arm64`/`x86_64` Release app, enables Hardened Runtime, submits it for notarization, staples the ticket, verifies Gatekeeper acceptance, and writes the final app ZIP plus a separate dSYM ZIP and SHA-256 checksums under `dist/release/`. Keep the dSYM private if the GitHub release itself is public; it is needed to symbolicate crash reports but users do not need to download it.

## GitHub release automation

The release workflow runs for tags matching `v*`. Configure these repository secrets:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_APPLICATION_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `KEYCHAIN_PASSWORD`

Update `VERSION`, update `CHANGELOG.md`, merge to `main`, and push a matching tag such as `v0.1.0`.
