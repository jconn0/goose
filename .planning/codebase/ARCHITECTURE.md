<!-- refreshed: 2026-06-03 -->
# Architecture

**Analysis Date:** 2026-06-03

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                          SwiftUI Views                               │
│  HomeDashboardView  HealthView  CoachView  MoreView  OnboardingView │
│  `GooseSwift/Home*` `GooseSwift/Health*`  `GooseSwift/Coach*`       │
└──────────┬──────────────────┬───────────────────────────────────────┘
           │ @EnvironmentObject│ @StateObject
           ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  App Model Layer (@MainActor)                        │
│  GooseAppModel          HealthDataStore         AppRouter           │
│  `GooseSwift/GooseAppModel.swift`               `AppRouter.swift`   │
│  `GooseAppModel+*.swift`  `HealthDataStore+*.swift`                 │
└──────┬───────────────────────────┬────────────────────────────────┘
       │                           │ GooseRustBridge.request(method:)
       │                           ▼
┌──────▼──────────────────────────────────────────────────────────────┐
│    BLE Layer                     Rust Bridge (FFI)                   │
│  GooseBLEClient                  GooseRustBridge                    │
│  `GooseBLEClient.swift`          `GooseRustBridge.swift`            │
│  `GooseBLEClient+*.swift`        JSON over C FFI                    │
└──────┬───────────────────────────┬────────────────────────────────┘
       │ CoreBluetooth              │ goose_bridge_handle_json(cStr)
       ▼                            ▼
┌─────────────────┐   ┌────────────────────────────────────────────┐
│  WHOOP Device   │   │  Rust Core (libgoose_core)                  │
│  (BLE GATT)     │   │  `Rust/core/src/`                          │
│                 │   │  SQLite via rusqlite                        │
└─────────────────┘   └──────────────┬─────────────────────────────┘
                                      │
                                      ▼
                          ┌──────────────────────┐
                          │  goose.sqlite          │
                          │  ApplicationSupport/   │
                          │  GooseSwift/           │
                          └──────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `GooseSwiftApp` | App entry point; scene config; lifecycle events | `GooseSwift/GooseSwiftApp.swift` |
| `GooseAppModel` | Central coordinator; owns BLE client, Rust bridge, packet pipelines, overnight guard | `GooseSwift/GooseAppModel.swift` + `GooseAppModel+*.swift` |
| `GooseBLEClient` | CoreBluetooth central; WHOOP GATT connection; packet framing; command writes | `GooseSwift/GooseBLEClient.swift` + `GooseBLEClient+*.swift` |
| `GooseRustBridge` | JSON-over-FFI bridge to Rust; serialises requests, deserialises responses, tracks timing | `GooseSwift/GooseRustBridge.swift` |
| `HealthDataStore` | Rust bridge consumer for metric scores; @MainActor; owns packet input reports | `GooseSwift/HealthDataStore.swift` + `HealthDataStore+*.swift` |
| `AppRouter` | Tab selection, deep-link handling, navigation paths | `GooseSwift/AppRouter.swift` |
| `RootView` | Onboarding gate; renders either `OnboardingView` or `AppShellView` | `GooseSwift/RootView.swift` |
| `AppShellView` | Tab bar with Home/Health/Coach/More; creates `HealthDataStore` | `GooseSwift/AppShellView.swift` |
| `NotificationFrameParser` | Delegates raw BLE bytes to Rust for frame parsing; compact summary extraction | `GooseSwift/NotificationFrameParsing.swift` |
| `CaptureFrameWriteQueue` | Batched SQLite inserts of captured BLE frames via Rust bridge | `GooseSwift/CaptureFrameWriteQueue.swift` |
| `OvernightSQLiteMirrorQueue` | During overnight guard, queues raw notification rows → Rust bridge insert | `GooseSwift/OvernightSQLiteMirrorQueue.swift` |
| `WhoopDataSignalPipeline` | Ingests `WhoopDataSignalSample` on a dedicated queue; forwards to aggregators | `GooseSwift/WhoopDataSignalPipeline.swift` |
| `PassiveActivityDetectionPipeline` | Heuristic motion/HR analysis to auto-detect workout sessions | `GooseSwift/PassiveActivityDetector.swift` |
| `WorkoutLiveActivityController` | Manages `ActivityKit` Live Activity lifecycle for workouts | `GooseSwift/WorkoutLiveActivityController.swift` |
| Rust core (bridge) | Protocol parsing, SQLite persistence, metric algorithms, BLE frame import | `Rust/core/src/bridge.rs` (58+ dispatched methods) |
| `GooseWorkoutLiveActivityWidget` | WidgetKit / ActivityKit extension; renders Dynamic Island + lock-screen UI | `GooseWorkoutLiveActivityExtension/GooseWorkoutLiveActivityWidget.swift` |

