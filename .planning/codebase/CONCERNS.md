# Codebase Concerns

**Analysis Date:** 2026-06-03

---

## Tech Debt

### Rust FFI Bridge is a Single Monolithic Dispatch Table

- Issue: `bridge.rs` is 8,153 lines with a single `handle_bridge_request_inner` function containing 143+ match arms mapping string method names to handler calls. Every new Rust capability requires extending this one file. There is no middleware, no versioning at the method level, and no type-safe call boundary — all args cross as `serde_json::Value` / `[String: Any]` dictionaries.
- Files: `Rust/core/src/bridge.rs`, `GooseSwift/GooseRustBridge.swift`
- Impact: Merges and rebases become painful as the file grows. Method contract breakage is invisible at compile time; a renamed method key silently causes a runtime `unknown_method` error on the Swift side.
- Fix approach: Group methods into sub-dispatchers by namespace (e.g., `metrics.*`, `overnight.*`, `export.*`) so each namespace lives in its own file. Introduce a typed method registry or macro to enforce that every Swift call site matches a registered Rust method key.

### Multiple Uncoordinated `GooseRustBridge` Instances

- Issue: Thirteen separate `GooseRustBridge()` instantiation sites across the app create independent objects, each with their own `counter` state. The bridge itself is stateless on the Rust side, so counter collisions do not corrupt data, but `lastTiming` is per-instance and there is no shared timing budget or call-rate limiting.
- Files: `GooseSwift/HealthDataStore.swift:25`, `GooseSwift/MoreDataStore.swift:93`, `GooseSwift/OvernightSQLiteMirrorQueue.swift:33`, `GooseSwift/CaptureFrameWriteQueue.swift:183`, `GooseSwift/NotificationFrameParsing.swift:215`, `GooseSwift/GooseAppModel+ActivityTimeline.swift:110`, `GooseSwift/GooseLocalDataExporter+FileSystem.swift:29`, `GooseSwift/GooseLocalDataExporter+Metrics.swift:250`, `GooseSwift/GooseAppModel+HealthCapture.swift:21`, `GooseSwift/MoreDataStore.swift:481`, `GooseSwift/HealthDataStore+PacketInputs.swift:8`
- Impact: Makes it impossible to reason about total bridge call frequency or aggregate timing in production. When adding perf budgets or call throttling, each site must be updated individually.
- Fix approach: Centralise behind a shared singleton or injected service, inject via dependency injection at app startup.

### `runPacketScores()` Blocks `@MainActor`

- Issue: `HealthDataStore.runPacketScores()` (called directly from a SwiftUI `Button` action in `HealthDashboardViews.swift:613`) makes five sequential synchronous Rust FFI calls (sleep, strain, recovery, stress) on the main actor thread without offloading to a background queue. `runPacketInputs()` was correctly offloaded to `packetInputQueue`, but `runPacketScores` was not.
- Files: `GooseSwift/HealthDataStore+Snapshots.swift:7-42`, `GooseSwift/HealthDashboardViews.swift:613`
- Impact: Each call serialises JSON, crosses the FFI boundary, runs Rust computation, and deserialises back. On a real dataset this can block the UI for hundreds of milliseconds.
- Fix approach: Mirror the `runPacketInputs` pattern — add a `packetScoreQueue`, run scores there, dispatch results back to `@MainActor`.

### `refreshBridgeCatalogs()` Blocks During App Launch on `@MainActor`

- Issue: `HealthDataStore.loadBridgeCatalogsIfNeeded()` → `refreshBridgeCatalogs()` is called from `HealthDataStore.init()` (via line 111) and from `HealthView.swift:110`. The three `bridge.requestValue` calls inside it are synchronous on the main actor. This runs every time the health view appears before the catalog has loaded.
- Files: `GooseSwift/HealthDataStore.swift:106-198`, `GooseSwift/HealthView.swift:110`
- Impact: Blocks the main thread during launch, potentially causing frame drops or a perceived freeze if the Rust library takes time to warm up.
- Fix approach: Move catalog loading to `Task.detached` or a background actor, returning results to `@MainActor` via `MainActor.run`.

