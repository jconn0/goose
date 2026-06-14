# Findings

## Overview

Fork of `b-nnett/goose` -> `1324123sedrf/goose`. The upstream `b-nnett/goose` is itself a fork of `tigercraft4/goose`. This fork has diverged significantly — the local copy has its own milestones and fixes not in either upstream.

## Build Pipeline

An existing release workflow (`.github/workflows/release.yml`) builds unsigned IPAs on `macos-15` runners:

1. Installs Rust + `aarch64-apple-ios` target
2. Runs `xcodebuild` with `CODE_SIGNING_ALLOWED=NO`
3. Packages `Payload/GooseSwift.app` into an unsigned IPA
4. Uploads to GitHub Releases + updates `altstore-source.json`

**No Mac needed** — GitHub's macOS runners handle everything. IPA can be sideloaded with SideStore (resigns on-device with a free Apple ID).

Before building a personal fork, change the bundle ID in:
- `Config/Signing.xcconfig` — `APP_BUNDLE_ID = com.goose.app`
- `Config/SigningExtension.xcconfig` — `APP_BUNDLE_ID = com.goose.app`

Both include `Config/Local.xcconfig` (gitignored) for local overrides.

## WHOOP MG Support

### Current state of this fork
**No MG support.** The local codebase has no `WhoopMG`, `WhoopDeviceGeneration`, or MG-specific references anywhere in Swift or Rust.

### PR #50 on `b-nnett/goose` (naz3eh)
The only PR that specifically adds MG support. Two commits, opened Jun 12:

- **Device detection** — new `WhoopDeviceGeneration` enum, `isWhoopMG` property, derived from model number (no extra BLE traffic)
- **ECG capture** — Labrador sensor stream commands (124 data gen, 125 raw save, 139 filtered stream) toggled when MG connected
- **K16 raw ECG parsing** — Rust protocol layer parses K16 (raw ECG Labrador) body summaries, shares existing R17 logic
- **Pure Swift frame parser** — `WhoopFrameParser` replaces `NotificationFrameParser`'s Rust FFI round-trip (hex → JSON → C FFI → Rust → JSON → decode) with direct Swift parsing on the notification hot path. Covers all data/event/command packet types. Output parity checked against Rust parser.

### PR #19 on `b-nnett/goose` (po-sc) + PR #26 (jakobrmarrone)
Both are WHOOP 4.0 (Gen4) focused, not MG. #19 has the most substantive review discussion with tigercraft4. They conflict with each other — #19 uses `CommandGeneration` enum, #26 uses `WhoopGeneration`. Both need reconciling.

### Noop (`NoopApp/noop`)
A separate, standalone app (not a fork of goose):

- **MG/5.0 status:** 🧪 Experimental. Live HR works; recovery/strain/sleep still being reverse-engineered
- **Architecture:** Pure Swift + Kotlin (no Rust). Cross-platform: macOS + Android + iOS
- **Protocol:** Schema-driven decode via `whoop_protocol.json`. `DeviceFamily` enum: `whoop4` / `whoop5`
- **Storage:** GRDB (SQLite) on iOS, Room on Android
- **Scoring:** On-device implementations of published methods (Task Force 1996 HRV, Karvonen %HRR, Banister TRIMP, etc.)
- **License:** PolyForm Noncommercial 1.0.0 — free for personal/non-commercial, not open source
- **IPA distribution:** Unsigned IPAs via GitHub Releases, same SideStore approach
- **MG-specific:** No ECG/Labrador support. Live HR confirmed on real hardware via standard BLE Heart Rate profile (180D/2A37). Bonding with 5.0/MG requires freeing the strap from the official WHOOP app first

### Key gap: PR #50 vs Noop for MG

| Feature | PR #50 (b-nnett/goose) | Noop |
|---------|------------------------|------|
| Live HR | Yes | Yes |
| ECG capture | Yes (Labrador streams) | No |
| Recovery metrics | Via Rust core | Experimental |
| Swift-only hot path | Yes (WhoopFrameParser) | Yes (native Swift) |
| Android support | No | Yes |
| Self-hosted server | Yes (FastAPI) | No |
| License | GPL v3 (open source) | PolyForm (source-available) |
