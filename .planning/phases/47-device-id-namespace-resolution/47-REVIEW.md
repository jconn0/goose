---
phase: 47-device-id-namespace-resolution
reviewed: 2026-06-10T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - Rust/core/src/store.rs
  - Rust/core/src/capture_import.rs
  - Rust/core/src/bridge.rs
  - Rust/core/tests/capture_import_tests.rs
  - GooseSwift/GooseBLEClient.swift
  - GooseSwift/GooseBLEClient+CentralDelegate.swift
  - GooseSwift/CaptureFrameWriteQueue.swift
  - GooseSwift/GooseAppModel+Lifecycle.swift
  - GooseSwift/ActivityLocationTracker.swift
  - server/db/init.sql
  - server/ingest/app/main.py
  - server/ingest/app/store.py
  - server/ingest/app/read.py
  - server/ingest/tests/test_ingest_frames_api.py
  - server/ingest/tests/test_read_api.py
findings:
  critical: 3
  warning: 3
  info: 2
  total: 8
status: issues_found
---

# Phase 47: Code Review Report

**Reviewed:** 2026-06-10T00:00:00Z
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Summary

Phase 47 adds a `device_uuid` nullable column to both the Rust SQLite schema (`raw_evidence`, `decoded_frames`) and the TimescaleDB schema (`raw_frames`), propagates the CoreBluetooth peripheral UUID from Swift through the Rust FFI bridge, and adds a bidirectional UUID/model-name lookup in the FastAPI export endpoint. The overall design is sound and the parameterisation discipline in SQL is good. Three blockers were found: a `NOT NULL` constraint violation that crashes frame ingestion when optional fields are omitted, a stale `connectedPeripheralUUID` that leaks the previous device's UUID across reconnections, and a `decoded_frames.device_uuid` column that is created by the migration but never populated by `insert_decoded_frame`, making the test assertion misleading. Three warnings cover an odd-length hex input gap, a NULL-suppressed deduplication conflict, and a missing `min_length` guard. Two info items cover commented migration rationale and a test coverage gap.

## Critical Issues

### CR-01: NULL written into NOT NULL columns when optional IngestFrame fields are omitted

**File:** `server/ingest/app/store.py:46-65` / `server/ingest/app/main.py:438-445`

**Issue:** The `IngestFrame` Pydantic model declares `source`, `device_type`, `device_model`, and `sensitivity` as `str | None = None`. When an iOS client omits these fields (which is explicitly the intended use-case per the model comment "optional"), `model_dump()` produces `None` for each. `store.insert_raw_frames_batch` then calls `f.get("source")` etc., which returns `None`, and passes it to psycopg as an explicit SQL `NULL`. The `raw_frames` DDL declares all four columns `NOT NULL` (with `DEFAULT` values). In PostgreSQL, `DEFAULT` only applies when a column is omitted from the `INSERT` column list — an explicit `NULL` overrides it and raises a `not-null constraint` violation, causing a 500 error for any client that omits those optional fields.

**Fix:** Use `COALESCE` in the `INSERT` or substitute defaults on the Python side before insertion:

```python
cur.execute(
    """INSERT INTO raw_frames
       (device_id, captured_at, frame_hex, source, device_type, device_model, sensitivity, device_uuid)
       VALUES (%s, to_timestamp(%s), %s,
               COALESCE(%s, 'ios.corebluetooth.notification'),
               COALESCE(%s, 'GOOSE'),
               COALESCE(%s, 'WHOOP 5.0 Goose'),
               COALESCE(%s, 'user-owned-capture'),
               %s)
       ON CONFLICT (device_id, captured_at, frame_hex) DO NOTHING""",
    (
        device_id,
        f.get("captured_at_unix"),
        f.get("frame_hex"),
        f.get("source"),
        f.get("device_type"),
        f.get("device_model"),
        f.get("sensitivity"),
        f.get("device_uuid"),
    ),
)
```

Or, equivalently, supply defaults before the execute call:

```python
source = f.get("source") or "ios.corebluetooth.notification"
device_type = f.get("device_type") or "GOOSE"
device_model = f.get("device_model") or "WHOOP 5.0 Goose"
sensitivity = f.get("sensitivity") or "user-owned-capture"
```

### CR-02: `connectedPeripheralUUID` never cleared on disconnect — stale UUID tags new device's frames

**File:** `GooseSwift/GooseBLEClient+CentralDelegate.swift:217` / `GooseSwift/GooseAppModel+Lifecycle.swift:115-136`

