# Feature Gap Implementation Ranking

> Every feature Goose lacks vs. WHOOP + Noop, ranked by implementation effort.
> Last updated: 2026-06-14

---

## Effort Scale

| Tier | Effort | Calendar Time |
|------|--------|---------------|
| **T0 — Trivial** | < 4 hours | Same day |
| **T1 — Easy** | 1–3 days | Same week |
| **T2 — Moderate** | 1–2 weeks | Same sprint |
| **T3 — Hard** | 2–4 weeks | 1–2 sprints |
| **T4 — Very Hard** | 1–3 months | Multi-sprint |
| **T5 — Blocked** | Unknown | RE / hardware / infra gate |

---

## T0 — Trivial (< 4 hours)

These are protocol facts, simple Rust additions, or single-view SwiftUI. Do several in a day.

| # | Feature | What to Build | Source to Check |
|---|---------|---------------|-----------------|
| 1 | **Puffin protocol framing** | Decode types 37/38/53/54/56 in Rust `protocol.rs` instead of RAW_ONLY | Noop `whoop_protocol.json` + PROTOCOL.md §3 |
| 2 | **CRC16-Modbus header check** | Add WHOOP 5.0 header CRC validation in Rust | Noop PROTOCOL.md §2.4 |
| 3 | **Rust DeviceType::MG variant** | Add `DeviceType::MG` to Rust core (currently aliased to `DeviceType::Goose`) | b-nnett PR #50 |
| 4 | **SELECT_WRIST command (123)** | Add BLE command + simple toggle in Device settings | Noop `WhoopCommand` enum |
| 5 | **GET_BODY_LOCATION_AND_STATUS (84)** | Add BLE command, parse response, surface in Device view | Noop `WhoopCommand` enum |
| 6 | **GET_EXTENDED_BATTERY_INFO (98)** | Add BLE command, expose mV + cycle data in Device view | Noop `WhoopCommand` enum |
| 7 | **GET_ALL_HAPTICS_PATTERN (80)** | Add BLE command, enumerate available patterns, show in debug | Noop `WhoopCommand` enum |
| 8 | **STOP_HAPTICS command (122)** | Add BLE command, wire to existing buzz primitive | Noop `WhoopCommand` enum |
| 9 | **Event: DOUBLE_TAP (14)** | Parse event, expose as `onDoubleTap` callback on GooseBLEClient | Noop PROTOCOL.md §4 |
| 10 | **Event: HAPTICS_FIRED (60)** | Parse event, confirm haptic commands worked | Noop PROTOCOL.md §4 |
| 11 | **Event: HAPTICS_TERMINATED (100)** | Parse event, confirm haptic completion | Noop PROTOCOL.md §4 |
| 12 | **Event: STRAP_DRIVEN_ALARM_SET (56)** | Parse event, confirm alarm was armed by strap | Noop PROTOCOL.md §4 |
| 13 | **Event: APP_DRIVEN_ALARM_EXECUTED (58)** | Parse event, confirm alarm fired | Noop PROTOCOL.md §4 |
| 14 | **Event: STRAP_DRIVEN_ALARM_DISABLED (59)** | Parse event, confirm alarm disabled | Noop PROTOCOL.md §4 |
| 15 | **Event: EXTENDED_BATTERY_INFO (63)** | Parse event, expose extended battery data | Noop PROTOCOL.md §4 |
| 16 | **Event: CAPTOUCH_AUTOTHRESHOLD (32)** | Parse event, observe cap sense auto-calibration | Noop PROTOCOL.md §4 |
| 17 | **Recovery impacts tile** | SwiftUI card on Recovery screen showing factors that drove score up/down | — |
| 18 | **LiveStrain home tile** | Persistent live strain accumulator on Home (not just during workout) | `DATA-02` already done for workouts |
| 19 | **In-app What's New changelog** | Simple scroll view + UserDefaults version gate | — |
| 20 | **Experimental settings toggle** | Settings toggle for MG protocol probes | — |

---

## T1 — Easy (1–3 days)

Straightforward features with clear scope. Mostly single-screen SwiftUI or single Rust module.

