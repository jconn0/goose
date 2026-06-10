# Phase 49: HealthDataStore Async Migration — Research

**Researched:** 2026-06-10
**Domain:** Swift Concurrency migration — @MainActor @Observable class with GCD dispatch queues → async/await
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Make `GooseRustBridge.requestValue` (and by extension `request`) an `async throws` function. Internally, the sync FFI call (`goose_bridge_handle_json`) runs inside `Task.detached(priority: .userInitiated) { ... }.value`. This ensures the FFI never executes on @MainActor even when called from @MainActor context.
- **D-02:** `HealthDataStore` remains `@MainActor @Observable`. No annotation change. The suspension points in `await bridge.request(...)` cause the runtime to hop to a worker thread for the FFI, then return to @MainActor for @Observable property mutations.
- **D-03:** All `refresh*` / `run*` methods in HealthDataStore that call the bridge become `async func`. Their callers (e.g., `refreshBridgeCatalogs()` called from `AppShellView`) wrap them in `Task { await store.refreshBridgeCatalogs() }`.
- **D-04:** All 60+ call sites in `HealthDataStore.swift` and all `HealthDataStore+*.swift` files are migrated. Zero occurrences of `bridge.request` or `bridge.requestValue` without `await` in the final state.
- **D-05:** `packetInputQueue` and `heartRateTimelineQueue` are removed from `HealthDataStore.swift` after migration. No retained dead code.
- **D-06:** Wave-per-file approach: Plan 1 modifies `GooseRustBridge.swift` (adds async variant); subsequent plans group `HealthDataStore+*.swift` files with zero inter-plan file overlap. Each plan builds and compiles cleanly before the next begins.
- **D-07:** For each extension file: replace `packetInputQueue.async { ... bridge.request(...) ... DispatchQueue.main.async { self.x = result } }` with `async func refreshX() { ... let r = try await bridge.request(...) ... self.x = result }` (direct @MainActor mutation after `await` is safe).
- **D-08:** Verification is: (a) `xcodebuild build` with zero errors and zero Swift Concurrency warnings; (b) launch in iOS Simulator and confirm Recovery V2, Sleep V2, and Esforço dashboards populate with data after a bridge call is triggered.

### Claude's Discretion

- Exact batching of HealthDataStore+*.swift files into plans (group by logical area, e.g., Cardio+Recovery together, Sleep+StagingSleep together).
- Whether to introduce a `nonisolated` wrapper on GooseRustBridge or use the existing instance — implementer chooses what compiles cleanly.
- Whether to add a `requestAsync` method alongside the existing sync `request`, or replace it — implementer decides based on migration strategy (additive is safer for wave migration).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ASYNC-01 | Todos os 60+ call sites de bridge em `HealthDataStore` (9 ficheiros Swift) são convertidos para `async`/`await` num background actor — zero chamadas síncronas Rust na `@MainActor` | D-01, D-04, D-06: additive requestAsync + wave-per-file strategy; actual count is 41 bridge calls across 8 files with bridge calls + HealthDataStore.swift (3 calls) |
| ASYNC-02 | A UI continua a actualizar correctamente após a migração — nenhum freeze de main thread, dashboards respondem normalmente | D-02, D-07: @MainActor property mutation after `await` is safe because HealthDataStore stays @MainActor; callers wrap in Task{} |
</phase_requirements>

---

## Summary

Phase 49 migrates all bridge FFI calls in `HealthDataStore` and its extension files from GCD dispatch queues to Swift Concurrency. The core mechanism: `GooseRustBridge` gains an additive async method (`requestAsync`) that wraps the existing sync `requestValue` inside `Task.detached(priority: .userInitiated) { }.value`. Since `GooseRustBridge` is already `@unchecked Sendable`, this compiles cleanly. `HealthDataStore` keeps its `@MainActor @Observable` annotation — after an `await bridge.requestAsync(...)`, Swift automatically hops back to @MainActor for property mutations.

The actual bridge call count is **41 total** across files (not 60+): 3 in `HealthDataStore.swift` + 21 in `+PacketInputs.swift` (static nonisolated method with its own bridge instance) + 17 in 6 other extension files. Additionally, `+Cardio.swift` has 2 **direct** (non-queued) bridge calls on @MainActor — these are a higher-priority risk item. Files with no bridge calls (ActivitySnapshots, CoachSummaries, Sleep, StaticSnapshots, StressEnergy, Trends, Vitals) require no migration work.

**Primary recommendation:** Use the additive approach — add `requestAsync` to `GooseRustBridge` in Plan 1, then migrate files one logical group per plan. Final cleanup plan removes the sync variants and `packetInputQueue`/`heartRateTimelineQueue`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| FFI bridge async wrapper | `GooseRustBridge` | — | Bridge owns the execution model; callers just `await` |
| @Observable property mutations | @MainActor (`HealthDataStore`) | — | @Observable requires actor-isolated mutations; after `await`, Swift is back on @MainActor |
| Bridge call dispatch | Task.detached (worker thread) | — | FFI is sync and blocking; must not run on @MainActor or cooperative thread pool |
| Caller wrapping | SwiftUI views / GooseAppModel | HealthDataStore | Views call `Task { await store.runX() }` — same as existing `Task { @MainActor in }` pattern already in codebase |

