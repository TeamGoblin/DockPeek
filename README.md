# DockPeek

Window previews for the macOS Dock — a native replacement for HyperDock.
Menu bar app (no Dock icon), macOS 14+, Apple Silicon and Intel.

## Develop

The app ID is `com.teamgoblin.dockpeek`. To build under a different ID locally, copy
`local.env.example` to `local.env` (git-ignored) and set `DOCKPEEK_BUNDLE_ID`.

```sh
./build.sh --install     # build, sign (Apple Development), install to /Applications, relaunch
```

## Release a shareable installer

One-time setup:

1. **Developer ID certificate** — Xcode → Settings → Accounts → select your team →
   Manage Certificates… → **+** → *Developer ID Application*.
   (Only the team's Account Holder can create this.)
2. **Notary credentials** — create an app-specific password at https://account.apple.com
   (Sign-In and Security → App-Specific Passwords), then:
   ```sh
   xcrun notarytool store-credentials dockpeek --apple-id <your Apple ID> --team-id <TEAM ID>
   ```
   It prompts for the app-specific password and stores it in your keychain.

Each release:

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`.
2. `scripts/dist.sh` → produces `dist/DockPeek-<version>.dmg`, signed, notarized and stapled.

Users open the DMG and drag DockPeek into Applications, then grant Accessibility and
Screen Recording on first launch.