## Pattern Overview

**Overall:** MVVM + event-driven pipelines, with a Rust core accessed exclusively via a JSON-RPC-style FFI bridge.

**Key Characteristics:**
- `GooseAppModel` is the single `@MainActor` coordinator; UI observes it via `@EnvironmentObject`.
- The Rust library (`libgoose_core`) is stateless from Swift's perspective; state is persisted in SQLite. Each bridge call passes the `database_path` argument.
- BLE bytes flow inward through callbacks on `GooseBLEClient`, are reassembled into frames on `notificationIngestQueue`, parsed via `GooseRustBridge`, then written to SQLite via `CaptureFrameWriteQueue`.
- Thread safety: `@MainActor` for all UI mutations; dedicated `DispatchQueue` instances for BLE, parse, write, and pipeline work; `NSLock` guards for shared counters.

## Layers

**View Layer:**
- Purpose: SwiftUI rendering, user interaction
- Location: `GooseSwift/` (all `*View.swift`, `*Views.swift`, `*Screen.swift`)
- Contains: SwiftUI `View` structs, view-local `@State`
- Depends on: `GooseAppModel`, `HealthDataStore`, `AppRouter` via `@EnvironmentObject`/`@StateObject`
- Used by: `AppShellView` tab builder

**App Model / Coordinator Layer:**
- Purpose: Business logic, state machine, pipeline wiring
- Location: `GooseSwift/GooseAppModel.swift` + `GooseAppModel+*.swift`
- Contains: `@MainActor final class GooseAppModel: ObservableObject`; all `@Published` state; extension files split by concern
- Depends on: `GooseBLEClient`, `GooseRustBridge`, dispatch queues, `NotificationFrameParser`, `CaptureFrameWriteQueue`
- Used by: `GooseSwiftApp`, SwiftUI views

**Data Store Layer:**
- Purpose: Query Rust bridge for scored metrics; publish results to views
- Location: `GooseSwift/HealthDataStore.swift` + `HealthDataStore+*.swift`
- Contains: `@MainActor final class HealthDataStore: ObservableObject`; owns a `GooseRustBridge` instance
- Depends on: `GooseRustBridge` (each method call passes `database_path`)
- Used by: `AppShellView` (creates one instance), view tabs

**BLE Layer:**
- Purpose: CoreBluetooth central manager; WHOOP GATT protocol; command writes and notifications
- Location: `GooseSwift/GooseBLEClient.swift` + `GooseBLEClient+*.swift`
- Contains: `CBCentralManagerDelegate`, `CBPeripheralDelegate`; proprietary WHOOP command framing
- Depends on: CoreBluetooth, OSLog
- Used by: `GooseAppModel` (holds the instance)

**FFI Bridge Layer:**
- Purpose: Type-safe JSON envelope around a C FFI function pair
- Location: `GooseSwift/GooseRustBridge.swift`, `GooseSwift/GooseSwift-Bridging-Header.h`
- Contains: `GooseRustBridge` class; calls `goose_bridge_handle_json` / `goose_bridge_free_string`
- Depends on: `Rust/core/include/goose_core_bridge.h` (two C symbols)
- Used by: `GooseAppModel` (one instance), `HealthDataStore` (own instance), `OvernightSQLiteMirrorQueue` (own instance), `CaptureFrameWriteQueue` (own instance), ad-hoc calls in extensions

**Rust Core:**
- Purpose: Protocol parsing, SQLite schema and persistence, metric feature extraction, health scoring algorithms
- Location: `Rust/core/src/`
- Contains: 40+ Rust modules; entry point `bridge.rs` dispatches JSON `method` strings to internal functions
- Depends on: `rusqlite`, `serde_json`, `serde`; writes to `goose.sqlite`
- Used by: Swift side only through the C FFI pair

**WidgetKit Extension:**
- Purpose: Live Activity (Dynamic Island + lock screen) for active workouts
- Location: `GooseWorkoutLiveActivityExtension/`
- Contains: `GooseWorkoutLiveActivityWidget`, `WorkoutLiveActivityAttributes` (shared type)
- Depends on: `ActivityKit`, `WidgetKit`; reads `WorkoutLiveActivityAttributes.ContentState` pushed from main app

## Data Flow

### Primary Real-Time BLE → SQLite Path

