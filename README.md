<!-- generated-by: gsd-doc-writer -->
> **Disclaimer — Unofficial Project / Personal Data Research**
>
> Goose is an independent, unofficial project not affiliated with, endorsed by, or supported by WHOOP, Inc. This project accesses biometric data exclusively over Bluetooth Low Energy from the user's own hardware — it does not touch WHOOP's servers or APIs. It was built for personal research and data portability purposes only, grounded in GDPR Art. 20 (right to data portability) and EU Directive 2009/24/EC Art. 6 (interoperability exception).
>
> See [DISCLAIMER.md](DISCLAIMER.md) for the full legal statement.

# Goose - Local Companion for WHOOP Devices

> **Fork of [jconn0/goose](https://github.com/jconn0/goose).** This fork builds on [tigercraft4/goose](https://github.com/tigercraft4/goose) and [b-nnett/goose](https://github.com/b-nnett/goose) with WHOOP MG support, a pure-Swift BLE frame parser, and integrated upstream PRs. Tested on WHOOP MG hardware.

**Alpha proof of concept.** Not ready for daily use as a health tracker.

This prototype targets **WHOOP 5.0, WHOOP 4.0, and WHOOP MG** (the medical-grade WHOOP 5.0 variant).

![Goose app hero showing a connected WHOOP 5.0 device](docs/assets/readme-hero.png)

## Quick Start — No Mac Required

Unsigned IPAs are built via GitHub Actions on `macos-15` runners and can be sideloaded with **SideStore** (or AltStore):

1. Go to **Actions → Release → Run workflow** with a tag like `v11.0`
2. Download the unsigned IPA artifact
3. Drop into SideStore — it resigns on-device with your free Apple ID

Change the bundle ID in `Config/Signing.xcconfig` before building if you fork.

## Key Changes in This Fork

- **WHOOP MG support** — device detection, Labrador ECG sensor streams (cmd 124/125/139), K16 raw ECG parsing in Rust core
- **Pure Swift frame parser** — `WhoopFrameParser` replaces the Rust FFI round-trip on the per-notification BLE hot path for lower latency
- **Upstream PRs integrated** — BLE exponential backoff, FFI bridge optimization, deep-link security, WAL mode/capture storage fixes, scroll/threading perf, and more
- **Self-hosted server** — FastAPI + TimescaleDB for persisting biometric streams (optional, app works standalone)

Goose is a local-first WHOOP data and health metrics project. The iOS app connects to WHOOP bands, routes packet data through the Goose Rust core, and turns that data into daily health, recovery, sleep, strain, stress, cardio, energy, coach, and debug views. An optional self-hosted server lets you persist decoded biometric streams outside the device.

## What's Here

**Device support**

- WHOOP 5.0 and WHOOP MG — connect, live HR, historical sync, Labrador ECG streams
- WHOOP 4.0 — full support via upstream Gen4 integration (BLE framing, historical sync, V12/V24 metric decode)

**WHOOP MG specific**

- MG device detection from model number (`WhoopDeviceGeneration` enum)
- Labrador sensor commands (124/125/139) for raw ECG capture
- K16 raw ECG packet parsing in Rust + pipeline integration

**Performance**

- `WhoopFrameParser` — pure Swift BLE frame parser replaces Rust FFI round-trip on the per-notification hot path (covers all data/event/command packet types with verified output parity)
- `@ObservationIgnored lazy var rust` — defers bridge init until first use so UI renders before FFI
- WAL mode + capture-path indexes in SQLite

**BLE reliability**

- Exponential backoff reconnect (1s→60s ramp, 10-attempt cap) with UI banner
- BLE auth retry on `insufficientAuthentication`
- Deep-link security — state-changing commands blocked from URL scheme

**Metrics and algorithms**

- HRV: BLE-gap aware RMSSD with segment-aware differencing and Malik ectopic filter
- Sleep staging: Cole-Kripke + 4-class AASM model
- Strain/calories: Ghidra-confirmed WHOOP coefficients
- Recovery: goose_recovery_v0 (HRV-dominant z-score vs personal baseline)
- Readiness Engine v1: ACWR with Foster monotony

**Self-hosted server**

- FastAPI + TimescaleDB, Dockerized
- 10 stream tables with `synced` flag for upload tracking
- API-compatible with my-whoop

**Rust core**

- SQLite with versioned schema
- 45+ integration test files in `Rust/core/tests/`

## Project Layout

```text
GooseSwift/                         SwiftUI app source
GooseSwiftTests/                    XCTest suite for Swift components
GooseWorkoutLiveActivityExtension/  Live Activity widget extension
Rust/                               iOS static library, headers, per-platform outputs
Scripts/build_ios_rust.sh           Xcode build phase for the Goose Rust core
server/                             Self-hosted FastAPI+TimescaleDB server (Docker)
docs/guides/                        Getting started, development, testing, configuration guides
docs/architecture/                  System overview and component diagrams
docs/api/                           Server API reference
GooseSwift.xcodeproj                Xcode project
```

Key Swift entry points:

- `GooseSwiftApp.swift`: app lifecycle and deep-link handling.
- `RootView.swift`: onboarding gate and global sync toast host.
- `AppShellView.swift`: tab shell and shared health store wiring.
- `GooseAppModel.swift`: app state, BLE ownership, lifecycle, and bridge summaries.
- `GooseBLEClient.swift`: Bluetooth scan/connect/sync logic.
- `GooseRustBridge.swift`: Swift wrapper around the Rust C bridge.
- `HealthView.swift` and `Health*` files: health dashboards, metric pages, trends, and sheets.
- `CoachView.swift` and `Coach*` files: coach UI and chat support.
- `MoreView.swift`: operational/debug/settings surfaces.

This is an active prototype. Because the data pipeline is still evolving, some metrics appear as empty or unavailable until the app has a source for them.

## Independence

Goose is an independent project and is not affiliated with WHOOP. This repository does not include or reference source code owned by WHOOP. The app communicates with WHOOP bands over Bluetooth using services and data exposed by the device, then parses and stores that local data through the Goose Rust core. Product names are used only to describe compatibility.

## Acknowledgements

Built on [b-nnett/goose](https://github.com/b-nnett/goose) (original iOS app, BLE protocol, Rust core) and [tigercraft4/goose](https://github.com/tigercraft4/goose) (server, Coach, Gen4 support, upstream PR integration). WHOOP MG support from [PR #50](https://github.com/b-nnett/goose/pull/50) by [naz3eh](https://github.com/naz3eh). BLE patterns drawn from [Noop](https://github.com/NoopApp/noop). Self-hosted server adapted from [my-whoop](https://github.com/tigercraft4/my-whoop) / [johnmiddleton12/wearable](https://github.com/johnmiddleton12/wearable).

## Current Scope

- SwiftUI app shell with Home, Health, Coach, and More tabs.
- CoreBluetooth scan/connect flows for WHOOP 5.0, WHOOP 4.0, and WHOOP MG.
- Pure-Swift BLE frame parser (`WhoopFrameParser`) with Rust fallback for non-hot paths.
- JSON-over-C bridge into the Goose Rust core.
- Self-hosted server (`server/`): FastAPI + TimescaleDB, Dockerized.
- Automatic upload of decoded biometric data from iOS to server (10 stream tables).
- Health metric surfaces for Sleep, Recovery, Strain, Stress, Cardio Load, Energy Bank, Health Monitor, Packet Inputs, Coach, and Debug.
- HealthKit sleep import and workout write support.
- CI: unsigned IPA builds for SideStore sideloading.

## Requirements

- macOS with Xcode installed (only if building locally).
- iOS 26.0 SDK and an iOS 26.0 capable device.
- Configure `APP_BUNDLE_ID` in `Config/Signing.xcconfig` (or `Config/Local.xcconfig`, gitignored).
- Rust and Cargo for building the Goose Rust core from the committed `Rust/core` source.
- iOS Rust targets installed with `rustup`; see the Rust Core Bridge section below.
- Docker (for the self-hosted server — optional).

Built Rust `.a` archives (`Rust/iphoneos/libgoose_core.a` and `Rust/iphonesimulator/libgoose_core.a`) are committed to the repository as pre-built artifacts. Set `GOOSE_SKIP_RUST_CORE_BUILD=1` to skip rebuilding when the committed archives are already valid for the active Xcode platform.

## Build

Clone the repository first:

```bash
git clone https://github.com/jconn0/goose.git
cd goose
```

Open `GooseSwift.xcodeproj` in Xcode and build the `GooseSwift` scheme, or build from the command line.

Unsigned IPA via GitHub Actions (no Mac needed — runs on `macos-15` runners):

```yaml
# On any push to a v* tag, or manually via Actions → Release → Run workflow
# Downloads the unsigned .ipa for SideStore/AltStore sideloading
```

Simulator build:

```sh
xcodebuild \
  -project GooseSwift.xcodeproj \
  -scheme GooseSwift \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/goose-swift-deriveddata \
  build
```

Physical device build:

```sh
xcodebuild \
  -project GooseSwift.xcodeproj \
  -scheme GooseSwift \
  -configuration Debug \
  -destination 'platform=iOS,id=<device-id>' \
  -derivedDataPath /tmp/goose-swift-deriveddata-device \
  -allowProvisioningUpdates \
  build
```

List connected devices:

```sh
xcrun devicectl list devices
```

## Reinstall On A Device

After a successful physical-device build, reinstall and launch:

```sh
xcrun devicectl device uninstall app \
  --device <device-id> \
  <bundle-id>

xcrun devicectl device install app \
  --device <device-id> \
  /tmp/goose-swift-deriveddata-device/Build/Products/Debug-iphoneos/GooseSwift.app

xcrun devicectl device process launch \
  --device <device-id> \
  --terminate-existing \
  <bundle-id>
```

## Self-Hosted Server

The `server/` directory contains an optional FastAPI + TimescaleDB backend. The iOS app works standalone without it.

```bash
cd server
cp .env.example .env
# Set GOOSE_API_KEY and GOOSE_DB_PASSWORD in .env
docker compose up -d --build
```

Check it started: `curl -s localhost:8770/healthz` → `{"status":"ok"}`

Configure the server URL and Bearer token in the iOS app under More > Server Settings. See `server/README.md` for API details and the full list of environment variables.

## Rust Core Bridge

The Rust bridge source is committed in `Rust/core`. Do not commit built `.a`
archives; Xcode generates them locally through `Scripts/build_ios_rust.sh`.

Prerequisites:

- Xcode command line tools.
- Rust via `rustup`.
- iOS Rust targets:

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
```

`Scripts/build_ios_rust.sh` builds `Rust/core` for the active Xcode platform:

- `iphoneos` -> `aarch64-apple-ios`
- `iphonesimulator` on Apple Silicon -> `aarch64-apple-ios-sim`
- `iphonesimulator` on Intel -> `x86_64-apple-ios`

Outputs are staged into:

```text
Rust/iphoneos/libgoose_core.a
Rust/iphonesimulator/libgoose_core.a
```

The Swift target links `Rust/$(PLATFORM_NAME)/libgoose_core.a` and reads the C
bridge header from `Rust/core/include/goose_core_bridge.h`. The default Cargo
target directory is `build/rust-target/goose-core`, so Rust build products stay
outside the committed source tree.

Manual builds:

```bash
# Simulator on Apple Silicon
PLATFORM_NAME=iphonesimulator CURRENT_ARCH=arm64 Scripts/build_ios_rust.sh

# Physical iPhone
PLATFORM_NAME=iphoneos CURRENT_ARCH=arm64 Scripts/build_ios_rust.sh
```

You normally do not need to run these by hand; the Xcode build phase runs the
script before compiling Swift.

## Data And Privacy

- Metric views show empty, stale, or unavailable states when a source is missing.
- Metric rows and trend sheets show where values came from when that information is available.
- Raw packet payloads stay in debug/export flows rather than everyday health views.
- Coach responses use the same local metric summaries shown in the app.
- Health and fitness data is local by default. Any future backend or AI feature will need its own consent flow and privacy notes.

## Documentation

Guides and reference docs:

- `docs/guides/getting-started.md`: prerequisites, clone, first run, and common setup issues.
- `docs/guides/development.md`: local setup, build commands, code style, and PR process.
- `docs/guides/testing.md`: Rust test suite, coverage, and CI integration.
- `docs/guides/configuration.md`: environment variables and server configuration.
- `docs/architecture/overview.md`: system overview, component diagram, and data flow.
- `docs/api/reference.md`: server API endpoints, request/response formats, and authentication.

## Contributing

This project moves quickly, so small focused changes are easiest to review.

Want to talk to other contributors? [Join the discussion on GitHub](https://github.com/tigercraft4/goose/discussions).

- Keep changes close to the feature or bug you are working on.
- Match the existing SwiftUI style before introducing new patterns.
- Build after touching Swift, Rust bridge, project, or signing settings.
- Check both empty and populated states for metric UI when possible.
- Keep user-facing health copy plain and careful. Avoid medical claims.
- Put debug tooling, packet details, and raw export behavior under More or Debug surfaces.
- Update the relevant MVP doc when a change completes or changes an open task.
- Mention any build warnings, skipped checks, or device-only assumptions in the PR notes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines including code style, Rust bridge conventions, and the PR checklist.

## Development Notes

- Prefer small, typed Swift models over displaying raw summary strings.
- Keep Home, Health, Coach, and More routes modular enough to work independently.
- Metric pages should still look polished when data is missing.
- Before installing to a device, run a simulator or device build and check that the Rust library target matches the destination platform.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
