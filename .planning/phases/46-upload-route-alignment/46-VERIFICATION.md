---
phase: 46-upload-route-alignment
status: passed
verified_date: "2026-06-10"
requirements: [ROUTE-01, ROUTE-02]
---

# Phase 46 Verification — Upload Route Alignment

## Status: PASSED

All must-have truths from the 46-01-PLAN.md are satisfied by the implementation.

## Must-Have Truth Checks

| # | Truth | Evidence | Result |
|---|-------|----------|--------|
| 1 | POST /v1/ingest-frames accepts the iOS payload `{device:{id,mac,name}, frames:[...]}` and returns `{inserted, skipped}` | `IngestFramesBatch`, `IngestFramesDevice`, `IngestFrame` models in `server/ingest/app/main.py` lines 432–450; route at line 453 returns `store.insert_raw_frames_batch` result which is `{"inserted": N, "skipped": M}` | PASS |
| 2 | Uploaded frames are idempotent: re-posting the same frames inserts 0 new rows | `ON CONFLICT (device_id, captured_at, frame_hex) DO NOTHING` in `server/ingest/app/store.py` line 54; `raw_frames_dedup` unique index in `server/db/init.sql` | PASS |
| 3 | POST /v1/ingest-frames requires Bearer auth (401 without it) | `@app.post("/v1/ingest-frames", dependencies=[Depends(require_auth)])` in `main.py` line 453; `require_auth` raises 401 via `secrets.compare_digest` | PASS |
| 4 | GET /v1/export/frames/{device_id} returns frames uploaded via POST (round-trip works) | `read_device_frames` in `server/ingest/app/read.py` line 379 SELECTs from `raw_frames` and merges with archive results | PASS |
| 5 | GET frames are ordered by captured_at_unix ASC with the iOS import shape | Python merge-sort in `read_device_frames` on `captured_at_unix`; shape keys `captured_at_unix, frame_hex, source, device_model, device_type, sensitivity` preserved | PASS |

## Artifact Checks

| Artifact | Required Content | Found |
|----------|-----------------|-------|
| `server/db/init.sql` | `CREATE TABLE IF NOT EXISTS raw_frames` | YES (line 108) |
| `server/db/init.sql` | `create_hypertable('raw_frames', ...)` | YES (line 117) |
| `server/db/init.sql` | `raw_frames_device_time` index | YES (line 118) |
| `server/ingest/app/store.py` | `def insert_raw_frames_batch` | YES (line 36) |
| `server/ingest/app/read.py` | `FROM raw_frames` | YES (line 379) |
| `server/ingest/app/main.py` | `"/v1/ingest-frames"` route | YES (line 453) |
| `server/ingest/tests/test_ingest_frames_api.py` | ≥3 `test_` functions | YES (4 functions) |
| `server/ingest/tests/conftest.py` | `raw_frames` in TRUNCATE | YES (line 70) |

## Schema Deviation (recorded from 46-02-SUMMARY.md)

The plan specified column name `ts`; the live server already had `captured_at`. Plan 02 corrected `store.py` and `read.py` to use `captured_at` and added `raw_frames_dedup` unique index instead of rebuilding the table (preserving 4674 existing rows). The final implementation uses `captured_at` throughout — init.sql, store.py, and read.py are consistent.

## iOS Contract Verification

| iOS field (GooseUploadService.swift) | Server model (IngestFrame) | Match |
|--------------------------------------|---------------------------|-------|
| `device.id / mac / name` | `IngestFramesDevice.id / mac / name` | YES |
| `frames[].captured_at_unix` | `IngestFrame.captured_at_unix: float` | YES |
| `frames[].frame_hex` | `IngestFrame.frame_hex: str` (hex pattern validated) | YES |
| `frames[].source / device_type / device_model / sensitivity` | optional fields | YES |
| Response `json["inserted"]` | `{"inserted": N, "skipped": M}` | YES |
| GET envelope `json["frames"]` | `{frames: [...], count: N}` | YES |
| GET route `v1/export/frames/{deviceID}` | `GET /v1/export/frames/{device_id}` | YES |

## Live Smoke-Test (from 46-02-SUMMARY.md, run against dockge.tigercraft4.com:8770)

| Test | Result |
|------|--------|
| POST /v1/ingest-frames (1 frame) | `{"inserted":1,"skipped":0}` |
| GET /v1/export/frames/smoketest | correct frame_hex + captured_at_unix |
| Re-POST (idempotency) | `{"inserted":0,"skipped":1}` |
| POST without Authorization | HTTP 401 |

## Automated Test Suite

Command: `cd server/ingest && .venv-test/bin/pytest tests/test_ingest_frames_api.py -q`

Result without Docker: `4 skipped in 1.11s` — no failures, no errors. Tests are correctly guarded by `@requires_docker` and skip cleanly in a non-Docker CI environment.

Tests defined:
- `test_round_trip` — POST 3 frames → `{inserted:3,skipped:0}`; GET returns all 3 sorted ASC
- `test_idempotency` — second POST → `{inserted:0,skipped:3}`; GET count stays 3
- `test_auth_required` — empty Authorization → 401
- `test_device_uuid_persisted` — optional `device_uuid` field round-trips to DB

## Requirements Coverage

| Requirement | Description | Status |
|-------------|-------------|--------|
| ROUTE-01 | POST /v1/ingest-frames accepts iOS payload and persists frames | SATISFIED |
| ROUTE-02 | Uploaded frames retrievable via GET /v1/export/frames/{device_id} | SATISFIED |