1. WHOOP device sends BLE notification → `CBPeripheralDelegate.peripheral(_:didUpdateValueFor:)` (`GooseBLEClient+PeripheralDelegate.swift`)
2. Raw bytes passed to `GooseAppModel.handleNotification(_:)` via `ble.onNotification` callback
3. Bytes queued on `notificationIngestQueue`; `notificationIngestResult(for:)` calls Rust bridge method `protocol.parse_notification_frame_batch` to reassemble and parse frames (`GooseAppModel+NotificationPipeline.swift`)
4. Parsed frames dispatched to `@MainActor handleNotificationIngestResult(_:)`; movement/event/data signal samples extracted
5. Frame rows enqueued in `CaptureFrameWriteQueue`; background queue drains them via Rust bridge method `capture.import_frame_batch` → writes to `goose.sqlite`
6. `GooseAppModel` publishes UI status updates via `packetUIStateAggregator` (coalesced at 200ms interval)

### Metric Score Path (on-demand)

1. `HealthDataStore.runPacketInputs()` dispatched on `packetInputQueue`
2. Each metric calls `GooseRustBridge.request(method: "metrics.*", args: ["database_path": ...])` — reads from `goose.sqlite`
3. Results returned as `[String: Any]`; stored in `packetInputReports`
4. Score methods (`runSleepScore`, `runRecoveryScore`, etc.) call further bridge methods using those reports as input
5. `@Published` properties updated on `@MainActor`; views re-render

### Overnight Guard Path

1. User starts Overnight Guard → `GooseAppModel.startOvernightGuard()`
2. `OvernightRawNotificationSpool` writes raw BLE notification bytes to disk (JSON lines)
3. `OvernightSQLiteMirrorQueue` batches rows → Rust bridge `overnight.upsert_raw_notifications` → `goose.sqlite`
4. Periodic range polls (`GET_DATA_RANGE` BLE command) track historical sync progress
5. On finish, `GooseLocalDataExporter` exports SQLite data and spool files

### Live Activity Path

1. Activity recording begins → `WorkoutLiveActivityController.start(attributes:)` (`WorkoutLiveActivityController.swift`)
2. Main app updates Live Activity state via `Activity<WorkoutLiveActivityAttributes>.update()`
3. `GooseWorkoutLiveActivityWidget` renders `ContentState` updates in Dynamic Island and lock screen (separate process)

**State Management:**
- All observable state lives in `GooseAppModel` and `HealthDataStore` as `@Published` properties on `@MainActor`
- Navigation state lives in `AppRouter`
- Persistence: `UserDefaults` for onboarding/device identity/HR estimates; `goose.sqlite` for all health/packet data; `ApplicationSupport/GooseSwift/` for database and logs; `Documents/GooseSwift/` for user-accessible exports

## Key Abstractions

**GooseRustBridge:**
- Purpose: JSON-RPC envelope over a single C function `goose_bridge_handle_json`. Schema: `goose.bridge.request.v1` with `method` + `args`. Rust returns `{ok, result, error, timing}`.
- Examples: `GooseSwift/GooseRustBridge.swift` (lines 26–81)
- Pattern: Each caller creates its own bridge instance; bridge is stateless. Always pass `database_path` in args for storage-backed methods.

**GooseBLEClient extensions:**
- Purpose: Large class split into focused extension files by concern
- Examples: `GooseBLEClient+Commands.swift`, `GooseBLEClient+HistoricalCommands.swift`, `GooseBLEClient+Parsing.swift`, `GooseBLEClient+PeripheralDelegate.swift`
- Pattern: Each extension file owns a coherent slice of BLE behaviour; all share state on the parent class

**GooseAppModel extensions:**
- Purpose: Coordinator split across extension files by domain
- Examples: `GooseAppModel+NotificationPipeline.swift`, `GooseAppModel+ActivityRecording.swift`, `GooseAppModel+OvernightRun.swift`
- Pattern: Concern-scoped extensions on `@MainActor` class; background queue work dispatches back to main via `Task { @MainActor in ... }`

**HealthDataStore extensions:**
- Purpose: Query layer split by metric family
- Examples: `HealthDataStore+PacketInputs.swift`, `HealthDataStore+Snapshots.swift`, `HealthDataStore+Sleep.swift`, `HealthDataStore+Cardio.swift`
- Pattern: Each extension calls `bridge.request(method: "metrics.*")` with `database_path` arg; updates `@Published` state

**WorkoutLiveActivityAttributes:**
- Purpose: Shared type between main app and WidgetKit extension (ActivityKit contract)
- Examples: `GooseSwift/WorkoutLiveActivityAttributes.swift`
- Pattern: `ActivityAttributes` conformance; `ContentState` carries mutable workout metrics

