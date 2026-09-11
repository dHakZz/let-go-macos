# Distributing Let Go

Polished production builds should be signed with a **Developer ID Application** certificate, use the Hardened Runtime, and be notarized by Apple before wide promotion. Early GitHub feedback builds may be ad-hoc signed when their release notes and download instructions clearly disclose that macOS will show a Gatekeeper warning.

Apple's current guidance:

- [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## One-time setup

1. Join the Apple Developer Program and add the Apple ID to Xcode.
2. In **Xcode → Settings → Accounts → Manage Certificates**, create or download a **Developer ID Application** certificate.
3. Create an app-specific password for the Apple ID used for notarization.
4. Save the notarization credentials in the login keychain. Do not put credentials in this repository:

```sh
xcrun notarytool store-credentials "let-go-notary" \
  --apple-id "YOUR-APPLE-ID" \
  --team-id "YOUR-TEAM-ID" \
  --password "YOUR-APP-SPECIFIC-PASSWORD"
```

## Build a signed and notarized release

First confirm the exact certificate name:

```sh
security find-identity -v -p codesigning
```

Then run:

```sh
LETGO_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
LETGO_NOTARY_PROFILE="let-go-notary" \
LETGO_SUPPORT_URL="https://your-optional-support-page.example" \
zsh Scripts/build-app.sh
```

Omit `LETGO_SUPPORT_URL` if the app should not show a support link. Supporting the app is always optional and does not change which features are available.

The script:

1. Builds a universal Apple silicon and Intel app.
2. Signs it with the Hardened Runtime and a secure timestamp.
3. Verifies the code signature.
4. Submits the ZIP with `notarytool` and waits for Apple's result.
5. Staples and validates the notarization ticket.
6. Checks the final app with Gatekeeper.

The final files are written to:

- `outputs/Let Go.app`
- `outputs/Let-Go-macOS.zip`

## Development build

Running `zsh Scripts/build-app.sh` without credentials creates an ad-hoc signed local build. That is useful for testing, but it should not be promoted as the public download.