**Issue:** `connectedPeripheralUUID` is set in `centralManager(_:didConnect:)` (line 217) and consumed via `captureFrameWriteQueue.currentDeviceUUID` in `handleBLEConnectionStateChange("ready")` (Lifecycle line 121). However, `connectedPeripheralUUID` is **never set to `nil`** in the disconnect path (`didDisconnectPeripheral`, `didFailToConnect`, or `centralManagerDidUpdateState` when Bluetooth turns off). The `Lifecycle` extension clears `captureFrameWriteQueue.currentDeviceUUID` when the state is non-ready (line 135), but only after `handleBLEConnectionStateChange` propagates. Between a disconnect and the next non-ready state callback, and again if `captureFrameWriteQueue.currentDeviceUUID` is read directly, `connectedPeripheralUUID` retains the old device's UUID.

More concretely: if a user pairs with Device A (UUID = `AAA-...`), disconnects, then pairs with Device B and packets arrive before `handleBLEConnectionStateChange("ready")` fires for Device B, those packets will be tagged with Device A's UUID. This corrupts the `device_uuid` column for Device B's `raw_evidence` rows.

**Fix:** Clear `connectedPeripheralUUID` in `didDisconnectPeripheral`:

```swift
// In GooseBLEClient+CentralDelegate.swift, centralManager(_:didDisconnectPeripheral:)
connectedPeripheralUUID = nil
```

And similarly in `didFailToConnect` and the Bluetooth-off path in `centralManagerDidUpdateState`.

### CR-03: `decoded_frames.device_uuid` column is created by migration but never written — test assertion is misleading

**File:** `Rust/core/src/store.rs:6894-6910` / `Rust/core/tests/capture_import_tests.rs:852-876`

**Issue:** `ensure_decoded_frame_columns()` (store.rs line 6902) adds a `device_uuid TEXT` column to `decoded_frames`. The test `test_migration_adds_device_uuid` asserts this column exists (line 858-875). However, `insert_decoded_frame` (store.rs line 2254-2296) never includes `device_uuid` in its `INSERT` statement — the column is always `NULL` in every decoded frame row regardless of the input. The test gives the false impression that `device_uuid` is propagated end-to-end through decode; it is not. Any downstream query joining `raw_evidence.device_uuid` via `decoded_frames` will find only `NULL`.

This is a correctness defect: Phase 47's stated goal is namespace resolution through UUID, but the decoded frames table — the table the upload bridge queries at bridge.rs for frame export — never carries the UUID. The `upload_get_raw_frames_for_upload_bridge` function (bridge.rs line 3616) correctly reads `device_uuid` from `raw_evidence`, so the upload path is fine. But any future code querying `decoded_frames.device_uuid` directly will silently receive `NULL`.

**Fix:** Either (a) populate `device_uuid` in `insert_decoded_frame` by passing it through `DecodedFrameInput`, or (b) drop the column from `decoded_frames` to avoid the misleading schema, or (c) add a clear code comment stating the column exists for future use and is always `NULL` today, and fix the test to assert the column is `NULL`:

```rust
// Option (a): add device_uuid to DecodedFrameInput and INSERT
pub struct DecodedFrameInput<'a> {
    pub frame_id: &'a str,
    pub evidence_id: &'a str,
    pub parsed: &'a ParsedFrame,
    pub parser_version: &'a str,
    pub device_uuid: Option<&'a str>,  // add this
}
```

## Warnings

### WR-01: `IngestFrame.frame_hex` pattern allows odd-length hex strings — incomplete validation

**File:** `server/ingest/app/main.py:440`

**Issue:** `IngestFrame.frame_hex` uses `pattern=r"^[0-9a-fA-F]+$"` which validates character set but does not enforce even length (complete bytes). The `Frame` model used by the older `/v1/ingest` endpoint has an explicit `hex_even_length` field validator (main.py line 67-72). `IngestFrame` for `/v1/ingest-frames` lacks this check. An iOS client submitting an odd-length hex string (e.g., a truncated BLE notification) will pass Pydantic validation and be persisted. When the frame is later exported and the Rust side attempts to `decode_hex_with_whitespace`, the import will fail with an error; but the corrupted row remains in `raw_frames` and counts against the deduplication unique index, blocking a corrected re-upload of the same `(device_id, captured_at, frame_hex)`.

**Fix:** Add the same even-length validator used by `Frame`:

```python
class IngestFrame(BaseModel):
    captured_at_unix: float
    frame_hex: str = Field(..., pattern=r"^[0-9a-fA-F]+$")
    ...

    @field_validator("frame_hex")
    @classmethod
    def frame_hex_even_length(cls, v: str) -> str:
        if len(v) % 2 != 0:
            raise ValueError("frame_hex must have even length (complete bytes)")
        return v
```

### WR-02: `insert_raw_frames_batch` uses `cur.rowcount` to count inserts — fails to count skips correctly when `ON CONFLICT DO NOTHING` fires after explicit NULL constraint violation