---

## Standard Stack

### Core (no new dependencies)
| Component | Current State | Migration Target |
|-----------|--------------|-----------------|
| `GooseRustBridge` | `final class @unchecked Sendable` | Add `requestAsync` as `async throws -> [String: Any]` wrapping `Task.detached { requestValue(...) }.value` |
| `HealthDataStore` | `@MainActor @Observable final class` | No annotation change; `run*`/`refresh*` methods become `async func` |
| `packetInputQueue` | `DispatchQueue(label:qos:.utility)` | Remove after all call sites migrated |
| `heartRateTimelineQueue` | `DispatchQueue(label:qos:.utility)` | Remove after all call sites migrated (only used in `refreshHeartRateTimeline`) |
| `packetInputBridgeReports` | `nonisolated static` with own `GooseRustBridge()` | Becomes `nonisolated static async` — callers `await` it |

**No new packages.** This is a pure concurrency model migration with zero external dependencies.

---

## Architecture Patterns

### System Architecture Diagram

```
SwiftUI View (.onAppear / .onChange / Button)
    │
    │  Task { await store.runX() }    ← NEW: wraps previously sync calls
    ▼
HealthDataStore (@MainActor @Observable)
    │
    │  let result = try await bridge.requestAsync(method:args:)
    │                    ↑ suspension point — leaves @MainActor
    ▼
GooseRustBridge.requestAsync()
    │
    │  Task.detached(priority: .userInitiated) { self.requestValue(...) }.value
    │                    ↑ runs on worker thread (concurrent pool)
    ▼
goose_bridge_handle_json()   ← blocking C FFI call, NOT on @MainActor
    │
    │  returns
    ▼
GooseRustBridge.requestAsync()  ← .value suspends until Task.detached completes
    │
    │  returns decoded result
    ▼
HealthDataStore (@MainActor @Observable)
    │
    │  self.someProperty = result    ← SAFE: back on @MainActor after await
    ▼
SwiftUI re-renders
```

### Recommended Project Structure (unchanged)
```
GooseSwift/
├── GooseRustBridge.swift         # Plan 1: add requestAsync
├── HealthDataStore.swift         # Plan-final: remove queues, migrate refreshBridgeCatalogs+runPacketInputs
├── HealthDataStore+PacketInputs.swift  # Plan 2: migrate static nonisolated (async) + 21 calls
├── HealthDataStore+Snapshots.swift     # Plan 3: 5 calls, 2 queued functions
├── HealthDataStore+Recovery.swift      # Plan 3: 1 call, 1 queued function
├── HealthDataStore+StagingSleep.swift  # Plan 4: 1 call, 1 queued function
├── HealthDataStore+Readiness.swift     # Plan 4: 2 calls, 1 queued function
├── HealthDataStore+Exercise.swift      # Plan 5: 1 call, 1 queued function
├── HealthDataStore+IMUSteps.swift      # Plan 5: 2 calls, 1 queued function
├── HealthDataStore+V24Biometrics.swift # Plan 5: 2 calls (incl. try?), 1 queued function
├── HealthDataStore+Cardio.swift        # Plan 6: 2 DIRECT calls (no queue!) — highest risk
├── HealthDataStore+Utilities.swift     # Plan 6: 1 call in helpers pattern
```

### Pattern 1: requestAsync in GooseRustBridge (additive)

**What:** Add `requestAsync` alongside the existing sync `request`/`requestValue`. Migration can proceed file-by-file without breaking others.

```swift
// Source: [ASSUMED] Swift Concurrency docs — Task.detached for sync-FFI wrapping
func requestAsync(method: String, args: [String: Any] = [:]) async throws -> [String: Any] {
  try await Task.detached(priority: .userInitiated) {
    try self.requestValue(method: method, args: args) as? [String: Any] ?? [:]
  }.value
}
```

Note: `self` capture works because `GooseRustBridge` is `@unchecked Sendable`. The `counter` and `lastTiming` mutation inside `requestValue` runs on the detached task's thread — this is safe because each HealthDataStore instance has its own bridge instance (no shared state). However, `lastTiming` access from `@MainActor` after the async call is now technically a data race (the property is written on a worker thread). **Resolution:** Mark `lastTiming` as `nonisolated(unsafe)` OR remove it after migration if not used from @MainActor. This is a discretion call for the implementer.

### Pattern 2: async func migration for run*/refresh* methods

**What:** Each method that currently does `packetInputQueue.async { ... DispatchQueue.main.async { self.x = r } }` becomes:

