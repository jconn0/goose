# Codebase Structure

**Analysis Date:** 2026-06-03

## Directory Layout

```
goose/                                      # Repo root
├── GooseSwift/                             # Main iOS app target (Swift sources + assets)
│   ├── GooseSwiftApp.swift                 # @main entry point
│   ├── GooseAppModel.swift                 # Central coordinator (@MainActor ObservableObject)
│   ├── GooseAppModel+*.swift               # Domain extensions (9 files)
│   ├── GooseBLEClient.swift                # CoreBluetooth central manager
│   ├── GooseBLEClient+*.swift              # BLE extensions (9 files)
│   ├── GooseRustBridge.swift               # FFI bridge to Rust core
│   ├── GooseSwift-Bridging-Header.h        # Imports goose_core_bridge.h
│   ├── HealthDataStore.swift               # Metric query store (@MainActor ObservableObject)
│   ├── HealthDataStore+*.swift             # Store extensions (10 files)
│   ├── AppRouter.swift                     # Navigation state
│   ├── AppShellView.swift                  # Tab bar shell (Home/Health/Coach/More)
│   ├── RootView.swift                      # Onboarding gate
│   ├── Home*.swift                         # Home tab views and models
│   ├── Health*.swift                       # Health tab views and models
│   ├── Coach*.swift                        # AI coach tab views and models
│   ├── More*.swift                         # Settings/debug tab views and models
│   ├── Onboarding*.swift                   # Onboarding flow views and models
│   ├── Sleep*.swift / SleepV2*.swift       # Sleep detail views
│   ├── Fitness*.swift                      # Fitness/workout views
│   ├── Activity*.swift                     # Activity recording and session models
│   ├── Workout*.swift                      # Workout live activity models and controller
│   ├── WorkoutLiveActivityAttributes.swift # Shared ActivityKit type (also used by extension)
│   ├── Overnight*.swift                    # Overnight guard spool and mirror queue
│   ├── Whoop*.swift                        # WHOOP data signal pipeline and event samples
│   ├── *Pipeline*.swift                    # Data pipelines (WhoopDataSignal, PassiveActivity)
│   ├── *Aggregator*.swift                  # UI state aggregators (coalesced publishing)
│   ├── *Store.swift                        # Other stores (HealthDataStore, GooseMessageStore, MoreDataStore, HeartRateSeriesStore)
│   ├── Packet*.swift                       # Packet monitor and UI state types
│   ├── Notification*.swift                 # BLE notification frame parsing
│   ├── CaptureFrameWriteQueue.swift        # Batched SQLite frame writes
│   ├── GooseLocalDataExporter*.swift       # Export helpers (filesystem, metrics, validation)
│   ├── GooseTheme.swift                    # Appearance configuration
│   ├── GooseHello.swift                    # WHOOP client-hello handshake helpers
│   ├── GooseSwift.entitlements             # App entitlements
│   ├── Info.plist
│   └── Assets.xcassets/                   # App icons, images
├── GooseWorkoutLiveActivityExtension/      # WidgetKit / ActivityKit extension target
│   ├── GooseWorkoutLiveActivityWidget.swift # @main for extension; Dynamic Island + lock screen
│   └── Info.plist
├── Rust/
│   └── core/                              # Rust library crate
│       ├── Cargo.toml
│       ├── src/
│       │   ├── lib.rs                     # Module declarations; re-exports GooseError/GooseResult
│       │   ├── bridge.rs                  # C FFI exports + JSON dispatch (goose_bridge_handle_json)
│       │   ├── store.rs                   # SQLite schema (v14), CRUD operations via rusqlite
│       │   ├── protocol.rs                # BLE frame parsing (ParsedFrame, DeviceType)
│       │   ├── metrics.rs                 # Algorithm definitions (sleep/recovery/strain/stress/HRV)
│       │   ├── metric_features.rs         # Feature extraction runners
│       │   ├── metric_readiness.rs        # Input readiness checks
│       │   ├── capture_import.rs          # Frame batch import to SQLite
│       │   ├── activity_sessions.rs       # Activity session storage and correction
│       │   ├── historical_sync.rs         # Historical data sync dry-run and validation
│       │   ├── health_sync.rs             # HealthKit sync dry-run helpers
│       │   ├── energy_rollup.rs           # Daily/hourly energy rollup
│       │   ├── recovery_rollup.rs         # Recovery sensor rollup
│       │   ├── sleep_validation.rs        # Sleep data validation
│       │   ├── algorithm_compare.rs       # Algorithm A/B comparison
│       │   ├── calibration.rs             # Metric calibration records
│       │   ├── export.rs                  # Raw export filtering and bundle validation
│       │   ├── debug_ws.rs / debug_ws_server.rs # WebSocket debug server
│       │   ├── step_counter.rs / step_discovery.rs / step_motion_estimator.rs
│       │   ├── timeline.rs                # Activity timeline queries
│       │   ├── commands.rs                # BLE command definitions and validation
│       │   ├── fixtures.rs                # Test fixture helpers
│       │   └── ...                        # ~15 more modules
│       ├── include/
│       │   └── goose_core_bridge.h        # C header: goose_bridge_handle_json, goose_bridge_free_string
│       └── fixtures/                      # Owned and synthetic test fixture data
├── Packages/
│   ├── WhoopProtocol/                     # Local Swift package (no Package.swift found — likely embedded)
│   └── WhoopStore/                        # Local Swift package (no Package.swift found — likely embedded)
├── GooseSwift.xcodeproj/                  # Xcode project
├── build/                                 # Build outputs (not committed)
├── docs/                                  # Project documentation and evidence
│   ├── goose-swift-mvp/
│   └── assets/
├── Scripts/                               # Build or utility scripts
├── .planning/                             # GSD planning documents (committed)
│   └── codebase/                          # Codebase map documents
├── README.md
└── recovery-todo.md
```

