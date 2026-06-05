# 🐋 Orca Mobile (Flutter)

A native Android/iOS client for the [Orca](https://github.com/stablyai/orca)
agent-fleet IDE, built from scratch in Flutter. It pairs with a running
**desktop Orca** over an **end-to-end-encrypted WebSocket** and streams your
agent terminals to a tablet or phone.

This is **not** the prebuilt React-Native companion app — it's an independent,
buildable-from-source Flutter implementation of the same wire protocol.

> **Why a companion, not a standalone IDE?** Orca's core job — orchestrating
> CLI agents (Claude Code, Codex, …) across git worktrees — runs on a desktop.
> The mobile app is a real-time remote into that desktop fleet, which is exactly
> what this client implements.

---

## What it does

- **Pair** with a desktop host by pasting its `orca://pair?code=…` link
  (Settings → Mobile on desktop Orca). The pairing offer carries the endpoint,
  device token, and the server's Curve25519 public key.
- **End-to-end encryption** identical to desktop: ephemeral X25519 ECDH +
  XSalsa20-Poly1305 (NaCl `box`). Handshake:
  `e2ee_hello → e2ee_ready → e2ee_auth → e2ee_authenticated`.
- **List worktrees** (`worktree.ps`) with live status indicators.
- **Stream terminals** — subscribes via `terminal.subscribe`, decodes the
  binary terminal-stream frames, and renders live output.
- **Send input** (`terminal.send`) including an accessory bar for `esc`, `tab`,
  `^C`, arrows, etc.
- **Auto-reconnect** with the same tiered backoff as desktop.
- **Self-update from GitHub Releases** (Android) — see below.

### Project layout

```
lib/
├── main.dart
├── transport/         # wire protocol (ported from Orca desktop mobile/src/transport)
│   ├── e2ee.dart            # NaCl box encrypt/decrypt
│   ├── pairing.dart         # orca://pair link parsing
│   ├── terminal_stream.dart # 16-byte-header binary frame codec
│   ├── models.dart          # RpcResponse, HostProfile, Worktree, TerminalInfo
│   └── rpc_client.dart      # handshake + encrypted JSON-RPC + stream dispatch
├── storage/host_store.dart  # hosts in prefs; device token in secure storage
├── services/updater.dart    # GitHub Releases update checker/installer
└── screens/                 # hosts → worktrees → terminal, + update dialog
```

---

## Build

Requires the Flutter SDK (3.12+) and the Android SDK.

```bash
cd orca-flutter
flutter pub get
flutter analyze     # static analysis (clean)
flutter test        # unit tests
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Install the APK on your tablet (`adb install app-release.apk`, or sideload it).

For development against a connected device: `flutter run`.

---

## 🔄 Updating the APK from GitHub

The app updates itself from this repo's **GitHub Releases** — no Play Store
needed.

**How it works**

1. On launch (and via the ↻ button in the app bar) it calls
   `GET /repos/<owner>/<repo>/releases/latest`.
2. It compares the release tag (e.g. `orca-v0.2.0`) against the installed
   version (`package_info_plus`).
3. If newer, it offers to download the attached `*.apk` and hands it to the
   Android package installer (`REQUEST_INSTALL_PACKAGES`).

The owner/repo are configured in `lib/services/updater.dart`:

```dart
const String kUpdateOwner = 'bryantmorris042698-hyperhermes';
const String kUpdateRepo  = 'slm-matrix';
```

**Publishing an update**

CI (`.github/workflows/build-orca-apk.yml`) builds and attaches the APK to a
Release automatically when you push a tag:

```bash
# bump version in pubspec.yaml first (e.g. 0.2.0), then:
git tag orca-v0.2.0
git push origin orca-v0.2.0
```

The workflow runs `analyze` + `test`, builds the release APK named
`orca-mobile-<version>.apk`, and publishes it as the latest GitHub Release.
Installed apps pick it up on their next launch.

> First install must be sideloaded manually (download the APK from the Releases
> page). After that, in-app updates take over. Android will prompt the user to
> allow installs from this app the first time it launches an installer.

---

*Implements the Orca mobile protocol (MIT — https://github.com/stablyai/orca).*