```swift
// Source: [ASSUMED] Swift Evolution SE-0296, SE-0306 — @MainActor + async mutation
func runRecoveryV1() async {
  let db = databasePath            // @MainActor property — captured before suspension
  let hrv = ...                    // other @MainActor state captured synchronously
  do {
    let report = try await bridge.requestAsync(method: "metrics.goose_recovery_v1", args: bridgeArgs)
    // After await, back on @MainActor — safe to mutate @Observable properties directly
    self.recoveryV1Result = parseResult(report)
  } catch {
    self.recoveryV1Result = nil
  }
}
```

**Key rule:** All `@MainActor` property reads (e.g., `databasePath`, `packetInputReports`, `packetScoreReports`) must be captured **before** the first `await`. After the first `await`, there is an implicit actor hop but Swift re-enters @MainActor — the properties remain accessible safely after the await too, since HealthDataStore is @MainActor.

### Pattern 3: Caller migration for sync→async methods

**What:** SwiftUI `.onAppear`, `.onChange`, and closure callbacks that call `store.runX()` synchronously must wrap in `Task { }`.

```swift
// BEFORE
.onAppear {
  store.runPacketScores()
  store.runRecoveryV1()
}

// AFTER
.onAppear {
  Task {
    await store.runPacketScores()
    await store.runRecoveryV1()   // sequential or can be concurrent with async let
  }
}
```

For `AppShellView.onHistoricalSyncCompleted` (a `(() -> Void)?` closure):

```swift
// BEFORE
model.onHistoricalSyncCompleted = {
  healthStore.runPacketInputs()
}

// AFTER
model.onHistoricalSyncCompleted = {
  Task {
    await healthStore.runPacketInputs()
  }
}
```

### Pattern 4: Static nonisolated async (PacketInputs)

`packetInputBridgeReports` is `nonisolated static` with its **own** `GooseRustBridge()` instance. It makes 21 sequential bridge calls.

```swift
// AFTER: nonisolated static async
nonisolated static func packetInputBridgeReports(databasePath: String) async -> Result<[String: [String: Any]], Error> {
  let bridge = GooseRustBridge()
  do {
    var reports: [String: [String: Any]] = [:]
    reports["readiness"] = try await bridge.requestAsync(method: "metrics.input_readiness", args: ...)
    // ... 20 more sequential awaits
    return .success(reports)
  } catch {
    return .failure(error)
  }
}
```

The caller in `runPacketInputs` (in `HealthDataStore.swift`) becomes:

```swift
func runPacketInputs(completion: (() -> Void)? = nil) async {
  // ... guard, setup
  let result = await HealthDataStore.packetInputBridgeReports(databasePath: databasePath)
  switch result {
  case .success(let reports):
    self.packetInputReports = reports  // @MainActor — safe after await
    self.packetInputStatus = "Bridge packet-derived inputs extracted"
  case .failure(let error):
    self.packetInputStatus = "Bridge input extraction blocked: ..."
  }
  completion?()
}
```

Note: The `completion: (() -> Void)?` parameter remains for `refreshSleepAfterBandSync`. After migration, `refreshSleepAfterBandSync` becomes async and calls `await runPacketInputs()` directly without the closure.

### Pattern 5: Cardio direct bridge calls (RISK ITEM)

`cardioLoadActivitySessions` and `cardioLoadActivityMetricsByName` call `bridge.request` **directly** with no queue dispatch:

```swift
func cardioLoadActivitySessions(from start: Date, to end: Date) -> [[String: Any]] {
  do {
    let report = try bridge.request(...)   // DIRECT @MainActor call — blocks main thread
    return report["sessions"] as? ...
  } catch { return [] }
}
```

These are called from `cardioLoadAlgorithmSummary` which is called from `cardioLoadSnapshot` and other pure view-data methods. Neither is called externally (no callers found outside +Cardio.swift). The migration makes them `async` too — callers in the Cardio computation chain must also become async, propagating up.

**Risk:** This is the only pattern in the codebase where bridge calls are NOT wrapped in a queue — they run synchronously on @MainActor. The async migration here eliminates an **actual** main-thread block (not just architectural cleanup).

### Anti-Patterns to Avoid

- **Calling `requestValue` (sync) from async context**: After Plan 1, only `requestAsync` should be used in HealthDataStore files. The sync `request`/`requestValue` are not removed until the final cleanup plan.
- **Capturing @MainActor properties inside Task.detached**: Don't do `Task.detached { let x = abasePath }` — capture before the detach.
- **Using `DispatchQueue.main.async` after migration**: The old `DispatchQueue.main.async { self.x = r }` pattern must be fully replaced. Mixing async/await with legacy GCD on the same property is a data race.
- **Making heartRateTimelineQueue calls async**: `refreshHeartRateTimeline` uses `heartRateTimelineQueue` but doesn't call the bridge — it calls `heartRateSeriesStore.timelineSnapshot()` which is in-memory. This method can be migrated to async separately without touching bridge calls.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Running FFI on non-main thread | Custom GCD queue management | `Task.detached(priority:) { }.value` — Swift runtime manages thread pool |
| @MainActor property update after background work | `DispatchQueue.main.async { }` | Direct `self.prop = r` after `await` — Swift guarantees @MainActor re-entry |
| Cancellation | Manual `DispatchWorkItem.cancel()` | Swift structured concurrency `Task { }` — callers can hold `Task` reference for cancellation |