## Directory Purposes

**`GooseSwift/`:**
- Purpose: All Swift source for the main iOS app target
- Contains: Entry point, view hierarchy, app model, BLE client, Rust bridge, data stores, pipelines, overnight guard, onboarding, export helpers, assets
- Key files: `GooseSwiftApp.swift`, `GooseAppModel.swift`, `GooseRustBridge.swift`, `GooseBLEClient.swift`, `HealthDataStore.swift`

**`GooseWorkoutLiveActivityExtension/`:**
- Purpose: Separate WidgetKit/ActivityKit extension process; renders Live Activity UI
- Contains: One widget file; reads `WorkoutLiveActivityAttributes` pushed from main app
- Key files: `GooseWorkoutLiveActivityWidget.swift`

**`Rust/core/src/`:**
- Purpose: The Rust library that does all computation and storage
- Contains: FFI bridge dispatcher (`bridge.rs`), SQLite layer (`store.rs`), protocol parser (`protocol.rs`), metric algorithms, and domain modules
- Key files: `bridge.rs`, `store.rs`, `lib.rs`, `protocol.rs`, `metrics.rs`

**`Rust/core/include/`:**
- Purpose: C header that Swift imports via bridging header
- Key files: `goose_core_bridge.h` — declares `goose_bridge_handle_json` and `goose_bridge_free_string`

**`Rust/core/target/`:**
- Purpose: Rust build artifacts (not committed)
- Generated: Yes
- Committed: No

**`Packages/`:**
- Purpose: Local Swift packages (`WhoopProtocol`, `WhoopStore`) — appear to be embedded without their own `Package.swift` at the scanned location
- Generated: No
- Committed: Yes

**`build/`:**
- Purpose: Build outputs
- Generated: Yes
- Committed: No

**`.planning/codebase/`:**
- Purpose: GSD codebase map documents consumed by `/gsd-plan-phase` and `/gsd-execute-phase`
- Generated: By GSD tooling
- Committed: Yes

## Key File Locations

**Entry Points:**
- `GooseSwift/GooseSwiftApp.swift`: iOS app `@main`
- `GooseWorkoutLiveActivityExtension/GooseWorkoutLiveActivityWidget.swift`: WidgetKit extension `@main`

**Rust FFI Boundary:**
- `Rust/core/include/goose_core_bridge.h`: C header (2 symbols)
- `GooseSwift/GooseSwift-Bridging-Header.h`: Swift bridging header (imports above)
- `GooseSwift/GooseRustBridge.swift`: Swift wrapper class

**Rust Core:**
- `Rust/core/src/bridge.rs`: JSON dispatch router (all bridge methods defined here)
- `Rust/core/src/store.rs`: SQLite schema and persistence (schema v14)
- `Rust/core/src/lib.rs`: Crate root and module declarations

**App Coordinator:**
- `GooseSwift/GooseAppModel.swift`: Base class declaration + constants
- `GooseSwift/GooseAppModel+NotificationPipeline.swift`: BLE notification ingest pipeline
- `GooseSwift/GooseAppModel+ActivityRecording.swift`: Activity session begin/finish
- `GooseSwift/GooseAppModel+OvernightRun.swift`: Overnight guard start/stop
- `GooseSwift/GooseAppModel+Lifecycle.swift`: `scenePhase` and deep-link handlers

**BLE Client:**
- `GooseSwift/GooseBLEClient.swift`: Class declaration, UUIDs, command kinds, constants
- `GooseSwift/GooseBLEClient+PeripheralDelegate.swift`: GATT service/characteristic discovery, notification handling
- `GooseSwift/GooseBLEClient+Commands.swift`: Command write helpers
- `GooseSwift/GooseBLEClient+HistoricalCommands.swift`: GET_DATA_RANGE, SEND_HISTORICAL_DATA

