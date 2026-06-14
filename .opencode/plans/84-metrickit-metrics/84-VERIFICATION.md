# Phase 84: MetricKit Performance Monitoring + Self-Hosted Server — Verification

(To be filled in during execution)

## METRIC-01: Server Setup (LAN)

| Check | Status |
|-------|--------|
| `docker compose up -d` starts without errors | |
| `curl http://<lan-ip>:8770/healthz` returns `{"status":"ok"}` | |
| `curl http://<lan-ip>:8770/v1/app-metrics` (no auth) returns 401 | |
| `curl -H "Authorization: Bearer <key>" http://<lan-ip>:8770/v1/app-metrics` works | |
| Phone can reach server (app shows green reachable indicator) | |
| Phone uploads biometric data successfully (rows appear in TimescaleDB) | |

## METRIC-02: iOS MetricKit Subscription + Upload

| Check | Status |
|-------|--------|
| `MXMetricManager.shared.add(self)` called in `GooseAppModel.init()` | |
| `didReceive(_:)` fires on next launch or within 24h | |
| `metric_series.upsert` rows appear in SQLite (source=`metrickit`) | |
| Crash diagnostic files appear in `Documents/GooseSwift/metrickit/crashes/` | |
| `POST /v1/app-metrics` called with valid payload via `MetricKitUploader` | |
| Retry works — if server is offline, data is not lost, re-uploaded on reconnect | |
| `ON CONFLICT` on server prevents duplicate rows on re-upload | |

## METRIC-02: App Health Dashboard

| Check | Status |
|-------|--------|
| "App Health" route appears in More tab | |
| View shows crash count for last 7 days | |
| View shows CPU / memory / launch time / hang rate trends | |
| View renders correctly in dark mode | |
| View respects dynamic type | |
| View works offline (reads from local SQLite, not server) | |

## No Regressions

| Check | Status |
|-------|--------|
| Existing biometric upload still works | |
| Existing More tab routes unchanged | |
| App cold launch time not regressed (MetricKit subscription is lightweight) | |
| `docker compose up` with new schema works on fresh DB | |
| `docker compose up` with existing DB (migration idempotent) works | |
