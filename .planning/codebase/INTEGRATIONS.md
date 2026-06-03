# External Integrations

**Analysis Date:** 2026-06-03

## APIs & External Services

**OpenAI / ChatGPT Coach:**
- Service: OpenAI Responses API (streaming SSE)
  - Endpoint: `https://chatgpt.com/backend-api/codex/responses`
  - Client: `GooseSwift/OpenAICoachResponsesClient.swift` — `OpenAIResponsesClient`
  - Auth: Bearer token from stored `CodexStoredChatGPTAuth.accessToken`; account ID passed as `ChatGPT-Account-Id` header
  - Protocol: HTTP POST, `text/event-stream` accept, SSE response parsing
  - Models used: Configurable via `CoachModelPreset` (model ID and reasoning effort)
  - Tools exposed to model: `load_stats`, `get_activities`, `get_capture_sessions`, `get_data_gaps` — all local Goose Rust bridge calls, no outbound data
  - Request factory: `GooseSwift/OpenAICoachResponsesClient.swift` — `OpenAICoachRequestFactory`

**OpenAI Auth (OAuth / Device Code):**
- Service: `https://auth.openai.com` OAuth 2.0 with PKCE device-code flow
  - Client: `GooseSwift/CodexEmbeddedAuth.swift` — `CodexSelfContainedAuthClient`
  - Client ID: `app_EMoamEEZ73f0CkXaXp7hrann` (hardcoded)
  - Device code endpoint: `POST /api/accounts/deviceauth/usercode`
  - Poll endpoint: `POST /api/accounts/deviceauth/token`
  - Token exchange: `POST /oauth/token` (grant_type: authorization_code)
  - Token refresh: `POST /oauth/token` (grant_type: refresh_token)
  - Verification URL: `https://auth.openai.com/codex/device`
  - Session config: ephemeral `URLSession` (no cookies, no shared cookie store)

## Data Storage

**Databases:**
- SQLite via Rust core (`rusqlite 0.37`, bundled)
  - Database file: `goose.sqlite` (+ WAL files `goose.sqlite-wal`, `goose.sqlite-shm`)
  - Location: iOS app Application Support directory, path resolved in `GooseSwift/HealthDataStore.swift` via `HealthDataStore.defaultDatabasePath()`
  - Access: All reads/writes go through the Rust FFI bridge (`GooseSwift/GooseRustBridge.swift`); Swift never opens SQLite directly
  - Schema managed by Rust core (`CURRENT_SCHEMA_VERSION` constant in `Rust/core/src/bridge.rs`)
  - Tables cover: BLE capture frames, overnight sessions, historical sync ranges, activity sessions, activity metrics, activity intervals, sleep correction labels, calibration labels, step counter data, energy rollups, recovery rollups, HRV features, resting HR features, debug WebSocket session events

**File Storage:**
- Local filesystem (iOS sandboxed app container)
  - Application Support (`GooseSwift/` subdirectory): `goose.sqlite`, BLE diagnostic log `goose-ble.log`
  - Documents (user-accessible via iTunes file sharing, `UIFileSharingEnabled: true`, `LSSupportsOpeningDocumentsInPlace: true`): raw capture exports (ZIP bundles), overnight spool files, optional AFC diagnostic mirror `goose-ble-live.log`
  - Export bundles: ZIP archives produced by `GooseSwift/GooseLocalDataExporter+FileSystem.swift` with SHA-256 manifest; Rust `zip 0.6` crate used for bundle creation

**Caching:**
- `UserDefaults.standard` — lightweight ephemeral state: remembered BLE device ID/name, battery level, resting HR estimate, live HRV, onboarding flags, Coach model preset preference
- In-memory `HeartRateSeriesStore.shared` singleton for live HR time series

## Authentication & Identity

