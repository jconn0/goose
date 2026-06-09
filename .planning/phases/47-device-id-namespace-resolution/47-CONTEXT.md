# Phase 47: Device ID Namespace Resolution - Context

**Gathered:** 2026-06-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `device_uuid TEXT` (CoreBluetooth peripheral UUID) to `raw_evidence` and `decoded_frames` tables via schema migration. Wire the UUID from BLE connect callback through `GooseAppModel` → `CaptureFrameWriteQueue` and `GooseUploadService`. Store UUID↔device_model mapping in UserDefaults. Server export endpoint accepts both UUID and device_model for lookup.

Out of scope: any UI changes, backfilling historical rows, modifying other tables beyond raw_evidence/decoded_frames.

</domain>

<decisions>
## Implementation Decisions

### UUID↔Model Persistence
- **D-01:** Use `UserDefaults` with key `goose.swift.device_uuid_map` — dict of `[String: String]` (UUID string → device_model string). Codable serialisation. Simple and consistent with existing UserDefaults usage.
- **D-02:** If UUID regenerates (device unpaired from iOS Bluetooth settings), the map is updated at next BLE connect. Historical rows retain their old UUID — semantically correct since those captures were made with that UUID at the time.
- **D-03:** Map structure: `[String: String]` dict — `{ "uuid-str": "WHOOP 5.0 Goose" }`. No timestamps needed. Multiple devices supported naturally.

### UUID Threading (BLE → CaptureFrameWriteQueue)
- **D-04:** `GooseBLEClient` exposes `var connectedPeripheralUUID: String?` updated in `didConnect`. `GooseAppModel` reads it at connect time and updates `CaptureFrameWriteQueue.currentDeviceUUID` — same pattern already used for `device_model`.
- **D-05:** On reconnect (same or different device), `GooseAppModel` updates the queue's UUID in the `didConnect` handler. No direct BLE client → queue coupling.

### Server Bidirectional Lookup
- **D-06:** `GET /v1/export/frames/{device_id}`: try UUID parse first (UUID format = 36 chars, `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). If valid UUID → query by `device_uuid`. Otherwise → query by `device_model`. Zero caller configuration required.

### Schema Migration
- **D-07:** `device_uuid TEXT NULL` on both `raw_evidence` and `decoded_frames`. Existing rows get NULL (semantically correct — UUID was never captured pre-migration). No backfill.
- **D-08:** Add index `(device_uuid, ts)` on `raw_evidence` as per ROADMAP success criteria.

### Claude's Discretion
- Column name in Rust structs (`RawEvidenceInput`, `RawEvidenceRow`, `DecodedFrameInput`, `DecodedFrameRow`): use `device_uuid: Option<String>`.
- Schema version number for this migration (continue from current highest).
- Exact SQL for bidirectional lookup in FastAPI (use `try/except ValueError` for UUID parse or regex).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Schema & Storage
- `Rust/core/src/store.rs` lines 1107–1145 — `raw_evidence` and `decoded_frames` CREATE TABLE statements; current column set and indexes
- `Rust/core/src/store.rs` lines 2177–2215 — `insert_raw_evidence` implementation; column list to extend with `device_uuid`
- `Rust/core/src/store.rs` lines 5079–5145 — `raw_evidence` and `raw_evidence_between` read paths; `RawEvidenceRow` struct
- `Rust/core/src/bridge.rs` lines 3590–3620 — `storage.raw_evidence_between` bridge method; response JSON shape

### iOS BLE & Queue
- `GooseSwift/GooseBLEClient.swift` lines 31–35 — existing UUID properties (`activeDeviceIdentifier`, `selectedDeviceID`, `rememberedDeviceID`)
- `GooseSwift/GooseBLEClient+CentralDelegate.swift` line 217 — `didConnect` log; UUID extraction point (`peripheral.identifier.uuidString`)
- `GooseSwift/CaptureFrameWriteQueue.swift` lines 60–75 — current `device_model` usage; where `currentDeviceUUID` property must be added
- `GooseSwift/GooseAppModel+Upload.swift` lines 150–175 — `device_model` extraction and upload payload construction; extend with `device_uuid`

### Server
- `server/db/init.sql` — server-side schema; `raw_evidence` table on TimescaleDB (separate from Rust SQLite schema)
- `server/ingest/` — FastAPI route implementations; where bidirectional lookup for `GET /v1/export/frames/{device_id}` lives

### Requirements
- `.planning/REQUIREMENTS.md` §Device ID Namespace — DEVID-01, DEVID-02 (source of truth for success criteria)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GooseBLEClient.rememberedDeviceID: UUID?` — existing UUID storage pattern in UserDefaults (key `goose.swift.rememberedDeviceID`); device_uuid_map follows same approach
- `CaptureFrameWriteQueue.deviceModel: String` — property updated by GooseAppModel at connect; `currentDeviceUUID: String?` follows identical pattern
- `store.rs ensure_raw_evidence_columns()` — existing migration shim at line 1756; new `device_uuid` column can be added here with `ALTER TABLE IF NOT EXISTS`

### Established Patterns
- Bridge args structs (`RawEvidenceInput`) use `Option<String>` for nullable fields; `device_uuid` follows this
- Schema migrations via `ensure_*_columns()` helper methods (incremental ALTER TABLE) — used throughout `store.rs`
- UserDefaults keys: `static let` on enclosing type, reverse-DNS format (`goose.swift.device_uuid_map`)

### Integration Points
- `GooseBLEClient+CentralDelegate.didConnect` → sets `GooseBLEClient.connectedPeripheralUUID` → `GooseAppModel` reads in connect handler → updates `CaptureFrameWriteQueue.currentDeviceUUID`
- `GooseUploadService.performUpload` reads `device_model` from frame data → extend to also include `device_uuid` from UserDefaults map
- `GET /v1/export/frames/{device_id}` in FastAPI → bidirectional SQL: `WHERE device_uuid = ? OR (device_uuid IS NULL AND device_model = ?)`

</code_context>

<specifics>
## Specific Ideas

- `device_uuid` is nullable on both SQLite (Rust) and TimescaleDB (server) — existing rows are NULL without any backfill
- CoreBluetooth UUID is a stable per-device-per-phone UUID; it changes only when the user removes the device from iOS Bluetooth settings
- UUID format check for server-side bidirectional lookup: Python `uuid.UUID(device_id)` wrapped in try/except ValueError; if raises → treat as device_model string

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 47-Device ID Namespace Resolution*
*Context gathered: 2026-06-10*