## Entry Points

**GooseSwiftApp:**
- Location: `GooseSwift/GooseSwiftApp.swift`
- Triggers: iOS app launch (`@main`)
- Responsibilities: Creates `GooseAppModel` and `AppRouter` as `@StateObject`; injects into environment; handles `scenePhase` changes and deep links

**GooseWorkoutLiveActivityBundle:**
- Location: `GooseWorkoutLiveActivityExtension/GooseWorkoutLiveActivityWidget.swift`
- Triggers: WidgetKit extension process launch
- Responsibilities: Declares `GooseWorkoutLiveActivityWidget` for ActivityKit

## Architectural Constraints

- **Threading:** Main thread (`@MainActor`) for all UI and `@Published` state mutations. Background `DispatchQueue` instances for BLE events, notification parsing, frame row building, packet input computation, and overnight mirror writes. `NSLock` used for counters shared between queues.
- **Global state:** `HeartRateSeriesStore.shared` is a module-level singleton (`GooseSwift/HeartRateSeriesStores.swift`). All other state is instance-owned.
- **Rust bridge is synchronous:** `goose_bridge_handle_json` blocks the calling thread. Never call from `@MainActor` with expensive methods; always dispatch to a background queue first.
- **Database path convention:** The SQLite file is always at `ApplicationSupport/GooseSwift/goose.sqlite`, resolved via `HealthDataStore.defaultDatabasePath()`. Pass this path explicitly in every bridge call that needs storage.
- **Multiple bridge instances:** `GooseRustBridge` is not a singleton; `GooseAppModel`, `HealthDataStore`, `OvernightSQLiteMirrorQueue`, and `CaptureFrameWriteQueue` each hold their own instance. This is intentional — the Rust side is stateless across calls.
- **Circular imports:** None detected.
- **Extension target isolation:** `GooseWorkoutLiveActivityExtension` shares `WorkoutLiveActivityAttributes.swift` with the main target. It has no access to `GooseAppModel` or `GooseRustBridge`.

## Anti-Patterns

### Calling GooseRustBridge from @MainActor inline

**What happens:** Some ad-hoc bridge calls (e.g., in `GooseAppModel+HealthCapture.swift` and `GooseAppModel+ActivityTimeline.swift`) instantiate `GooseRustBridge()` inside a background queue closure while the queue captures model state.
**Why it's wrong:** If called without a background queue, it blocks the main thread during FFI + JSON serialisation, causing UI hitches and timing log warnings (`elapsedMS >= 50`).
**Do this instead:** Dispatch to a dedicated background queue before constructing the bridge and calling `request(method:)`, then dispatch results back to `@MainActor` — as `GooseAppModel+ActivityTimeline.swift` and `HealthDataStore+PacketInputs.swift` already do.

### Constructing ad-hoc GooseRustBridge() per call site

**What happens:** `GooseAppModel+HealthCapture.swift` and `GooseAppModel+ActivityTimeline.swift` create `GooseRustBridge()` inline in queue closures.
**Why it's wrong:** There is no shared instance to track timing or enforce serialisation; slightly wasteful.
**Do this instead:** Pass the model's existing `self.rust` instance into the closure via capture, or use the store's `bridge` property.

## Error Handling

**Strategy:** `GooseRustBridge.request` throws `GooseRustBridgeError`; callers use `do/catch` and surface errors as status strings on `@Published` properties.

**Patterns:**
- Bridge failures set human-readable status strings (e.g., `catalogStatus = "Metric catalog unavailable: \(error)"`)
- BLE errors are logged via `ble.record(level: .error, ...)` and update `connectionState`
- Overnight guard errors accumulate as warning strings in `overnightGuardWarning` and `overnightGuardStatus`

## Cross-Cutting Concerns

**Logging:** `ble.record(level:source:title:body:)` on `GooseBLEClient` is used throughout the app as a structured event log. Entries appear in `GooseMessageStore` (in-memory ring buffer, max 300) and optionally in `goose-ble.log` on disk. OSLog is also used in `GooseBLEClient` via `Logger(subsystem:category:)`.
**Validation:** Rust bridge validates data on the Rust side; Swift side validates bridge response shape (`ok`, `result` keys).
**Authentication:** Codex/OpenAI coach auth via OAuth deep link (`gooseswift://codex-auth`); token handled in `CodexEmbeddedAuth.swift`.

---

*Architecture analysis: 2026-06-03*