---

## Complete Call Site Inventory

### HealthDataStore.swift (3 bridge calls — base class)

| Line | Method | Pattern | Function to migrate |
|------|--------|---------|-------------------|
| 218 | `metrics.built_in_definitions` | `packetInputQueue.async { }` | `refreshBridgeCatalogs()` |
| 219 | `metrics.reference_definitions` | `packetInputQueue.async { }` | `refreshBridgeCatalogs()` |
| 220 | `metrics.default_preferences` | `packetInputQueue.async { }` | `refreshBridgeCatalogs()` |

Also: `runPacketInputs()` (line 277) dispatches to `packetInputQueue` and calls `packetInputBridgeReports` — the static method in +PacketInputs.

### HealthDataStore+PacketInputs.swift (21 bridge calls — static nonisolated)

Special case: `nonisolated static func packetInputBridgeReports(databasePath:)` creates its own `GooseRustBridge()` instance and makes 21 sequential bridge calls. Becomes `nonisolated static async func`.

### HealthDataStore+Snapshots.swift (5 bridge calls)

| Lines | Functions | Pattern |
|-------|-----------|---------|
| 31, 42, 46, 50 | `runPacketScores()` | `packetInputQueue.async { ... DispatchQueue.main.async { } }` |
| 80 | `runSleepScore()` | `packetInputQueue.async { ... DispatchQueue.main.async { } }` |

### HealthDataStore+Recovery.swift (1 bridge call)

| Line | Function | Pattern |
|------|----------|---------|
| 115 | `runRecoveryV1()` | `packetInputQueue.async { ... Task { @MainActor [weak self] in } }` |

### HealthDataStore+StagingSleep.swift (1 bridge call)

| Line | Function | Pattern |
|------|----------|---------|
| 124 | `runSleepStaging()` | `packetInputQueue.async { ... Task { @MainActor [weak self] in } }` |

### HealthDataStore+Readiness.swift (2 bridge calls)

| Lines | Function | Pattern |
|-------|----------|---------|
| 101, 151 | `runReadinessV1()` | `packetInputQueue.async { ... Task { @MainActor [weak self] in } }` |

Note: 2 bridge calls within a single `packetInputQueue.async` closure — the first fetches exercise sessions, the second calls goose_readiness_v1 using the result of the first.

### HealthDataStore+Exercise.swift (1 bridge call)

| Line | Function | Pattern |
|------|----------|---------|
| 91 | `runExerciseSessions()` | `packetInputQueue.async { ... Task { @MainActor [weak self] in } }` |

### HealthDataStore+IMUSteps.swift (2 bridge calls)

| Lines | Function | Pattern |
|-------|----------|---------|
| 50, 78 | `runIMUStepCount()` | `packetInputQueue.async { ... Task { @MainActor [weak self] in } }` |

Note: 2 sequential bridge calls within one dispatch — first fetches gravity rows, second runs step counting on the result.

### HealthDataStore+V24Biometrics.swift (2 bridge calls)

| Lines | Function | Pattern |
|-------|----------|---------|
| 64 | `runV24Biometrics()` | `packetInputQueue.async { ... Task { @MainActor [weak self] in } }` |
| 93 | `runV24Biometrics()` | `try? bridge.request(...)` — inside same dispatch, conditional secondary call |

### HealthDataStore+Cardio.swift (2 bridge calls — UNUSUAL: direct @MainActor)

| Lines | Function | Pattern |
|-------|----------|---------|
| 97 | `cardioLoadActivitySessions(from:to:)` | **DIRECT** — no queue, no async, called on @MainActor |
| 116 | `cardioLoadActivityMetricsByName(sessionID:)` | **DIRECT** — no queue, no async, called on @MainActor |

No external callers found — only used within +Cardio.swift computation chain. Both functions return values synchronously; after migration they must return `async` and all callers within the chain become async.

### HealthDataStore+Utilities.swift (1 bridge call — helper function)

| Line | Function | Pattern |
|------|----------|---------|
| 125 | `sleepScoreReport(baseArgs:) throws -> [String: Any]` | Direct `try bridge.request(...)` — helper called from within queue contexts |

**Note:** `sleepScoreReport` is defined as a helper but has **no callers found** in the codebase. It appears to be dead code or intended for future use. Safe to migrate to `async throws` or leave as-is and remove.

### Files with ZERO bridge calls (no migration work needed)

