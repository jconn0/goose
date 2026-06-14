# Phase 84: MetricKit Performance Monitoring + Self-Hosted Server — Context

**Gathered:** 2026-06-14
**Status:** Ready for execution
**Mode:** Planned

<domain>

## Phase Boundary

Two linked deliverables:

1. **METRIC-01**: Set up the self-hosted FastAPI + TimescaleDB server on the local WiFi network (Docker Compose on a machine reachable from the iPhone)
2. **METRIC-02**: iOS MetricKit integration — collect `MXMetricPayload` and `MXCrashDiagnosticPayload`, persist locally, upload to server, and display an on-device "App Health" dashboard

The app currently has zero crash reporting, zero performance monitoring, and zero analytics. The server stack exists in the repo but has never been deployed.

</domain>

<constraints>

- **No Rust changes** — only Swift (iOS), Python (server), and SQL (TimescaleDB schema)
- **No new external dependencies on iOS** — use `MetricKit.framework` (built-in), `URLSession` (already used), existing `GooseRustBridge` (for local persistence via `metric_series.upsert`)
- **No external dependencies on server** — already uses FastAPI + psycopg + TimescaleDB via Docker
- **Same-WiFi only** for v1 — server runs on LAN, phone reaches it via private IP (HTTP allowed by `RemoteServerURLValidator`)
- **Data must never be lost** — all metrics retained locally in SQLite before upload, same as biometric data

</constraints>

<decisions>

## Implementation Decisions

### METRIC-01: Server deployment model
- Server runs via `docker compose up -d` on a machine on the same WiFi as the phone
- Phone configures `http://192.168.X.X:8770` in the app's Remote Server settings
- HTTP is allowed for private IPs (existing `RemoteServerURLValidator` logic)
- No Tailscale/HTTPS needed for v1 — this is LAN-only

### METRIC-02: MetricKit data model on-device
- **Do NOT modify Rust** — use existing `metric_series.upsert` bridge method for individual scalar metrics (source: `"metrickit"`)
- Flatten `MXMetricPayload` into named metrics:
  - `metrickit.cpu.seconds` — cumulative CPU time
  - `metrickit.memory.peak_mb` — peak memory footprint
  - `metrickit.memory.average_mb` — average memory
  - `metrickit.disk.writes_mb` — logical writes
  - `metrickit.launch.time_ms` — time to first draw (cold launch)
  - `metrickit.hang.ratio` — proportion of time hung
  - `metrickit.exit.type` — foreground/background exit type
  - `metrickit.battery.drain_ma` — average battery drain
  - `metrickit.thermal.state` — thermal state
  - `metrickit.network.wifi_rx_mb` — WiFi bytes received
  - `metrickit.network.wifi_tx_mb` — WiFi bytes sent
  - `metrickit.network.cell_rx_mb` — cellular bytes received
  - `metrickit.network.cell_tx_mb` — cellular bytes sent
  - `metrickit.cell.condition` — cellular condition at time of transfer
- Flatten `MXCrashDiagnosticPayload` into:
  - `metrickit.crash.count` — incremented per crash diagnostic received
  - Full crash JSON stored as a file in `Documents/GooseSwift/metrickit/crashes/` for debugging

### METRIC-02: Upload path
- Add a new upload path alongside the existing biometric upload — does NOT reuse `GooseUploadService` biometric flow (which queries Rust for streams and marks rows synced)
- Instead: create `MetricKitUploader` in `GooseAppModel+Upload.swift` that POSTs aggregated metrics JSON to a new endpoint `POST /v1/app-metrics`
- Same server URL + Bearer token from settings
- Same retry pattern (exponential backoff, `isNetworkReachable` gate)
- No watermark needed — each upload is the daily aggregated payload, idempotent via `ON CONFLICT DO NOTHING` on server

### METRIC-01: Server schema
- New TimescaleDB hypertable `app_metrics` — one row per phone-day
- One `(device_id, date)` PK to handle daily idempotency
- `raw_payload` JSONB column stores the full original payload for later re-extraction if new metrics are added

### METRIC-02: On-device view
- New `MetricKitDashboardView` under the **More** tab as an "App Health" route
- Reads from local SQLite via existing `metric_series.query_range` bridge method
- Shows crash count, memory peak (line chart), launch time, hang rate over last 7/30 days
- Follows the `HealthDashboardViews.swift` card layout pattern

</decisions>