**Data Stores:**
- `GooseSwift/HealthDataStore.swift`: Metric catalog load, packet input orchestration
- `GooseSwift/HealthDataStore+PacketInputs.swift`: All `metrics.*` bridge calls (20+ methods)
- `GooseSwift/HealthDataStore+Snapshots.swift`: Score runs (strain, recovery, stress)
- `GooseSwift/MoreDataStore+Validation.swift`: Validation and audit bridge calls

**Shared ActivityKit Type:**
- `GooseSwift/WorkoutLiveActivityAttributes.swift`: `ActivityAttributes` struct shared between main target and extension

**Database Path:**
- Resolved at runtime: `ApplicationSupport/GooseSwift/goose.sqlite`
- Canonical resolver: `HealthDataStore.defaultDatabasePath()` (`GooseSwift/HealthDataStore.swift:74`)

## Naming Conventions

**Files:**
- `TypeName.swift` — primary type definition
- `TypeName+Concern.swift` — extension file adding a cohesive slice of behaviour (e.g., `GooseAppModel+OvernightRun.swift`)
- `*Views.swift` — SwiftUI view collections (multiple views in one file)
- `*Types.swift` — type declarations without behaviour
- `*Models.swift` — model structs/classes
- `*Store.swift` — data store classes
- `*Pipeline.swift` — background processing pipelines

**Directories:**
- `GooseSwift/` — flat; no subdirectory grouping by feature

**Types:**
- Classes: PascalCase, descriptive noun (`GooseBLEClient`, `HealthDataStore`)
- Extensions: `extension TypeName { }` in `TypeName+Concern.swift`
- Enums: PascalCase; cases camelCase
- Protocols: Not widely used; `CBCentralManagerDelegate` / `CBPeripheralDelegate` via extension on `GooseBLEClient`

**Rust modules:**
- `snake_case.rs` files; module names match the domain (e.g., `metric_features`, `capture_import`)

## Where to Add New Code

**New SwiftUI view:**
- Implementation: `GooseSwift/FeatureNameView.swift` (or `FeatureNameViews.swift` if multiple)
- Follow existing views: use `@EnvironmentObject private var model: GooseAppModel` and `@EnvironmentObject private var router: AppRouter`

**New GooseAppModel behaviour:**
- Create `GooseSwift/GooseAppModel+NewConcern.swift` as an extension on `GooseAppModel`
- Keep `@MainActor` constraint; dispatch heavy work to named `DispatchQueue` and callback via `Task { @MainActor in ... }`

**New Rust bridge method (Swift side):**
- Add call site in the appropriate extension file (`HealthDataStore+*.swift` for metric queries, `GooseAppModel+*.swift` for pipeline operations)
- Always pass `database_path` from `HealthDataStore.defaultDatabasePath()` for storage-backed methods
- Dispatch on a background queue; never call from `@MainActor` directly

**New Rust bridge method (Rust side):**
- Add match arm in `Rust/core/src/bridge.rs` dispatch block
- Implement logic in the appropriate domain module under `Rust/core/src/`
- Export type in `Rust/core/src/lib.rs` if needed

**New BLE command:**
- Add command kind to `GooseBLEClient.SensorStreamCommandKind` or create a new enum in `GooseBLEClient.swift`
- Implement send logic in `GooseSwift/GooseBLEClient+Commands.swift`
- Add response handler in `GooseSwift/GooseBLEClient+Parsing.swift` or `GooseBLEClient+PeripheralDelegate.swift`

**New tab:**
- Add case to `GooseAppTab` enum in `GooseSwift/AppShellView.swift`
- Add `tabContent(for:)` case in `AppShellView`
- Add routing in `AppRouter` if deep-link navigation is needed

**New data store:**
- Create `GooseSwift/FeatureDataStore.swift` as `@MainActor final class FeatureDataStore: ObservableObject`
- Follow `HealthDataStore` pattern: own a `GooseRustBridge` instance; dispatch bridge calls on a background queue; publish results via `@Published`

**Utilities / helpers:**
- Shared formatting helpers: `GooseSwift/FitnessFormatting.swift`, `GooseSwift/HomeFormatting.swift` (extend or create analogous file)
- Theme: `GooseSwift/GooseTheme.swift`

## Special Directories

**`Rust/core/fixtures/`:**
- Purpose: Test fixture data (owned captures and synthetic data for Rust unit tests)
- Generated: Partially (synthetic); owned data is captured from real devices
- Committed: Yes

**`GooseSwift/Assets.xcassets/`:**
- Purpose: App icons and image assets
- Generated: No
- Committed: Yes

**`build/`:**
- Purpose: Rust and Xcode build artefacts
- Generated: Yes
- Committed: No (in `.gitignore`)

---

*Structure analysis: 2026-06-03*
