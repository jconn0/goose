# Technology Stack

**Analysis Date:** 2026-06-03

## Languages

**Primary:**
- Swift 5.0 — iOS app, all UI and business logic in `GooseSwift/`, live activity extension in `GooseWorkoutLiveActivityExtension/`
- Rust (Edition 2024, MSRV 1.94) — Rust core library in `Rust/core/src/`, protocol parsing, metric computation, SQLite persistence, FFI bridge

**Secondary:**
- Python — Reference algorithm scripts only (`Rust/core/tools/reference/*.py`); not used at runtime

**Config/Build:**
- Bash — Rust cross-compilation script at `Scripts/build_ios_rust.sh`

## Runtime

**Environment:**
- iOS 26.0 (deployment target — `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `GooseSwift.xcodeproj/project.pbxproj`)
- ARM64 device (`aarch64-apple-ios`), ARM64 simulator (`aarch64-apple-ios-sim`), x86_64 simulator (`x86_64-apple-ios`) all supported via build script

**Package Manager:**
- Swift: No SPM (no root `Package.swift`). Project managed via `GooseSwift.xcodeproj`. Two local packages exist in `Packages/WhoopProtocol/` and `Packages/WhoopStore/` but contain only `.swiftpm` metadata — no source files; they appear to be placeholder or removed packages.
- Rust: Cargo, lockfile at `Rust/core/Cargo.lock` (present, committed)

## Frameworks

**Core (Swift/Apple):**
- SwiftUI — all UI; 80 files import SwiftUI
- UIKit — used for appearance configuration and low-level UI hooks; 81 files import UIKit
- Foundation — universal; 97 files import Foundation
- CoreBluetooth — BLE communication with WHOOP device; 14 files import CoreBluetooth
- HealthKit — body mass autofill from Apple Health; 11 files import HealthKit; entitlement `com.apple.developer.healthkit` granted in `GooseSwift/GooseSwift.entitlements`
- CoreLocation + MapKit — outdoor workout GPS tracking; 12 files import CoreLocation, 9 import MapKit
- ActivityKit — Live Activity / Dynamic Island for workouts; `GooseSwift/WorkoutLiveActivityController.swift`, `GooseWorkoutLiveActivityExtension/GooseWorkoutLiveActivityWidget.swift`
- WidgetKit — Live Activity widget extension; `GooseWorkoutLiveActivityExtension/GooseWorkoutLiveActivityWidget.swift`
- OSLog — structured logging; 11 files import OSLog
- CryptoKit — SHA-256 file integrity checksums for export; 5 files import CryptoKit
- Security — iOS Keychain for OAuth token storage; `GooseSwift/CodexEmbeddedAuth.swift`
- UserNotifications — notification permission onboarding; `GooseSwift/OnboardingModels.swift`, `GooseSwift/OnboardingPermissions.swift`

**Testing:**
- Rust: Cargo's built-in test runner (`cargo test`). Integration tests in `Rust/core/tests/` (40+ test files). No Swift test target detected in the project.

**Build/Dev:**
- Xcode project: `GooseSwift.xcodeproj`
- Rust cross-compile: `Scripts/build_ios_rust.sh` — invoked as an Xcode build phase, produces `Rust/iphoneos/libgoose_core.a` and `Rust/iphonesimulator/libgoose_core.a`
- Python reference tools: `Rust/core/tools/reference/` — neurokit2, pyhrv, pyactigraphy, ggir; used only for algorithm validation/comparison, not production

## Key Dependencies

**Rust Crates (from `Rust/core/Cargo.toml`):**
- `rusqlite 0.37` (feature: `bundled`) — SQLite embedded in the static library; all health/capture/activity persistence goes through this
- `serde 1.0` + `serde_json 1.0` — all JSON serialisation for the FFI bridge protocol
- `tungstenite 0.28` — WebSocket server used for local debug sessions (`ws://127.0.0.1:8765`)
- `zip 0.6` — raw data export bundling
- `sha2 0.10` — SHA-256 digests inside Rust (separate from Swift CryptoKit usage)
- `crc32fast 1.4` — CRC32 frame checksums
- `hex 0.4` — hex encoding for BLE frame capture
- `thiserror 2.0` — error type derivation
- `tempfile 3.13` (dev-only) — test temporary files

**No third-party Swift dependencies detected.** All Swift code uses Apple system frameworks only.

## Configuration

**Environment:**
- No `.env` files. Configuration driven by `ProcessInfo.processInfo` launch arguments and environment variables at runtime:
  - `GOOSE_SKIP_RUST_CORE_BUILD=1` — skips Rust build phase
  - `GOOSE_RUST_RELEASE=1` / `GOOSE_RUST_DEBUG_BUILD=1` — force Rust profile
  - `GOOSE_START_PHYSIOLOGY_CAPTURE=1` — auto-start BLE capture on launch
  - `GOOSE_AUTO_HISTORICAL_SYNC=1` — auto-trigger historical sync
  - `GOOSE_ENABLE_DIAGNOSTICS=1` / `GOOSE_DISABLE_DIAGNOSTICS=1` — BLE diagnostic log
  - `GOOSE_AFC_DIAGNOSTIC_MIRROR=1` — mirror log to Documents for AFC access
  - `GOOSE_DEBUG_MENU_COMMAND_HEX` / `GOOSE_DEBUG_MENU_COMMAND` — debug command payload override

**Build:**
- `GooseSwift.xcodeproj` — main Xcode project
- `Scripts/build_ios_rust.sh` — Rust cross-compilation invoked as Xcode build phase; reads `PLATFORM_NAME`, `CONFIGURATION`, `CURRENT_ARCH`, `IPHONEOS_DEPLOYMENT_TARGET` from Xcode environment
- Bundle ID: `com.goose.swift` (main app), `com.goose.swift.WorkoutLiveActivityExtension` (extension)
- Marketing version: `0.1.0`, build: `1`
- URL scheme: `gooseswift://` (`CFBundleURLSchemes` in `GooseSwift/Info.plist`)

## Platform Requirements

**Development:**
- macOS with Xcode (iOS 26.0 SDK)
- Rust toolchain with targets: `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`
- Cargo (installed separately or via rustup)

**Production:**
- iOS device or simulator, iOS 26.0+
- Pre-built static libraries committed at `Rust/iphoneos/libgoose_core.a` and `Rust/iphonesimulator/libgoose_core.a` (build incremental — script skips rebuild if inputs unchanged)
- Bluetooth background mode required (`UIBackgroundModes: bluetooth-central`)
- Location background mode required (`UIBackgroundModes: location`)
- Local networking allowed (`NSAllowsLocalNetworking: true`) for debug WebSocket

---

*Stack analysis: 2026-06-03*