### Additive-Only SQLite Migration Strategy Has No Rollback Path

- Issue: Schema migrations in `GooseStore::migrate()` use `CREATE TABLE IF NOT EXISTS` and `ALTER TABLE … ADD COLUMN` guards. Version numbers 1–14 are bulk-inserted into `goose_schema_migrations` in a single `execute_batch`. There is no downgrade path — if a user rolls back to an older app binary, the schema version check in `storage_check.rs:96` will fail and the database will be reported as unusable.
- Files: `Rust/core/src/store.rs:928-1431`, `Rust/core/src/storage_check.rs:91-98`
- Impact: A user who installs a beta then reverts to a stable release will see a schema-mismatch error and lose access to their data until they either re-upgrade or delete the database.
- Fix approach: Document the no-rollback constraint explicitly in the schema version comment. Consider writing a `downgrade_schema` path for at least one version back, or surface a user-visible migration warning before writing schema version bumps.

### `@unchecked Sendable` Bypasses Swift Concurrency Checks in Four Critical Classes

- Issue: `OvernightSQLiteMirrorQueue`, `OvernightRawNotificationSpool`, `CaptureFrameWriteQueue`, and `NotificationFrameParser` all suppress the Swift concurrency checker with `@unchecked Sendable`. These classes manage internal `DispatchQueue`-guarded mutable state, which is correct in principle, but the suppression disables all compiler-enforced safety guarantees, meaning new properties added in the future won't be automatically checked.
- Files: `GooseSwift/OvernightSQLiteMirrorQueue.swift:25`, `GooseSwift/OvernightRawNotificationSpool.swift:65`, `GooseSwift/CaptureFrameWriteQueue.swift:180`, `GooseSwift/NotificationFrameParsing.swift:214`
- Impact: Developer discipline is the only guard. A future contributor adding a non-queue-protected property won't get a compiler error.
- Fix approach: Replace with `actor` types wherever the internal dispatch queue pattern can be expressed as an actor, eliminating the need for `@unchecked Sendable`.

---

## Security Considerations

### OpenAI Client ID Hardcoded in Source

- Risk: `CodexSelfContainedAuthClient` has `private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"` embedded directly in Swift source. This is a public OAuth client credential (device-flow clients are inherently public), but publishing it in an open-source fork means the ID is trivially discoverable. If OpenAI rate-limits or revokes this specific app's client ID, the coach feature will silently fail for all fork users without a code update.
- Files: `GooseSwift/CodexEmbeddedAuth.swift:139`
- Current mitigation: Device-flow OAuth client IDs are low-risk by design (no secret is embedded), and access tokens are stored in the Keychain.
- Recommendations: Consider moving the client ID to an xcconfig/Info.plist build variable so it can be overridden per fork without touching source code.

### Coach Conversation History Stored in UserDefaults (Unencrypted)

- Risk: `CoachChatTypes` persists the full conversation history (user health questions and assistant answers) to `UserDefaults.standard` under key `goose.coach.conversation.v1`. UserDefaults are backed by a plist in the app container — not encrypted, not in the Keychain.
- Files: `GooseSwift/CoachChatTypes.swift:94-117`
- Current mitigation: Data is in the app sandbox (inaccessible to other apps without jailbreak). The app does not appear to send this data off-device.
- Recommendations: Conversations may contain health-sensitive text typed by the user. Store them in an encrypted Core Data store or under a ProtectedData file protection class, or clear on device lock. At minimum, add a clear-on-upgrade migration.

### `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` Expose SQLite Database via Files App

