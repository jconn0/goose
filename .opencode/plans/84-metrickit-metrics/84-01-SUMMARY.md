---
phase: 84-metrickit-metrics
plan: 01
subsystem: server, ios, app-health
tags: [metrickit, performance, monitoring, server-setup, crash-reporting, dashboard]

requires: []
provides:
  - Self-hosted FastAPI + TimescaleDB server running on LAN (Docker Compose)
  - MetricKit subscription that collects CPU/memory/disk/launch/hang/battery/crash data
  - Local persistence of metrics in SQLite via existing `metric_series.upsert` bridge
  - Upload path from iOS → server (`POST /v1/app-metrics`)
  - New TimescaleDB `app_metrics` hypertable with `raw_payload` JSONB
  - "App Health" dashboard view on-device in More tab
affects: [app-startup, background-tasks, more-tab, server-schema]

tech-stack:
  added:
    - "MetricKit.framework (built-in iOS 13+)"
  patterns:
    - "MXMetricManagerSubscriber conformance on @MainActor class"
    - "metric_series.upsert with source='metrickit' for scalar persistence"
    - "POST /v1/app-metrics with same Bearer auth as biometric endpoints"
    - "TimescaleDB hypertable + ON CONFLICT DO NOTHING for idempotency"

key-files:
  created:
    - GooseSwift/MetricKitModels.swift
    - GooseSwift/MetricKitDashboardViews.swift
    - .planning/seeds/SEED-002-metrickit-pattern.md
  modified:
    - server/db/init.sql
    - server/ingest/app/main.py
    - server/ingest/app/store.py
    - server/ingest/app/read.py
    - GooseSwift/GooseAppModel.swift
    - GooseSwift/GooseAppModel+Upload.swift
    - GooseSwift/MoreView.swift

key-decisions:
  - "Rust bridge unchanged — metric_series.upsert already exists for scalar storage"
  - "Crash payloads stored as JSON files in Documents/GooseSwift/metrickit/crashes/ (too large for metric_series)"
  - "App Health view reads from SQLite locally, not from server — zero latency, works offline"
  - "Server endpoint stores raw_payload JSONB for future re-extraction"
  - "Same-WiFi only: HTTP allowed on private IPs by existing URLValidator"

patterns-established:
  - "MetricKit flattening: each sub-metric becomes a metric_series row with source='metrickit'"
  - "Daily aggregate upload: one POST per day per device, idempotent on (device_id, date)"

requirements-completed: []