| # | Feature | What to Build | Source to Check |
|---|---------|---------------|-----------------|
| 21 | **Event: WRIST_ON / WRIST_OFF (9/10)** | Parse events, toggle `worn` state, expose via GooseBLEClient | Noop PROTOCOL.md §4 |
| 22 | **Event: STRAP_DRIVEN_ALARM_EXECUTED (57)** | ⚠️ **UNBLOCKS HAP-04** — parse event, feed to wake-window engine | Noop PROTOCOL.md §4, Goose HAP-04 gate |
| 23 | **Step calibration** | Per-user stride length tuning stored in UserDefaults | — |
| 24 | **Configurable notifications** | Replace 3 hardcoded NotificationScheduler triggers with per-metric threshold config | Noop `NotificationSettingsStore` |
| 25 | **Stress Calm Time stat** | Add "Calm Time" tile to Stress screen — simple aggregation of low-stress windows | — |
| 26 | **Stress Δ-baseline tiles** | Show deviation from personal stress baseline on Stress screen | — |
| 27 | **Stress range selector** | Date range picker on Stress screen | — |
| 28 | **Sleep need computation** | Replace fixed 480-min default with adaptive formula (age, activity, sleep debt) | WHOOP `/coaching-service/v1/sleepneed` |
| 29 | **Apple Health write-back** | Write Goose-computed metrics (HRV, RHR, SpO₂, sleep) back to HealthKit | — |
| 30 | **SpO₂ HealthKit export** | Write SpO₂ to HealthKit (`HKQuantityTypeIdentifierOxygenSaturation`) | — |
| 31 | **Battery fuel gauge improvements** | Add mV, cycle count, health % from extended battery events | Noop `GET_EXTENDED_BATTERY_INFO` |
| 32 | **K18 respiratory rate promotion** | Verify K18 byte semantics against ground truth, promote to score input | Goose `metric_readiness.rs` |
| 33 | **K25/K26 SpO₂ PIP parse** | Resolve pulse-information packet field, compute SpO₂ % | — |
| 34 | **Coach VOW card improvements** | Add rule-based VOW messages in Rust; improve card UI in Coach tab | — |
| 35 | **Morning report notification** | Schedule notification with sleep/recovery/strain summary after morning sync | WHOOP "Your morning report is ready" |

---

## T2 — Moderate (1–2 weeks)

Multi-file features, new SQLite tables, or significant new SwiftUI screens.

| # | Feature | What to Build | Source to Check |
|---|---------|---------------|-----------------|
| 36 | **Trends multi-range selector** | 30d, 90d, 6mo, 1yr date ranges on Trends screen (currently 7-day only) | Goose `metric_series` table exists |
| 37 | **YearHeatStrip heatmap** | Calendar heatmap SwiftUI component for year-view metrics | Noop `YearHeatStrip` |
| 38 | **Compare screen** | Dual metric overlay plot with shared timeline | Noop Compare screen |
| 39 | **Puffin events from strap (53/54)** | Full decode of WHOOP 5.0 relative puffin events and strap-pushed events | Noop `whoop_protocol.json` |
| 40 | **WHOOP CSV import** | Parse `physiological_cycles.csv`, `sleeps.csv`, `workouts.csv`, `journal_entries.csv` → SQLite | Noop `WhoopExportImporter` |
| 41 | **Nutrition CSV import** | Parse Cronometer/MacroFactor exports → SQLite | Noop nutrition import |
| 42 | **Journal UI** | Behavior selection, sliders, steppers, question banks + SQLite journal upsert | WHOOP Journal subsystem; Goose `journal` table exists |
| 43 | **Stress Monitor calibration** | Calibrating state + personal baseline computation for real stress monitor | WHOOP `stressMonitorCalibrating` |
| 44 | **Stress education content** | In-app education screens about stress/ANS | WHOOP `STRESS_MONITOR_IN_APP_EDUCATION` |
| 45 | **Coach local LLM support** | Add Ollama/LM Studio endpoint support to CoachChatModel | Noop local Coach |
| 46 | **SpO₂ computed calibration** | Calibrate raw red/IR values against WHOOP export ground truth, promote from "uncalibrated" | — |
| 47 | **Skin temp computed calibration** | Calibrate raw values against WHOOP export, compute deviation from baseline | — |

---

## T3 — Hard (2–4 weeks)

Complex subsystems with new Rust modules, multi-screen SwiftUI, or significant algorithm work.

| # | Feature | What to Build | Source to Check |
|---|---------|---------------|-----------------|
| 48 | **Real-time Stress Monitor** | Calibrated personal baseline + live monitoring + intervention suggestions | WHOOP `ENTITLEMENT_STRESS_MONITOR` |
| 49 | **Sleep Coach wizard** | Scheduling/onboarding, alarm type selector (Exact/Range), education, optimal sleep, wake-time config | WHOOP Sleep Coach (~30 tracked interactions) |
| 50 | **Coach WPA/MPA reports** | Weekly/Monthly Performance Assessment report generation | WHOOP `/coaching-service/v1/performance-assessment/` |
| 51 | **Integrations hub** | OAuth flow for Strava, activity sync, deauth | WHOOP Strava integration |
| 52 | **ECG waveform display** | Live K16/K17 trace rendering in SwiftUI | Goose K16/K17 partial decode exists |
| 53 | **ECG taking UI** | On-demand recording flow with countdown + save | WHOOP `TakeAnECGSectionModel` |
| 54 | **ECG results / classification** | Sinus Rhythm, Inconclusive, Unreadable, Low/High HR classification | WHOOP Labrador |
| 55 | **Menstrual cycle tracking** | Period prediction, cycle-phase coaching, calendar UI | WHOOP menstrual subsystem |
| 56 | **Pregnancy insights** | Trimester tracking, pregnancy coaching, notification screens | WHOOP pregnancy subsystem |
| 57 | **Blood Pressure monitoring** | Relative BP computation + manual entry + HealthKit integration | WHOOP Sage/BP |
| 58 | **AdvancedHaptic / HapticHeartbeat** | ⚠️ RE-gated: discover pattern values from WHOOP IPA | Goose HAP-01 exists (basic buzz) |