| File | Content |
|------|---------|
| `HealthDataStore+ActivitySnapshots.swift` | Pure data computation from `packetInputReports` |
| `HealthDataStore+CoachSummaries.swift` | Pure data computation |
| `HealthDataStore+Sleep.swift` | Pure data computation + HealthKit import (no bridge) |
| `HealthDataStore+StaticSnapshots.swift` | Static snapshot definitions |
| `HealthDataStore+StressEnergy.swift` | Computation from `HeartRateSeriesStore` (no bridge) |
| `HealthDataStore+Trends.swift` | Pure data computation |
| `HealthDataStore+Vitals.swift` | Pure data computation |

---

## External Callers to Migrate (Views + Model)

All callers are in SwiftUI view files calling methods that become `async`. Each call site needs wrapping in `Task { }`.

| Caller File | Method Called | Current Context | Migration |
|-------------|--------------|-----------------|-----------|
| `AppShellView.swift:22` | `healthStore.runPacketInputs()` | `model.onHistoricalSyncCompleted = { ... }` closure | Wrap in `Task { await ... }` inside closure |
| `HealthView.swift:115` | `store.refreshBridgeCatalogs()` | `@MainActor func refreshDashboard()` | Add `Task { await ... }` |
| `HealthView.swift:117` | `store.refreshPacketInputsIfNeeded()` | `@MainActor func refreshDashboard()` | Add `Task { await ... }` |
| `HealthView.swift:66` | `store.loadBridgeCatalogsIfNeeded()` | `.onAppear` | Add `Task { await ... }` |
| `HealthDashboardViews.swift:569` | `store.runPacketInputs()` | `Button action` | Add `Task { await ... }` |
| `HealthDashboardViews.swift:618` | `store.runPacketScores()` | `Button action` | Add `Task { await ... }` |
| `HealthRecoveryStressViews.swift:202-212` | `store.runPacketScores()` + `runRecoveryV1()` + `runReadinessV1()` + `runV24Biometrics()` | `.onAppear` + `.onChange` | Wrap all in single `Task { }` |
| `HealthSleepOverviewViews.swift:147` | `store.runSleepStaging()` | `.onAppear` | Add `Task { await ... }` |
| `HealthMetricFamilyStrainViews.swift:568-573` | `store.runExerciseSessions()` + `runIMUStepCount()` | `.onAppear` + `.onChange` | Wrap in `Task { }` |
| `SleepV2ScheduleViews.swift:144` | `store.refreshSleepAfterBandSync(packetCount:)` | Button action | Add `Task { await ... }` |
| `SleepBridgeViews.swift:36` | `store.refreshSleepAfterBandSync(packetCount:)` | Button action | Add `Task { await ... }` |
| `HomeDashboardView.swift:100` | `healthStore.loadBridgeCatalogsIfNeeded()` | `.onAppear` | Add `Task { await ... }` |
| `MoreRawExportViews.swift:199` | `healthStore.loadBridgeCatalogsIfNeeded()` | `.onAppear` | Add `Task { await ... }` |
| `MoreDataStore+Validation.swift:132` | `healthStore.loadBridgeCatalogsIfNeeded()` | ? | Add `Task { await ... }` |
| `HealthRecoveryStressViews.swift:202` | `store.loadBridgeCatalogsIfNeeded()` | `.onAppear` | Add `Task { await ... }` |
| `HealthSleepOverviewViews.swift:145` | `store.loadBridgeCatalogsIfNeeded()` | `.onAppear` | Add `Task { await ... }` |
| `CoachView.swift:91-92` | `healthStore.loadBridgeCatalogsIfNeeded()` + `refreshPacketInputsIfNeeded()` | `.onAppear` | Add `Task { await ... }` |

---

## Wave/Plan Grouping Strategy

Recommended grouping respects D-06 (zero inter-plan file overlap) and groups by logical area:

### Plan 1 — GooseRustBridge async foundation
**Files:** `GooseRustBridge.swift`
**Work:** Add `requestAsync` method. No file in HealthDataStore touched yet. Build verifies the new method exists and compiles.

### Plan 2 — PacketInputs migration (largest batch)
**Files:** `HealthDataStore+PacketInputs.swift`
**Work:** Convert `packetInputBridgeReports` to `nonisolated static async`. Update `HealthDataStore.swift:runPacketInputs` to `await` it (but `packetInputQueue` not yet removed — Plan-final does cleanup).
**Special:** 21 bridge calls in one static function. Also update `runPacketInputs` in `HealthDataStore.swift` to become async and use `await packetInputBridgeReports(...)` — removing the `packetInputQueue.async` wrapper.

### Plan 3 — Score runners (Snapshots + Recovery)
**Files:** `HealthDataStore+Snapshots.swift`, `HealthDataStore+Recovery.swift`
**Work:** `runPacketScores`, `runSleepScore`, `runRecoveryV1` → async. Update their view callers in `HealthRecoveryStressViews.swift`.