- Risk: Both keys are set to `true` in `Info.plist`. This means the entire app container (including `GooseSwift/goose.sqlite` and its WAL/SHM files) is visible and copyable via the iOS Files app and iTunes file sharing without any additional authentication.
- Files: `GooseSwift/Info.plist:34,59`
- Current mitigation: Intended to support the raw-data export workflow.
- Recommendations: Restrict file sharing to a dedicated `Exports/` subdirectory rather than exposing the entire app container. The SQLite database contains raw BLE biometric data.

### WHOOP BLE UUIDs Are Hardcoded Without Constants from the Reference Module

- Risk: The twelve WHOOP service/characteristic UUIDs in `GooseBLEClient.swift:367-397` are raw `CBUUID(string:)` literals that duplicate the constants defined in `Rust/core/src/openwhoop_reference.rs:70-75`. If WHOOP changes UUIDs in a future firmware update, two independent locations must be updated and the Rust-side reference becomes inconsistent with the Swift-side scanning filter.
- Files: `GooseSwift/GooseBLEClient.swift:366-397`, `Rust/core/src/openwhoop_reference.rs:70-75`
- Current mitigation: The Rust reference file is well-attributed and pinned to a specific OpenWhoop commit.
- Recommendations: Expose UUID constants via the bridge (`openwhoop.reference_report` already returns them) and have Swift consume them from the bridge response rather than hardcoding independently.

### Debug WebSocket Server Has Configurable `bind_host` with No Auth

- Risk: `DebugWsServerOptions.bind_host` is a runtime parameter. If set to `0.0.0.0` (which is a valid DNS-resolvable value), the debug WebSocket server accepts connections from all network interfaces on the device. There is no authentication, token check, or TLS on the server.
- Files: `Rust/core/src/debug_ws_server.rs:25,69-80`
- Current mitigation: The server is only started from the Swift side as a developer tool (`MoreDataStore+Validation.swift:212` hardcodes `ws://127.0.0.1:8765`), and only runs when explicitly triggered. It is not started at app launch.
- Recommendations: Enforce `127.0.0.1` in the Swift call site; add a compile-time gate or runtime guard in `bind_debug_ws_listener` that rejects any non-loopback host in non-debug builds.

### `NSAllowsLocalNetworking` Bypasses ATS for Local Network

- Risk: `Info.plist` enables `NSAllowsLocalNetworking`, which exempts all local network connections from App Transport Security. This is appropriate for the debug WebSocket server but broadens the attack surface if any other local HTTP endpoint is inadvertently called.
- Files: `GooseSwift/Info.plist:52-56`
- Current mitigation: Scoped to `NSAllowsLocalNetworking` only (not `NSAllowsArbitraryLoads`).
- Recommendations: No urgent action; document the rationale in a code comment alongside the plist entry.

---

## Performance Bottlenecks

### JSON Serialisation Round-Trip on Every FFI Call

- Problem: Every Rust bridge call — including high-frequency overnight mirror flushes — serialises a Swift `[String: Any]` dictionary to JSON, converts to a C string, crosses the FFI boundary, parses JSON in Rust, and reverses the process on the response. This happens synchronously and involves heap allocations on both sides.
- Files: `GooseSwift/GooseRustBridge.swift:40-68`, `Rust/core/src/bridge.rs:1908-1923`
- Cause: The JSON-over-C-string protocol was chosen for safety and simplicity. It avoids manual struct layout across FFI but pays a serialisation cost on every call.
- Improvement path: For the most frequent call (`overnight.mirror_batch`), consider a direct C struct ABI or binary encoding for the hot path. For lower-frequency calls, the current approach is acceptable.

### `OvernightSQLiteMirrorQueue` Retries the Entire Batch on Any Error