**Auth Provider: OpenAI (ChatGPT account)**
- Flow: OAuth 2.0 device code — user visits `https://auth.openai.com/codex/device` and enters a code
- Implementation: `GooseSwift/CodexEmbeddedAuth.swift` — full device-code + PKCE token exchange + refresh
- Token storage: iOS Keychain (`kSecClassGenericPassword`, service `com.goose.swift.codex`, account `chatgpt-auth`), protection `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- Token refresh: automatic when token age exceeds 50 minutes or explicit `expiresAt` is within 60 seconds
- No user account system of its own — Goose is fully local except for the Coach AI feature

## Monitoring & Observability

**Error Tracking:**
- None (no Sentry, Crashlytics, Firebase, or similar)

**Logs:**
- OSLog (`Logger(subsystem: "com.goose.swift", category: "ble")`) for BLE events; `GooseSwift/GooseBLEClient.swift`
- Optional file-based BLE diagnostic log: `goose-ble.log` in Application Support — enabled via launch argument `--goose-enable-diagnostics` or env `GOOSE_DIAGNOSTIC_LOGGING=1`
- Optional AFC mirror log: `goose-ble-live.log` in Documents — enabled via `--goose-afc-diagnostic-mirror` or `GOOSE_AFC_DIAGNOSTIC_MIRROR=1`
- Overnight spool: raw BLE notification log written to Documents during overnight session; `GooseSwift/OvernightRawNotificationSpool.swift`

## CI/CD & Deployment

**Hosting:**
- iOS app, distributed via Xcode direct install or TestFlight (no App Store listing detected)

**CI Pipeline:**
- None detected (no GitHub Actions, Fastlane, Bitrise, or CI config files found)

## Bluetooth (WHOOP Device Protocol)

**Device:** WHOOP strap (Gen 4 / Gen 5 / Puffin variants)
- Framework: CoreBluetooth (`GooseSwift/GooseBLEClient.swift`)
- Background mode: `bluetooth-central` (persistent connection while app is backgrounded)
- State restoration identifier: `com.goose.swift.central`

**GATT Services (proprietary WHOOP):**
- Primary service UUID: `fd4b0001-cce1-4033-93ce-002d5875f58a`
- Secondary service UUID: `61080001-8d6d-82b8-614a-1c8cb0f8dcc6`

**GATT Characteristics:**
- Command write: `fd4b0002` / `61080002`
- Notification: `fd4b0003`–`fd4b0005`, `fd4b0007` / `61080003`–`61080005`, `61080007`
- Debug menu: `fd4b0007` / `61080007`

**Standard GATT Services:**
- Heart Rate Service `180D`, measurement characteristic `2A37`
- Battery Service `180F`, level `2A19`, level status `2BED`
- Device Information `180A` — model `2A24`, firmware `2A26`, hardware `2A27`, software `2A28`, manufacturer `2A29`

**Protocol:** Proprietary binary v5 packet framing. Parsed by Rust core via `protocol.parse_frame_hex` / `protocol.parse_frame_hex_batch` bridge methods. Frame parsing logic in `Rust/core/src/protocol.rs`.

## Apple Platform Integrations

**HealthKit:**
- Permission: `com.apple.developer.healthkit` entitlement + `NSHealthShareUsageDescription`
- Read: body mass only (`HKObjectType.quantityType(forIdentifier: .bodyMass)`) for profile weight autofill
- Implementation: `GooseSwift/HealthKitSleepImporter.swift` — `HealthKitProfileImporter`
- No HealthKit write access

**Location Services:**
- Framework: CoreLocation + MapKit
- Permission: always + when-in-use (`NSLocationAlwaysAndWhenInUseUsageDescription`)
- Background mode: `location`
- Used for: outdoor workout route, pace, distance, elevation in `GooseSwift/ActivityLocationTracker.swift`
- Accuracy: `kCLLocationAccuracyBest`, distance filter 5 m, fitness activity type

**Live Activities / Dynamic Island:**
- Framework: ActivityKit + WidgetKit
- Main app controller: `GooseSwift/WorkoutLiveActivityController.swift`
- Widget extension: `GooseWorkoutLiveActivityExtension/GooseWorkoutLiveActivityWidget.swift`
- Attributes type: `GooseSwift/WorkoutLiveActivityAttributes.swift`
- Entitlement: `NSSupportsLiveActivities: true`, `NSSupportsLiveActivitiesFrequentUpdates: true`

**Deep Links:**
- URL scheme: `gooseswift://`
- Handled in: `GooseSwift/GooseSwiftApp.swift` via `.onOpenURL`; debug command deep links routed to `GooseAppModel.handleDebugCommandDeepLink(_:)`

## Debug / Development Integrations

**Local WebSocket Debug Server:**
- Rust crate: `tungstenite 0.28`
- Binaries: `goose-debug-ws-serve`, `goose-debug-ws-contract`
- iOS client connects to `ws://127.0.0.1:8765` during debug sessions
- Allows real-time bridging of BLE command/event data to desktop tools
- Implementation: `Rust/core/src/debug_ws_server.rs`, `Rust/core/src/debug_ws.rs`
- Bridge methods: `debug.start_session`, `debug.start_command`, `debug.finish_command`, `debug.record_event`, `debug.session_snapshot`

**Python Reference Tools (dev-only, offline):**
- `Rust/core/tools/reference/neurokit_hrv.py` — HRV reference (neurokit2)
- `Rust/core/tools/reference/pyhrv_time_domain.py` — HRV time-domain reference (pyhrv)
- `Rust/core/tools/reference/pyactigraphy_sadeh.py` — sleep actigraphy (pyactigraphy)
- `Rust/core/tools/reference/ggir_sleep_summary.py` — sleep GGIR summary reference
- Used only to generate ground-truth fixtures for Rust algorithm regression tests; not called at runtime

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None (all Coach tool calls return local Rust bridge data, no outbound telemetry)

---

*Integration audit: 2026-06-03*