### Plan 4 — Sleep staging + Readiness
**Files:** `HealthDataStore+StagingSleep.swift`, `HealthDataStore+Readiness.swift`
**Work:** `runSleepStaging`, `runReadinessV1` → async. Update callers in `HealthSleepOverviewViews.swift`.

### Plan 5 — Activity + IMU + V24
**Files:** `HealthDataStore+Exercise.swift`, `HealthDataStore+IMUSteps.swift`, `HealthDataStore+V24Biometrics.swift`
**Work:** `runExerciseSessions`, `runIMUStepCount`, `runV24Biometrics` → async. Update callers in `HealthMetricFamilyStrainViews.swift`.

### Plan 6 — Cardio direct calls + Utilities + Bridge catalog
**Files:** `HealthDataStore+Cardio.swift`, `HealthDataStore+Utilities.swift`
**Work:** `cardioLoadActivitySessions`, `cardioLoadActivityMetricsByName` → async (propagates through Cardio computation chain). Migrate `sleepScoreReport` in Utilities (or mark as dead code).

### Plan 7 — Final cleanup + all remaining callers + queue removal
**Files:** `HealthDataStore.swift`, `AppShellView.swift`, `HealthView.swift`, `HomeDashboardView.swift`, `MoreRawExportViews.swift`, `MoreDataStore+Validation.swift`, `CoachView.swift`, `HealthDashboardViews.swift`
**Work:**
- Remove `packetInputQueue` and `heartRateTimelineQueue` from `HealthDataStore.swift`
- Migrate `refreshBridgeCatalogs` to async
- Migrate `refreshPacketInputsAfterCapture` (uses DispatchWorkItem — convert to `Task.sleep` + cancellation pattern)
- Remove sync `request`/`requestValue` from `GooseRustBridge` (or rename `requestAsync` → `request`)
- Update all remaining view callers with `Task { await ... }` wrappers

---

## Risk Assessment

### RISK-01: GooseRustBridge mutable state in concurrent context [HIGH]
`GooseRustBridge` has `private var counter = 0` and `private(set) var lastTiming` with no lock. Under the current GCD model, calls happen sequentially on `packetInputQueue`. Under async+Task.detached, multiple async calls could race on the same bridge instance. However, each HealthDataStore owns exactly ONE bridge instance, and all async methods on HealthDataStore are `@MainActor` — they run one at a time (not concurrent). `Task.detached` within each call runs sequentially per-call. **Verdict:** Safe in practice, but `lastTiming` writes on detached thread + reads from @MainActor = technically `@unchecked Sendable` risk. Implementer should either add `nonisolated(unsafe)` to `lastTiming` or accept that `lastTiming` is unreliable post-migration (it was an internal diagnostic anyway).

### RISK-02: Cardio direct bridge calls [MEDIUM]
`cardioLoadActivitySessions` and `cardioLoadActivityMetricsByName` are called synchronously within `@MainActor` context with no queue. Making them `async` propagates through the Cardio computation chain. The call chain must be traced carefully. Fortunately, no external callers were found — these are only called within `+Cardio.swift` itself, and `cardioLoadAlgorithmSummary` (currently sync) may need to become async or hold cached data.

**Investigation needed:** Does `cardioLoadAlgorithmSummary` get called from SwiftUI body? If yes, it cannot be async — needs redesign (cache result in @Published property and refresh separately). Check `cardioLoadSnapshot` call site.

### RISK-03: refreshSleepAfterBandSync completion closure chain [MEDIUM]
`refreshSleepAfterBandSync` calls `runPacketInputs(completion:)` with a closure that calls `runSleepScore()` and `runSleepStaging()`. After migration, all three become async. The completion parameter should be removed — the function becomes a sequential async chain:

```swift
func refreshSleepAfterBandSync(packetCount: Int) async {
  bandSleepImportStatus = "..."
  await runPacketInputs()
  await runSleepScore()
  await runSleepStaging()
  bandSleepImportStatus = "..."
}
```

### RISK-04: refreshPacketInputsAfterCapture DispatchWorkItem debounce [LOW]
Currently uses `DispatchWorkItem.cancel()` + `DispatchQueue.main.asyncAfter` for a 0.8s debounce before calling `runPacketInputs()`. After migration, this must use a `Task` with cancellation pattern:

```swift
func refreshPacketInputsAfterCapture() {
  packetInputRefreshTask?.cancel()
  packetInputRefreshTask = Task {
    try await Task.sleep(for: .seconds(0.8))
    await runPacketInputs()
  }
}
```

The stored property `packetInputRefreshWorkItem: DispatchWorkItem?` becomes `packetInputRefreshTask: Task<Void, Error>?`.

### RISK-05: heartRateTimelineQueue is NOT a bridge queue [LOW]
`heartRateTimelineQueue` is used in `refreshHeartRateTimeline()` which calls `heartRateSeriesStore.timelineSnapshot()` — **not a bridge call**. It should be migrated separately (or kept as-is if not in scope). Per D-05, both queues are removed — so `refreshHeartRateTimeline` must also be converted to async (it currently uses the queue only for the timelineSnapshot computation, not for FFI).

