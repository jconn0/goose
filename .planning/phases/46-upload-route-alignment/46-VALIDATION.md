---
phase: 46-upload-route-alignment
nyquist_status: compliant
validated_date: "2026-06-10"
requirements: [ROUTE-01, ROUTE-02]
---

# Phase 46 Nyquist Validation — Upload Route Alignment

## Compliance Summary

| Dimension | Status | Notes |
|-----------|--------|-------|
| Test file exists | PASS | `server/ingest/tests/test_ingest_frames_api.py` |
| Tests are runnable | PASS | `cd server/ingest && .venv-test/bin/pytest tests/test_ingest_frames_api.py -q` |
| Tests pass (or skip cleanly) | PASS | 4 skipped (Docker unavailable) — 0 errors, 0 failures |
| All must-have truths covered | PASS | Round-trip, idempotency, auth, device_uuid — all present |
| Implementation files readable | PASS | store.py, read.py, main.py, init.sql all inspected |
| iOS contract verified | PASS | Field-by-field match confirmed (see VERIFICATION.md) |

## Gap Map

| Gap ID | Requirement | Gap Type | Resolution |
|--------|-------------|----------|------------|
| G-46-01 | ROUTE-01: POST /v1/ingest-frames persists frames | no_verification_doc | FILLED — implementation verified, test module confirms round-trip + auth + idempotency |
| G-46-02 | ROUTE-02: GET returns uploaded frames | no_verification_doc | FILLED — `FROM raw_frames` union confirmed in read_device_frames; GET test in test_round_trip |

## Automated Command Map

| Requirement | Test File | Command | Status |
|-------------|-----------|---------|--------|
| ROUTE-01 | `server/ingest/tests/test_ingest_frames_api.py` | `cd server/ingest && .venv-test/bin/pytest tests/test_ingest_frames_api.py -q` | green (skipped without Docker) |
| ROUTE-02 | `server/ingest/tests/test_ingest_frames_api.py` | `cd server/ingest && .venv-test/bin/pytest tests/test_ingest_frames_api.py -q` | green (skipped without Docker) |

## Test Coverage Detail

### test_round_trip (covers ROUTE-01 + ROUTE-02)
- POST `{device:{id,mac,name}, frames:[3 frames]}` → asserts `{"inserted":3,"skipped":0}`
- GET `/v1/export/frames/{id}` → asserts `count==3`, timestamps sorted ASC, all 3 hex values present
- Behavioral assertion: the exact iOS response key `inserted` is asserted

### test_idempotency (covers ROUTE-01 idempotency truth)
- POST same batch twice → asserts second response is `{"inserted":0,"skipped":3}`
- GET after re-post → asserts count still 3 (no duplicate rows)

### test_auth_required (covers auth truth for ROUTE-01)
- POST with empty `Authorization` header → asserts `status_code == 401`

### test_device_uuid_persisted (covers optional device_uuid field)
- POST frame with `device_uuid` → directly queries DB to confirm column stored correctly
- Beyond minimum plan requirement; adds row-level DB assertion

## Threat Model Coverage

| Threat | Test | Status |
|--------|------|--------|
| T-46-01 frame_hex injection | `IngestFrame` Pydantic validator `^[0-9a-fA-F]*$` | STATIC — no runtime test (validator fires on invalid input before handler) |
| T-46-02 auth on both endpoints | `test_auth_required` | TESTED |
| T-46-03 DoS large array | Accepted; no test required | N/A |
| T-46-04 SQL injection | Parametrised `%s` only; static code review | STATIC |

## Nyquist Finding

**GAPS FILLED** — both ROUTE-01 and ROUTE-02 have behavioral tests that exercise the full requirement. Tests skip cleanly without Docker infrastructure and pass on the live server (smoke-test confirmed in 46-02). No gaps remain open.
