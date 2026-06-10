---
phase: 48-upload-sync-race-fix
reviewed: 2026-06-10T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - GooseSwift/GooseUploadService.swift
  - Rust/core/src/store.rs
  - GooseSwiftTests/GooseUploadServiceTests.swift
findings:
  critical: 2
  warning: 3
  info: 1
  total: 6
status: issues_found
---

# Phase 48: Code Review Report

**Reviewed:** 2026-06-10
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 48 introduces a pre-capture pattern to eliminate a race window where rows
inserted during an HTTP round-trip were incorrectly marked synced. The Rust-side
contract test (`test_pre_capture_does_not_mark_rows_inserted_during_race_window`)
is well-written and correctly validates the core invariant. The `mark_synced_rows`
and `rows_pending_upload` Rust functions are correctly allowlist-guarded against
SQL injection.

However, two blockers are present: the `@unchecked Sendable` class mutates shared
state from multiple concurrent tasks without any synchronisation primitive, which
is a provable data race. Additionally, `triggerBackfill` unconditionally passes
`deviceType: "GOOSE"` to `performUpload`, defeating the device-type derivation
logic the phase is supposed to preserve. Three warnings cover silent accumulation
of old unsynced rows, a nearly-always-skipped integration test, and leaked static
state in `MockURLProtocol`.

## Critical Issues

### CR-01: Data race on mutable properties in `@unchecked Sendable` class

**File:** `GooseSwift/GooseUploadService.swift:14-23, 40`

**Issue:** `GooseUploadService` is declared `@unchecked Sendable` with four
mutable stored properties (`pendingBatchCount`, `pendingRowCount`,
`lastSyncedCount`, `lastUploadTimestamp`). The comment at line 19 states they are
"Protected by Swift's cooperative thread pool — only mutated from upload tasks",
but this is incorrect:

- `upload()` (line 40) increments `pendingBatchCount` synchronously on whatever
  thread the caller uses (typically `@MainActor`), with no await or dispatch.
- `performUpload` (line 46), running on a detached task on the cooperative thread
  pool, decrements `pendingBatchCount` and writes the other three fields.
- `triggerBackfill` (line 337) spawns a second detached task that also calls
  `performUpload`, meaning two `performUpload` coroutines can be in-flight
  simultaneously — both racing to read and write `pendingBatchCount`.

Swift's cooperative thread pool does not guarantee serial execution of all
detached tasks; multiple coroutines on different threads can truly run concurrently
on multi-core devices. `pendingBatchCount += 1` / `pendingBatchCount -= 1` are
non-atomic read-modify-write cycles. The result is stale badge counts at minimum
and, if the compiler reorders, torn reads of the timestamp/count pair published via
`publishStatus()`.

**Fix:** Isolate all mutable state to a serial actor:

```swift
actor UploadState {
  var lastUploadTimestamp: Date?
  var pendingBatchCount: Int = 0
  var lastSyncedCount: Int?
  var pendingRowCount: Int = 0

  func incrementBatch() { pendingBatchCount += 1 }
  func decrementBatch() { pendingBatchCount = max(0, pendingBatchCount - 1) }
  func snapshot() -> GooseUploadStatus { ... }
}
```

Or — if an actor boundary is too invasive — protect reads and writes with an
`NSLock` consistently at every call site, matching the pattern used elsewhere in
the codebase (e.g., `CaptureFrameWriteQueue`).

---

### CR-02: `triggerBackfill` hardcodes `deviceType: "GOOSE"`, bypassing device derivation

**File:** `GooseSwift/GooseUploadService.swift:358`

**Issue:** `triggerBackfill` calls `performUpload` with a literal `"GOOSE"`:

```swift
await performUpload(deviceID: deviceID, deviceType: "GOOSE", sinceTimestamp: sinceTimestamp)
```

`performUpload` passes `deviceType` directly to `buildUploadPayload`, which uses
it to select the server-side JSON field (`device_generation: "5.0"` for `"GOOSE"`
vs `device_type` + `device_class` for HR monitors). If the caller obtained the
`deviceID` of a paired Polar H10 or GEN4 device and triggered backfill, the server
receives incorrect device classification. The test `test_triggerManualUpload_doesNotHardcodeGoose`
only scans `GooseAppModel+Upload.swift` for this pattern — it does not scan
`GooseUploadService.swift` itself, so this occurrence is invisible to that test.

**Fix:** Add `deviceType: String` as a parameter to `triggerBackfill` and have
the caller (in `GooseAppModel+Upload.swift`) pass the derived device type, matching
how `upload()` receives it:

```swift
func triggerBackfill(deviceID: UUID, deviceType: String, sinceTimestamp: Date) {
  Task.detached(priority: .utility) { [weak self] in
    ...
    await performUpload(deviceID: deviceID, deviceType: deviceType, sinceTimestamp: sinceTimestamp)
  }
}
```

---

## Warnings

### WR-01: Old unsynced rows silently excluded by `sinceTs` filter, accumulate forever

**File:** `GooseSwift/GooseUploadService.swift:267-284`