---

## Common Pitfalls

### Pitfall 1: Reading @MainActor properties inside Task.detached
**What goes wrong:** `Task.detached { self.databasePath }` — compiler error: actor-isolated property captured in detached task.
**Why it happens:** `Task.detached` does not inherit actor context; `HealthDataStore` is @MainActor.
**How to avoid:** Capture all @MainActor properties into local `let` constants before calling `requestAsync`. Since `requestAsync` itself handles the Task.detached internally, the caller on @MainActor just does `let result = try await bridge.requestAsync(...)` — all property reads happen before the suspension point, safely on @MainActor.
**Warning signs:** Compiler error "Expression is 'async' but is not marked with 'await'" or "actor-isolated ... cannot be captured".

### Pitfall 2: Publishing changes from background threads
**What goes wrong:** `self.someProperty = result` inside `Task.detached { }` or on a background thread.
**Why it happens:** @Observable requires mutations on the actor that owns the class. If you accidentally assign inside the detached task body, you get the runtime warning "Publishing changes from background threads".
**How to avoid:** Per D-02, `HealthDataStore` stays @MainActor. After `await bridge.requestAsync(...)`, Swift is back on @MainActor. Never assign to self.X inside the `Task.detached` closure — only inside the async func body after the await.
**Warning signs:** Xcode console: "Publishing changes from background threads is not allowed; make sure to publish values from the main thread (via operators like receive(on:)) on model updates."

### Pitfall 3: Forgetting `[weak self]` becomes less necessary but still good practice
**What goes wrong:** Strong reference cycles in Task closures can cause memory leaks.
**Why it happens:** `Task { await self.runX() }` in a view captures `store` strongly — fine for short-lived tasks; `[weak self]` in view closures is still good.
**How to avoid:** Views that create `Task { }` in `.onAppear` or Button actions should use `Task { [weak store] in await store?.runX() }` or verify that the view lifecycle handles cleanup.

### Pitfall 4: `try?` bridge call in V24Biometrics
**What goes wrong:** `if let spo2Report = try? bridge.request(...)` — the `try?` silently absorbs errors.
**Why it happens:** The secondary spo2_from_raw call is intentionally optional.
**How to avoid:** `if let spo2Report = try? await bridge.requestAsync(...)` — same semantics, just add `await`. The `try?` pattern is preserved.

---

## Code Examples

### requestAsync implementation (Plan 1 target)

```swift
// Source: [ASSUMED] Swift Evolution SE-0304 (structured concurrency)
// GooseRustBridge — additive method
func requestAsync(method: String, args: [String: Any] = [:]) async throws -> [String: Any] {
  try await Task.detached(priority: .userInitiated) {
    try self.requestValue(method: method, args: args) as? [String: Any] ?? [:]
  }.value
}
```

### Canonical async migration of a run* method

```swift
// BEFORE: Recovery.swift runRecoveryV1
func runRecoveryV1() {
  let db = databasePath
  let bridge = self.bridge
  packetInputQueue.async { [weak self] in
    guard let self else { return }
    do {
      let report = try bridge.request(method: "metrics.goose_recovery_v1", args: bridgeArgs)
      let result = parseResult(report)
      Task { @MainActor [weak self] in
        self?.recoveryV1Result = result
      }
    } catch {
      Task { @MainActor [weak self] in
        self?.recoveryV1Result = nil
      }
    }
  }
}

// AFTER
func runRecoveryV1() async {
  let db = databasePath        // captured on @MainActor before suspension
  var bridgeArgs: [String: Any] = [
    "database_path": db,
    // ... other args from @MainActor state
  ]
  do {
    let report = try await bridge.requestAsync(method: "metrics.goose_recovery_v1", args: bridgeArgs)
    let result = parseResult(report)
    self.recoveryV1Result = result  // @MainActor — safe after await
  } catch {
    self.recoveryV1Result = nil
  }
}
```

### View caller migration