---

## T4 — Very Hard (1–3 months)

Major subsystems requiring new Rust modules, BLE protocol work, and comprehensive testing.

| # | Feature | What to Build | Source to Check |
|---|---------|---------------|-----------------|
| 59 | **ECG history + past recordings** | Recording list, detail view, symptoms, notes, share | WHOOP `AllRecordingsScreen` |
| 60 | **ECG PDF report** | Generate PDF report from ECG recording | WHOOP `LabradorReadingReportPDF` |
| 61 | **HeartKey analysis engine** | Stress score, HRV, HR, signal quality, arrhythmia check — port from WHOOP IPA | WHOOP HeartKey |
| 62 | **AFib detection (Shepherd)** | Arrhythmia screening, history, onboarding, notifications, regulatory info | WHOOP Shepherd module |
| 63 | **Healthspan / WHOOP Age** | Pace of Aging computation, impact cards, education | WHOOP `ENTITLEMENT_HEALTHSPAN` |
| 64 | **Advanced Labs / Biomarkers** | Blood test scheduling, results upload, biomarker tracking, clinical reports | WHOOP Sanguine |
| 65 | **Smart alarm wake-window engine** | Lightest-sleep firing within time window. RE-gated: needs BTSnoop capture of `SetAlarmInfoCommandPacketRev4` + `STRAP_DRIVEN_ALARM_EXECUTED` decode | Goose HAP-04 |

---

## T5 — Blocked (Cannot estimate)

Gated by reverse engineering, unknown hardware protocol, or missing test hardware.

| # | Feature | Blocker | Unblock When |
|---|---------|---------|-------------|
| 66 | **Firmware OTA** | FIRMWARE_UPDATE command blocked — safety concern | Protocol audit of destructive commands |
| 67 | **On-wrist cap sense detection** | GATT UUID for capacitive sensor unknown (Phase 66 hardware-gated) | BTSnoop capture of WHOOP app on real MG device |
| 68 | **CALIBRATE_CAPSENSE (100)** | Same hardware gate as above — needs working cap sense first | Same as #67 |
| 69 | **ECG production vs clinical modes** | Unknown how WHOOP switches between modes | RE of WHOOP Labrador module |
| 70 | **ECG upload to cloud** | Requires WHOOP cloud API — out of scope for offline app | Would need `/ecg-service/v1/ecg/metric/mobile` |
| 71 | **ECG terms of use / registration** | Legal/regulatory — ECG is FDA-regulated | Legal review needed |

---

## Summary: Best ROI by Effort

### Morning's Work (T0 — do 5–10 in a day)
Puffin framing, CRC16-Modbus, SELECT_WRIST, GET_BODY_LOCATION, GET_EXTENDED_BATTERY, GET_ALL_HAPTICS_PATTERN, STOP_HAPTICS, all 8 event handlers, Recovery impacts tile, LiveStrain home tile, DeviceType::MG variant.

### Week's Work (T1 — do 3–5 in a week)
WRIST_ON/OFF events, STRAP_DRIVEN_ALARM_EXECUTED (unblocks HAP-04!), step calibration, configurable notifications, sleep need, HealthKit write-back, battery gauge, morning report notification.

### Sprint's Work (T2 — pick 1–2 per sprint)
Trends multi-range, WHOOP CSV import, Journal UI, Compare screen, Stress Monitor calibration, Coach local LLM, K18 promotion, SpO₂ calibration.

### Major Milestone (T3 — 1 per milestone)
Real-time Stress Monitor, Sleep Coach wizard, ECG waveform UI, Menstrual tracking, Integrations hub.

### Avoid Until Unblocked (T4–T5)
HeartKey, AFib Shepherd, Healthspan, Advanced Labs, Firmware OTA, On-wrist cap sense — all gated by RE, hardware, or regulatory.

---

## Quick-Start: Highest Value + Lowest Effort

| # | Feature | Tier | Why |
|---|---------|------|-----|
| 22 | STRAP_DRIVEN_ALARM_EXECUTED event | T1 | **Unblocks HAP-04 wake-window** — already RE-gated |
| 1 | Puffin protocol framing | T0 | Unblocks MG packet decode for 5 types |
| 21 | WRIST_ON/OFF events | T1 | On-wrist detection without cap sense hardware |
| 32 | K18 respiratory rate promotion | T2 | Unblocks respiratory rate as production metric |
| 17 | Recovery impacts tile | T0 | Visible UX win, small effort |
| 4 | SELECT_WRIST command | T0 | Completes device config |
