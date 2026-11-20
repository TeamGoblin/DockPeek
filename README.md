# DockPeek

Window previews for the macOS Dock — a native replacement for HyperDock.
Menu bar app (no Dock icon), macOS 14+, Apple Silicon and Intel.

## Build and run it yourself

No paid Apple Developer account needed.

**Requirements:** macOS 14 (Sonoma) or newer, and Swift 5.10+, which comes with Xcode 15.3+ or
the Command Line Tools (`xcode-select --install`). Works on Apple Silicon and Intel.

```sh
git clone <this repo> DockPeek
cd DockPeek
./build.sh --install
```

That builds for your Mac, installs `/Applications/DockPeek.app`, and launches it. A Dock-shaped
icon appears in the menu bar. Then:

1. Grant **Accessibility** and **Screen Recording** in System Settings → Privacy & Security.
   DockPeek's Settings → Advanced shows when both are granted.
2. Quit and reopen DockPeek from the menu bar icon if macOS asks you to.
3. Hover any running app in the Dock.
4. Optional: turn on **Launch at login** in Settings → General.

**Signing:** `build.sh` uses an *Apple Development* certificate if you have one (any Apple ID
signed into Xcode gets one free). Without one it falls back to ad-hoc signing, which works, but
macOS may ask you to re-grant the two permissions after each rebuild.

**App ID:** defaults to `com.teamgoblin.dockpeek`. To build under your own, copy
`local.env.example` to `local.env` (git-ignored) and set `DOCKPEEK_BUNDLE_ID`.

**If it crashes:** open Console → Crash Reports, find the `DockPeek` entry, and attach that
report (the `.ips` file) to an issue.

## Release a shareable installer (maintainers)

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