```swift
// BEFORE
.onAppear {
  store.runPacketScores()
  store.runRecoveryV1()
  store.runReadinessV1()
  store.runV24Biometrics()
}

// AFTER
.onAppear {
  Task {
    await store.runPacketScores()
    await store.runRecoveryV1()
    await store.runReadinessV1()
    await store.runV24Biometrics()
  }
}
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (GooseSwiftTests target exists) |
| Config file | `GooseSwiftTests/Info.plist` |
| Quick run command | `xcodebuild test -scheme GooseSwiftTests -destination 'platform=iOS Simulator,name=iPhone 16'` |
| Full suite command | Same — single test target |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ASYNC-01 | bridge.request without await = 0 results | grep audit | `grep -r "bridge\.request(" GooseSwift/ --include="*.swift" \| grep -v await \| grep -v "//.*request"` | N/A — grep check |
| ASYNC-01 | GooseRustBridge.requestAsync exists and compiles | build | `xcodebuild build -scheme GooseSwift -destination 'platform=iOS Simulator,name=iPhone 16'` | Wave 0 gap |
| ASYNC-02 | Dashboards populate after bridge call | smoke test | Manual simulator — see D-08 | Human verify |

### Wave 0 Gaps

- [ ] No existing test for GooseRustBridge async behaviour — Phase 48 added `GooseUploadServiceTests.swift` but no bridge async tests. The build test (`xcodebuild build`) is the primary gate per D-08.

*(The existing `GooseBLETypesTests.swift`, `HRMonitorStateTests.swift` etc. are unrelated to this phase.)*

---

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1`. This phase does not introduce new network calls, authentication, or data storage. All changes are internal Swift Concurrency refactoring with no security surface change.

| ASVS Category | Applies | Note |
|---------------|---------|------|
| V2 Authentication | No | No auth changes |
| V3 Session Management | No | No session changes |
| V4 Access Control | No | No access control changes |
| V5 Input Validation | No | FFI args unchanged |
| V6 Cryptography | No | No crypto changes |

No new threat patterns introduced.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode (iOS 26 SDK) | Build + test | ✓ (assumed — project compiles) | iOS 26.0 | — |
| iOS Simulator | D-08 smoke test | ✓ (XcodeBuildMCP available) | — | — |
| GooseSwiftTests target | Automated test | ✓ | — | Build-only gate |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DispatchQueue.main.async for actor hops | `self.prop = r` after `await` on @MainActor | SE-0306 (Swift 5.5) | Cleaner, compiler-verified actor isolation |
| `DispatchQueue.async` for background work | `Task.detached` or `Task { }` | SE-0304 (Swift 5.5) | Structured concurrency, cancellation, priority |
| `@unchecked Sendable` with GCD locks | `actor` type | Swift 5.5+ | For this codebase, @unchecked Sendable stays (GooseRustBridge is not refactored to actor) |

**Note on Swift Observable vs @Published:** `@MainActor @Observable` (Observation framework) requires mutations on the main actor. After `await` in an @MainActor-isolated async func, Swift is guaranteed to be back on @MainActor. This is the key enabling property of D-02.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `cardioLoadActivitySessions` and `cardioLoadActivityMetricsByName` have no external callers | Cardio risk / call site inventory | If called from a SwiftUI body (not found), making them async would require a redesign with cached @Published properties |
| A2 | `sleepScoreReport` in +Utilities.swift is dead code (no callers found) | Call site inventory | If called from somewhere not found, it needs async migration too |
| A3 | `Task.detached { requestValue(...) }.value` compiles cleanly given @unchecked Sendable | requestAsync pattern | If Swift 5.10+ strict concurrency flags this as unsafe, may need different isolation strategy |
| A4 | `refreshHeartRateTimeline` (uses heartRateTimelineQueue but no bridge) is in scope for queue removal | Plan 7 scope | If left with heartRateTimelineQueue, D-05 is only partially satisfied — implementer must convert it to async too |

---

## Open Questions (RESOLVED)

1. **cardioLoadAlgorithmSummary call context** — RESOLVED
   - Resolution: Verified by grep — `cardioLoadAlgorithmSummary`, `cardioLoadActivitySessions`, and `cardioLoadActivityMetricsByName` have ZERO live callers in the codebase. These methods are dead code with no SwiftUI View body callers. Making them async causes no cascade issues. Plan 06 can migrate these freely.

2. **lastTiming data race in GooseRustBridge** — RESOLVED
   - Resolution: `lastTiming` is marked `@ObservationIgnored` and used only in diagnostic timing output within GooseRustBridge itself. No @MainActor code reads `lastTiming` after bridge calls. Plan 01 adds `nonisolated(unsafe)` to `lastTiming` as a precaution, consistent with the pattern already used for `heartRateSeriesUpdateObserver` in HealthDataStore.

---

## Sources

### Primary (HIGH confidence)
- Codebase grep — all call sites verified by direct file inspection
- `GooseRustBridge.swift` — direct read, line numbers confirmed
- `HealthDataStore.swift` + all 17 extension files — direct read

### Secondary (MEDIUM confidence)
- [ASSUMED] Swift Evolution SE-0296, SE-0304, SE-0306 — Swift Concurrency (`async`/`await`, structured concurrency, actor isolation) from training knowledge

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Call site inventory: HIGH — verified by grep + direct file reads
- Migration patterns: HIGH — patterns already present in codebase (Task { @MainActor [weak self] } precedent)
- Caller identification: HIGH — verified by grep
- Swift Concurrency semantics: MEDIUM — training knowledge (SE-0296/SE-0304/SE-0306), not verified via Context7 this session

**Research date:** 2026-06-10
**Valid until:** 2026-07-10 (stable — no external dependencies)
