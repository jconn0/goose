# SEED-002: MetricKit Integration Pattern

A reusable pattern for collecting, persisting, uploading, and displaying Apple MetricKit performance data.

## When to use

Any iOS target that needs zero-dependency, privacy-preserving app performance monitoring — CPU, memory, disk, launch time, battery drain, hang rate, crash diagnostics — without third-party SDKs.

## Architecture

```
MXMetricManagerSubscriber.didReceive(payloads: [MXMetricPayload])
    |
    +-- For each payload:
    |     +-- Extract scalars: CPU sec, mem peak MB, disk MB, launch ms, hang ratio, etc.
    |     +-- Extract MXCrashDiagnostic: crash type, signal, exception, stack traces
    |     |
    |     +-- Persist scalars -> metric_series.upsert(database_path, "metrickit", name, date, value)
    |     |     (uses existing Rust bridge, no new Rust code)
    |     |
    |     +-- Persist crash report -> Documents/GooseSwift/metrickit/crashes/<date>-<uuid>.json
    |     |     (crash payloads contain stack traces, too large for metric_series)
    |     |
    |     +-- Queue daily aggregate for upload
    |
    +-- On next upload cycle:
          POST /v1/app-metrics { device, metrics: { cpu, memory, ... }, app_version, os_version }
```

## Key types

| Swift type | Purpose |
|---|---|
| `MXMetricPayload` | Daily delivery of CPU, memory, disk, launch, hang, battery, network, display metrics |
| `MXCrashDiagnosticPayload` | On-launch delivery of crash reports (signal, exception, stack frames) |
| `MXAppExitMetric` | Foreground/background exit reasons (normal, crash, watchdog, etc.) |
| `MXSignpostMetricData` | Custom os_signpost intervals (not used in v1, available for future instrumentation) |

## Metric name convention

Source key always `"metrickit"`. Metric names snake_case, dot-delimited:

```
metrickit.cpu.seconds
metrickit.memory.peak_mb
metrickit.memory.average_mb
metrickit.disk.writes_mb
metrickit.launch.time_ms
metrickit.hang.ratio
metrickit.exit.type
metrickit.battery.drain_ma
metrickit.thermal.state
metrickit.network.wifi_rx_mb
metrickit.network.wifi_tx_mb
metrickit.network.cell_rx_mb
metrickit.network.cell_tx_mb
metrickit.cell.condition
metrickit.crash.count
```

## Server storage

```sql
CREATE TABLE IF NOT EXISTS app_metrics (
    device_id         TEXT NOT NULL,
    date              DATE NOT NULL,
    app_version       TEXT,
    os_version        TEXT,
    cpu_seconds       REAL,
    memory_peak_mb    REAL,
    memory_average_mb REAL,
    disk_writes_mb    REAL,
    launch_time_ms    REAL,
    hang_time_ratio   REAL,
    exit_type         TEXT,
    average_battery_drain_ma REAL,
    thermal_state     TEXT,
    wifi_rx_mb        REAL,
    wifi_tx_mb        REAL,
    cell_rx_mb        REAL,
    cell_tx_mb        REAL,
    cell_condition    TEXT,
    crash_count       INTEGER DEFAULT 0,
    raw_payload       JSONB,
    received_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, date)
);
SELECT create_hypertable('app_metrics', 'received_at', if_not_exists => TRUE);
```

## Server endpoint

```
POST /v1/app-metrics
Authorization: Bearer <api-key>
{
  "device": { "id": "..." },
  "date": "2026-06-14",
  "metrics": { ... },
  "app_version": "0.1.0",
  "os_version": "26.0"
}
```

Returns `{"inserted": true}` on success, `{"inserted": false}` on conflict (idempotent).

## On-device querying

Use `metric_series.query_range`:

```swift
let result = try await bridge.requestAsync(
    method: "metric_series.query_range",
    args: ["database_path": db, "source": "metrickit",
           "metric_name": "metrickit.memory.peak_mb",
           "start_date": sevenDaysAgo, "end_date": today]
)
```

## Verification checklist

- [ ] `MXMetricManager.shared.add(self)` called in `init()`
- [ ] `didReceive(_:)` fires (test by running on device for 24h or forcing a launch after crash)
- [ ] Scalar metrics appear in SQLite `metric_series` table
- [ ] Crash payloads appear as JSON files in Documents
- [ ] Upload POSTs to server successfully
- [ ] Server returns 200 on first upload, 200 on re-upload (idempotent)
- [ ] App Health view renders valid data