- Problem: In `flushPendingLocked()`, if the `overnight.mirror_batch` bridge call throws, all three pending arrays (`sessions`, `rawNotifications`, `historicalRangePolls`) are re-inserted at the front of their respective queues and retried on the next flush. A persistent Rust-side error (e.g., corrupt database) will fill the queue to `maxQueuedRows = 4096` entries and begin silently dropping new data.
- Files: `GooseSwift/OvernightSQLiteMirrorQueue.swift:238-245`
- Cause: The retry-all strategy is simple but does not distinguish recoverable errors (transient I/O) from fatal ones (schema mismatch, corrupt file).
- Improvement path: Add a retry counter per-batch; after N consecutive failures, clear the queue and surface a persistent error rather than continuing to accumulate dropped rows silently.

---

## Fragile Areas

### Bridge Method String Keys Are the Only Contract Between Swift and Rust

- Files: `Rust/core/src/bridge.rs:1952-2496`, all `GooseSwift/*.swift` call sites using `bridge.request(method: "...")`
- Why fragile: Method names like `"overnight.mirror_batch"`, `"metrics.sleep_score_from_features"`, and `"export.raw_timeframe"` are free-form strings. A typo on either side produces a silent `methodFailed` error at runtime. There are no generated Swift stubs, no shared schema file, and no compile-time check.
- Safe modification: When adding or renaming a method, grep both `bridge.rs` match arms and all Swift `bridge.request(method:)` call sites simultaneously. The bridge tests in `Rust/core/tests/bridge_tests.rs` do exercise all named methods — run them before any rename.
- Test coverage: Rust integration tests cover all 143+ bridge methods. Swift side has zero unit tests; coverage depends entirely on manual UI exercise.

### `store.migrate()` Runs Inside a Single `execute_batch` with No Transaction Savepoints

- Files: `Rust/core/src/store.rs:928-1431`
- Why fragile: All `CREATE TABLE IF NOT EXISTS` statements and the `PRAGMA user_version = 14` are in one `execute_batch`. If the batch partially executes and the app is killed mid-migration (e.g., by iOS), the schema may be left in an inconsistent intermediate state. SQLite's `execute_batch` does not wrap the entire batch in a single transaction by default.
- Safe modification: Wrap schema changes in `BEGIN; ... COMMIT;` inside the batch, or use `conn.execute_batch("BEGIN; ...schema...; COMMIT;")` so the migration is atomic.
- Test coverage: `store_tests.rs` and `storage_check_tests.rs` test the happy path but do not simulate partial migration failures.

### `GooseBLEClient` Has 972 Lines on a Single Class with 70+ `@Published` Properties

- Files: `GooseSwift/GooseBLEClient.swift`
- Why fragile: The class owns BLE scanning, connection, GATT characteristic subscriptions, alarm scheduling, historical sync, high-frequency history sync, clock synchronisation, and battery state — all as `@Published` properties on a single `ObservableObject`. Any change to one responsibility risks unintended side effects on the others.
- Safe modification: Test in isolation using a real device before merging any change to this file. Changes to the reconnection logic or characteristic subscriptions should be validated across all iOS background states.
- Test coverage: No Swift unit tests exist for this class.

---

## Dependencies at Risk

### `rusqlite` with `bundled` Feature Compiles SQLite into the Static Library

- Risk: `rusqlite = { version = "0.37", features = ["bundled"] }` compiles a specific SQLite version into `libgoose_core.a`. The app therefore ships two copies of SQLite: the system SQLite (used by iOS APIs) and the bundled one (used by the Rust core). Security patches to the system SQLite do not automatically apply to the bundled copy.
- Impact: If a CVE is discovered in SQLite, Goose requires a Cargo dependency update + full Rust rebuild + app release to ship the fix.
- Migration plan: Evaluate `rusqlite` without `bundled` on iOS to link against the system-provided SQLite (`/usr/lib/libsqlite3.dylib`). This is supported on iOS via a linker flag and would keep the SQLite version in sync with OS updates.

### `tungstenite = "0.28"` Is Compiled into the Static Library for Debug-Only Use