**File:** `server/ingest/app/store.py:62-65`

**Issue:** The `inserted`/`skipped` accounting (lines 62-65) relies on `cur.rowcount == 1`. With CR-01 (explicit NULL into NOT NULL columns), the execute call raises a `psycopg.errors.NotNullViolation` exception before `rowcount` is set. The exception propagates up uncaught through `ingest_frames` → `insert_raw_frames_batch`, rolls back the entire batch, and returns a 500 to the iOS client. Even when CR-01 is fixed, the counting logic is correct only when a row is inserted (`rowcount=1`) or silently skipped by ON CONFLICT (`rowcount=0`). There is no case where this goes wrong independently of CR-01, but the robustness issue is worth noting: if PostgreSQL ever returns `rowcount=-1` (unknown, valid in some drivers), `skipped` would be incremented incorrectly. A more defensive pattern is `if cur.rowcount > 0`.

**Fix:**
```python
if cur.rowcount > 0:
    inserted += 1
else:
    skipped += 1
```

### WR-03: Race window — `currentDeviceUUID` read on `captureFrameRowBuildQueue` but written on main thread via NSLock

**File:** `GooseSwift/GooseAppModel+NotificationPipeline.swift:187` / `GooseSwift/CaptureFrameWriteQueue.swift:204-208`

**Issue:** `captureFrameWriteQueue.currentDeviceUUID` is a computed property protected by `stateLock` (NSLock). The property getter correctly acquires the lock. The read at `GooseAppModel+NotificationPipeline.swift:187` happens inside `importCapturedFrames`, which is called from `handleNotificationIngestResult` on the main actor. This specific read is safe. However, the `CaptureFrameRowBuildRequest` is then passed to `captureFrameRowBuildQueue.async` where `captureFrameRows(for:)` consumes it — but the UUID is captured by value into the struct at the time of request creation on the main actor, so the subsequent background-queue work uses the snapshot correctly.

The warning is narrower: in the non-ready disconnect path (`GooseAppModel+Lifecycle.swift:135`), `captureFrameWriteQueue.currentDeviceUUID = nil` is assigned under `stateLock` from the main thread, while `CaptureFrameWriteQueue.enqueue` simultaneously reads `pendingRows` and appends under the same `stateLock`. Any in-flight `CaptureFrameRowBuildRequest` already created before the disconnect will carry the correct (now-stale) UUID. Rows that were enqueued but not yet written at disconnect time will go out with the old UUID. This is acceptable in practice but is a semantic gap: frames captured just before disconnect are attributed to the prior UUID even after the device is disconnected, which may be surprising.

**Fix:** Document this as a known artifact with a code comment, or set `currentDeviceUUID = nil` earlier (before the BLE state transition reaches "non-ready") to narrow the window.

## Info

### IN-01: Missing `min_length` guard on `IngestFramesBatch.frames`

**File:** `server/ingest/app/main.py:450`

**Issue:** `frames: list[IngestFrame] = Field(..., max_length=5000)` enforces an upper bound but not a lower bound. A client may POST an empty `frames: []` which succeeds (returns `{"inserted": 0, "skipped": 0}`) but wastes a DB round-trip and connection allocation. The iOS uploader never sends an empty batch, but there is no server-side guard.

**Fix:**
```python
frames: list[IngestFrame] = Field(..., min_length=1, max_length=5000)
```

### IN-02: Test `test_migration_adds_device_uuid` does not verify `device_uuid` propagation in the decoded path

**File:** `Rust/core/tests/capture_import_tests.rs:831-877`

**Issue:** The test verifies the column exists in both `raw_evidence` and `decoded_frames`, and that the index exists. However, it does not assert that a frame imported with a non-null `device_uuid` produces a non-null value in `decoded_frames.device_uuid`. Because `insert_decoded_frame` never writes the column (CR-03), this gap in test coverage hides the defect. The test for `raw_evidence` propagation (`test_capture_import_propagates_device_uuid`, line 984) correctly validates the full path for `raw_evidence`. An equivalent test for `decoded_frames` is missing.

**Fix:** Add an assertion in `test_capture_import_propagates_device_uuid` (or a new test) that reads back the `decoded_frames` row and checks `device_uuid`:

```rust
// After import, also check decoded_frames carries the UUID (once CR-03 is fixed)
let decoded = store.decoded_frame("devid-import-propagate.frame.0").unwrap().unwrap();
assert_eq!(
    decoded.device_uuid.as_deref(),
    Some("uuid-from-swift"),
    "device_uuid must propagate to decoded_frames"
);
```

---

_Reviewed: 2026-06-10T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