**Issue:** `captureAllPendingRowIDs` post-filters each row by `ts >= sinceTs`
(line 284). The Rust `rows_pending_upload` returns all `synced=0` rows regardless
of timestamp — it has no time bound. Any row with `synced=0` and `ts < sinceTs`
(e.g., a row that was never synced from an earlier session) is silently dropped
from the returned map and therefore never included in a future `markStreamsSynced`
call. Because `upload.get_recent_decoded_streams` on the Rust side also gates on
`since_ts`, those old rows are never included in the HTTP payload either, so they
are in a permanent limbo: `synced=0` but never uploaded. Over time, every call to
`refreshPendingRowCount()` (which uses no timestamp filter) will count them,
inflating the badge number past what will ever be uploaded.

The comment at line 254 acknowledges that "no cross-device risk" exists for tables
without `device_id`, but does not acknowledge the accumulation risk.

**Fix:** Either (a) pass `since_ts` as an argument to `sync.rows_pending_upload`
(add it to `SyncRowsPendingUploadArgs` in `bridge.rs` and propagate to
`rows_pending_upload` in `store.rs`) so that old rows are excluded consistently
at the Rust level, OR (b) remove the Swift-side `sinceTs` post-filter entirely —
all unsynced rows should be candidates for marking once the upload succeeds, since
`upload.get_recent_decoded_streams` already gates the payload content.

---

### WR-02: Integration tests skip silently on a fresh database, never verifying the race fix end-to-end

**File:** `GooseSwiftTests/GooseUploadServiceTests.swift:220-275`

**Issue:** Both `test_upload503_leavesSynced0` and `test_upload200_marksSynced1`
call `seedTempDB` and then `guard hasData else { throw XCTSkip(...) }`. On a fresh
in-memory SQLite (which `seedTempDB` creates), `upload.get_recent_decoded_streams`
returns empty arrays because there are no `decoded_frames` rows. The guard throws
`XCTSkip`, meaning the test always skips in CI where no real BLE data exists. The
skip message states "mock infrastructure verified: MockURLProtocol.handler is set
and tearDown clears it", but that is not what the test is supposed to prove. The
race-fix invariant — that 503 leaves `synced=0` and 200 leaves `synced=1` — is
never actually asserted in practice.

This means phase 48's core correctness guarantee is tested only at the Rust unit
test level (`test_pre_capture_does_not_mark_rows_inserted_during_race_window`), not
at the Swift integration level.

**Fix:** Seed the temp database programmatically at the Rust level by directly
inserting rows into `hr_samples` with `synced=0` before calling `svc.upload(...)`.
The bridge already exposes `sync.mark_synced` and can be called in reverse to set
up state. Alternatively, insert a synthetic `decoded_frames` row via the existing
`insert_raw_frames_batch` bridge method so that `seedTempDB` returns `true`.

---

### WR-03: `MockURLProtocol` static state can leak between test methods

**File:** `GooseSwiftTests/GooseUploadServiceTests.swift:126-149`

**Issue:** `MockURLProtocol.handler` and `MockURLProtocol.requestCount` are `static
var` fields. They are reset inside `tearDownUploadEnvironment()`, which is called
inside `defer` blocks within individual test methods rather than in `tearDown()`.
If a test throws before reaching its `defer` (for example, `setUpUploadEnvironment`
crashes or an earlier assertion throws), the static state is not cleaned up and
will pollute the next test in the suite. XCTest does not guarantee test method
order, so whichever test runs next may inherit a stale `handler` or a non-zero
`requestCount`.

Additionally, because `requestCount` is read from the test assertion context while
it may still be written by the URLProtocol dispatch queue, the read at line 244
(`XCTAssertEqual(MockURLProtocol.requestCount, 3)`) is a non-atomic read of a var
that `startLoading` (line 135) increments from a background thread, which is a
data race.

**Fix:** Move teardown into `override func tearDown()` (or `addTeardownBlock`) so
it always runs. Replace `static var requestCount: Int` with `static var
requestCount: Int = 0` guarded by an `NSLock` or `os_unfair_lock`, or use
`os_atomic` via `@MainActor`.

---

## Info

### IN-01: `captureAllPendingRowIDs` sends 8 synchronous bridge calls sequentially

**File:** `GooseSwift/GooseUploadService.swift:268-292`

**Issue:** Each of the 8 streams triggers a separate `rust.request(...)` call
(which opens the SQLite file, runs a query, and closes it). All 8 calls are
sequential in a tight loop. On a heavily loaded device with a large pending queue,
this adds measurable latency before the HTTP request is even sent. It also means 8
separate `GooseStore::open()` calls with `configure_read_write_connection` and WAL
checkpoint setup each time. This is not a correctness issue but is a quality smell
given the CLAUDE.md guidance that expensive Rust bridge calls should be minimised.

**Fix (deferred):** Expose a single `sync.rows_pending_upload_all_streams` bridge
method that queries all 8 streams in one `open_bridge_store` call and returns the
combined map, reducing round-trips from 8 to 1. This is a future improvement;
current behavior is correct.

---

_Reviewed: 2026-06-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