- Risk: The `tungstenite` WebSocket library is a full production dependency (not `dev-dependencies`), meaning it is compiled into `libgoose_core.a` and shipped in every release build, even though it is only used by the debug WebSocket server and the `goose-debug-ws-serve` binary tool.
- Impact: Increases binary size and attack surface unnecessarily in production builds.
- Migration plan: Move `debug_ws_server.rs` functionality behind a Cargo feature flag (e.g., `debug-ws-server`) and make `tungstenite` an optional dependency gated on that feature.

### Rust 2024 Edition + `rust-version = "1.94"` Requires Very Recent Toolchain

- Risk: `Cargo.toml` pins `edition = "2024"` and `rust-version = "1.94"`. As of this analysis date, Rust 1.94 is a release-candidate or very recent stable version. Any CI environment or developer machine running an older toolchain will fail to compile.
- Impact: New contributors without the exact toolchain will hit cryptic build errors.
- Migration plan: Document the required Rust version prominently in the README and add a `rust-toolchain.toml` file to the `Rust/core/` directory so `rustup` automatically selects the correct version.

---

## Test Coverage Gaps

### Zero Swift Unit or UI Tests

- What's not tested: All Swift-side logic — BLE packet parsing (`GooseBLEClient+Parsing.swift`), the overnight mirror queue flush/retry logic, the coach conversation state machine, onboarding persistence, and all data stores.
- Files: `GooseSwift/GooseBLEClient+Parsing.swift`, `GooseSwift/OvernightSQLiteMirrorQueue.swift`, `GooseSwift/OpenAICoachChat.swift`, `GooseSwift/OnboardingPersistence.swift`, `GooseSwift/HealthDataStore.swift`
- Risk: Regressions in BLE parsing or data store logic are only caught during live device testing.
- Priority: High — `GooseBLEClient+Parsing.swift` (961 lines) is the most critical untested path.

### `runReferenceComparisons()` Is a Stub

- What's not tested: `HealthDataStore.runReferenceComparisons()` sets all reference comparison statuses to `"blocked | real comparison inputs not wired"` and returns immediately. The HRV, sleep, strain, and stress reference comparison pipelines are not connected to actual data.
- Files: `GooseSwift/HealthDataStore+Snapshots.swift:54-58`
- Risk: Any refactor of the metric feature pipeline could break the intended reference comparison path with no failing test to signal it.
- Priority: Medium.

### No Integration Test for Schema Version Mismatch Recovery

- What's not tested: The behaviour when an app with `CURRENT_SCHEMA_VERSION = 14` opens a database written by a future version (e.g., 15). The `storage_check` reports this as an error, but there is no test confirming the app presents an actionable recovery path to the user rather than silently failing all bridge calls.
- Files: `Rust/core/src/storage_check.rs:91-98`, `GooseSwift/MoreDataStore.swift`
- Risk: A database schema mismatch silently breaks capture and scoring flows.
- Priority: High.

---

## Missing Critical Features

### No Offline Fallback for OpenAI Coach

- Problem: The coach feature (`OpenAICoachChat`, `CodexEmbeddedAuth`) requires live network access to `auth.openai.com` and `api.openai.com`. If the network is unavailable or the token has expired and cannot be refreshed, the coach shows an error with no cached or degraded mode.
- Blocks: Any offline or low-connectivity use of the coach.

### No App-Level Error Recovery UI for Bridge Failures

- Problem: When `GooseRustBridge` throws (e.g., `methodFailed`, `malformedResponse`), each call site individually updates a status string (e.g., `packetScoreStatus = "Bridge score run blocked: ..."`). There is no centralised error reporting, no retry mechanism, and no user-visible prompt to diagnose or recover from a persistent bridge failure.
- Files: `GooseSwift/HealthDataStore+Snapshots.swift:40`, `GooseSwift/MoreDataStore.swift`, `GooseSwift/OvernightSQLiteMirrorQueue.swift:243`

---

*Concerns audit: 2026-06-03*
