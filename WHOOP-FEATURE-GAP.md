# Goose vs. WHOOP — Complete Feature Gap Analysis

> Comparing Goose (current `feature/xcuitest-ci`) against the real WHOOP app across all membership tiers (One, Peak, Life/MG).
> Generated 2026-06-14 from live codebase verification.

---

## Pre-Implementation Checklist

**Before starting ANY feature implementation, check these three upstream sources to avoid duplicate work:**

### 1. NoopApp/noop — https://github.com/NoopApp/noop
- **Status:** v3.0.0 "Titanium & Gold", 1.7k stars, 714 forks, 303 commits, actively maintained
- **What they have that Goose might implement:**
  - Breathe screen (HRV haptic biofeedback — Goose has this via Phase 79)
  - Interval Timer (silent haptic HIIT — Goose has this via Phase 71)
  - Smart Alarm with wake-window engine (Goose: basic alarm, wake-window RE-gated)
  - Metric Explorer/Compare/Correlation engine
  - Daily mood check-in journal
  - Automations (double-tap → Mac action, wear/presence detection)
  - Apple Health + WHOOP CSV import
  - Trends (long-range, multi-metric)
  - YearHeatStrip heatmap
  - Menu-bar extra (macOS)
  - **Full Puffin protocol framing** (types 37/38/53/54/56 — Goose is RAW_ONLY)
- **Key protocol docs:** `docs/PROTOCOL.md`, `whoop_protocol.json`
- **License:** PolyForm Noncommercial 1.0.0 (⚠️ copy code only if license-compatible)

### 2. b-nnett/goose (upstream) — https://github.com/b-nnett/goose
- **Status:** Active — 17 open PRs as of 2026-06-14
- **Notable open PRs to review before implementing:**
  | PR | Author | Area |
  |----|--------|------|
  | [#50](https://github.com/b-nnett/goose/pull/50) | naz3eh | WHOOP MG support + BLE frame parsing in pure Swift |
  | [#31](https://github.com/b-nnett/goose/pull/31) | castanley | Fix scroll jitter (display-safety filter at ingestion) |
  | [#29](https://github.com/b-nnett/goose/pull/29) | iamkishann | Reduce main thread load (perf) |
  | [#27](https://github.com/b-nnett/goose/pull/27) | virajshoor | Fix backend live capture storage lag |
  | [#26](https://github.com/b-nnett/goose/pull/26) | jakobrmarrone | WHOOP 4.0 (Gen4) historical sync support |
  | [#19](https://github.com/b-nnett/goose/pull/19) | po-sc | WHOOP 4.0 (Gen4) BLE support + stability/perf fixes |
  | [#18](https://github.com/b-nnett/goose/pull/18) | regulapati-n | Exponential backoff + attempt limits for BLE reconnection |
  | [#15](https://github.com/b-nnett/goose/pull/15) | kobemartin | Block state-changing debug deep links |
  | [#13](https://github.com/b-nnett/goose/pull/13) | Maloron | Fix Rust core integration tests + Windows compat |
  | [#12](https://github.com/b-nnett/goose/pull/12) | Maloron | Optimize FFI bridge serialization + move blocking calls to background |
  | [#10](https://github.com/b-nnett/goose/pull/10) | anup4khandelwal | Rust core CI workflow |
  | [#7](https://github.com/b-nnett/goose/pull/7) | Sanjays2402 | `core.list_methods` RPC for method discovery |
  | [#5](https://github.com/b-nnett/goose/pull/5) | apurv-1 | Apple Health fallback for sleep/recovery/strain/vitals |
  | [#4](https://github.com/b-nnett/goose/pull/4) | apurv-1 | Reduce scroll frame drops on Home/Health views |
- **Process:** Each PR should be evaluated for merge conflicts, feature overlap, and code quality before starting parallel work

### 3. tigercraft4/goose — https://github.com/tigercraft4/goose
- **Status:** Active fork — focusing on CI/release infrastructure (AltStore distribution), seed documentation, and milestone management
- **Recent work (last 15 commits):** Release notes automation, AltStore source updates, CI fixes for Release builds, architectural seed documentation
- **No open PRs** — feature work primarily tracked via seeds and milestone planning
- **Process:** Check their branches (not just `main`) for any feature work-in-progress; coordinate on overlapping features

### Checklist (before starting any feature)
- [ ] Searched NoopApp/noop for existing implementation of this feature
- [ ] Reviewed relevant open PRs on b-nnett/goose for overlap
- [ ] Checked tigercraft4/goose branches for WIP on same feature
- [ ] If implementation exists elsewhere: evaluated license compatibility and integration cost vs building from scratch
- [ ] Documented decision in phase plan or seed

---

## Membership Tier Context

| Tier | Price/yr | Key Features | MG Required? |
|------|----------|-------------|-------------|
| **WHOOP One** | ~$199 | Sleep, strain, recovery, HR zones, basic coach | No |
| **WHOOP Peak** | ~$239 | + Healthspan, Pace of Aging, Health Monitor with alerts, Stress Monitor | No |
| **WHOOP Life** | ~$359 | + ECG, AFib, Blood Pressure, Advanced Labs | **Yes** |

---

## 1. Core Metrics & Scoring

### 1.1 Strain Score

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Daily strain (0–21) | ✅ Packet-derived + HealthKit eTRIMP fallback | ✅ Proprietary | Algorithm differs; not WHOOP's exact formula |
| Live accumulating strain during workout | ✅ (Phase 79) | ✅ | Parity achieved |
| LiveStrain home tile (persistent) | ❌ | ✅ | Home tile showing real-time strain outside workouts |
| Optimal strain target | ✅ Local heuristic from recovery | ✅ Server-side mapping per cycle | WHOOP uses `/coaching-service/v1/coaching/strain/optimal/mapping/cycle/` |

### 1.2 Recovery Score

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Recovery V0 (packet features) | ✅ `metrics.recovery_score_from_features` | — | Goose's own |
| Recovery V1 (EWMA personal baseline) | ✅ `metrics.goose_recovery_v1` | ✅ Proprietary | Goose's own, not WHOOP's formula |
| HRV/RHR baselines | ✅ Seed 4 nights, mature 7, trusted 14 | ✅ | Parity |
| Recovery colour bands | ✅ Green/yellow/red | ✅ | Parity |
| Recovery impacts tile | ❌ | ✅ | Shows what factors drove recovery up/down |
| Apple Health fallback | ✅ 6-component weighted formula | — | Goose-only |

### 1.3 Sleep Score

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Sleep scoring | ✅ Goose V1 model | ✅ Proprietary | Goose's own algorithm, not WHOOP's |
| 4-class sleep staging | ✅ Cole-Kripke + cardiorespiratory | ✅ | Different staging method |
| Sleep debt / Tonight recommendation | ✅ | ✅ | |
| Sleep need computation | ⚠️ Fixed 480-min default | ✅ Adaptive server-side | WHOOP uses `/coaching-service/v1/sleepneed` |
| Sleep consistency tracking | ✅ Bed/wake/midpoint deviation | ✅ | |
| Sleep Bank / cumulative tracking | ⚠️ Shell only | ✅ | |
| **Sleep Coach** (dedicated wizard) | ⚠️ Route views | ✅ Full subsystem | WHOOP has scheduling, alarm types, education, onboarding, optimal sleep |

### 1.4 Cardio Load

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| ACWR calculation | ✅ 7-day acute / 28-day chronic | ✅ | |
| Training status bands | ✅ 7 bands (Calibrating→Overtraining) | ✅ | |
| Session load computation | ⚠️ Banister eTRIMP + zone-minutes | ✅ Proprietary | Not WHOOP's exact cardio load formula |
| Calibration progress | ✅ Weekly calibration view | ✅ | |

### 1.5 Stress

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Local HR-proxy stress | ✅ HR pressure + volatility heuristic | — | Goose-only local proxy |
| **Real-time Stress Monitor** | ❌ | ✅ | WHOOP Life gated; calibrated personal baseline |
| Stress calibration state | ❌ | ✅ `stressMonitorCalibrating` | |
| Stress intervention suggestions | ❌ | ✅ `STRESS_MONITOR_INTERVENTION` | |
| Stress education content | ❌ | ✅ `STRESS_MONITOR_IN_APP_EDUCATION` | |
| Stress VoW messages | ❌ | ✅ `StressVoW` | |

### 1.6 Energy Bank

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Energy charge/drain from stress windows | ✅ | ✅ | |
| Energy daily rollup | ✅ | ✅ | |

### 1.7 Readiness V1 (ACWR)

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| ACWR from 28-day strain | ✅ | — | Goose's own readiness metric |
| Foster monotony | ✅ | — | |

---

## 2. Vitals & Biometrics

### 2.1 Heart Rate

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Live HR (BLE 0x180D) | ✅ | ✅ | |
| HR zones | ✅ 5-zone system | ✅ | |
| Resting HR baseline | ✅ EWMA, 4-14 night maturation | ✅ | |
| HR during sleep | ✅ HR dip %, avg, min | ✅ | |

### 2.2 HRV

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| RMSSD from RR intervals | ✅ | ✅ | |
| HRV baseline (personal) | ✅ Provisional 4 nights, trusted 14 | ✅ | |
| Frequency-domain HRV (LF/HF) | ❌ | ❌ | WHOOP doesn't expose either |

### 2.3 Respiratory Rate

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| K18 historical candidate | ⚠️ Detected but unverified | ✅ | Field at body offset 26 — plausible but semantics unverified |
| V24 raw decode | ✅ Raw/100 RPM | ✅ | |
| Computed/promoted respiratory rate | ❌ Blocked | ✅ | `respiratory_rate_semantics_unverified` blocker |
| HealthKit fallback | ✅ | ✅ | |
| Respiratory rate elevated alert | ❌ | ✅ | |

### 2.4 SpO₂ (Blood Oxygen)

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Raw ADC (red + IR channels) | ✅ V24 decode | ✅ | |
| Computed SpO₂ % | ⚠️ Server-side, uncalibrated | ✅ Proprietary calibration | K25/K26 PIP field unresolved |
| SpO₂ HealthKit export | ❌ | ✅ | |

### 2.5 Skin Temperature

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Raw sensor decode | ✅ V24 → raw/100 °C | ✅ | |
| Computed temperature | ⚠️ 25–40°C plausibility gate | ✅ Proprietary calibration | |
| Temperature deviation from baseline | ⚠️ Server-side | ✅ | |

### 2.6 Step Count

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| IMU zero-crossing step count | ✅ K10 accelerometer | ✅ | |
| Step counter rollup | ✅ Hourly/daily | ✅ | |
| HealthKit steps import | ✅ | ✅ | |

---

## 3. Coach & Coaching

### 3.1 Goose Coach vs. WHOOP Coach

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| AI model | External LLM (GPT-5.5 / Claude) via user API key | Internal GPT via WHOOP coaching service | Goose requires user API key; WHOOP is first-party |
| Authentication | Codex OAuth → user-managed key | WHOOP account | |
| Domain data | Local bridge data injected per request | Deep integration with WHOOP platform | |
| Conversation persistence | ✅ Last 80 messages in UserDefaults | ✅ Server-side | |
| Tool events | ✅ CoachToolEvent with status/args/results | ✅ | |

### 3.2 Coaching Subsystems WHOOP Has That Goose Lacks

| Feature | Gap |
|---------|-----|
| **Sleep Coach** (full wizard) | Scheduling, alarm types (Exact/Range), education, onboarding, optimal sleep, wake-time config — WHOOP has ~30 tracked interaction events; Goose has basic route views |
| **Strain Coach** | WHOOP has server-side optimal strain mapping per cycle; Goose is local heuristic |
| **Weekly Performance Assessment (WPA)** | Locked/unlocked views, eligibility, tiles on Home — entirely absent |
| **Monthly Performance Assessment (MPA)** | Delivery date, shared links, online MPA state — entirely absent |
| **VOW Messages** | WHOOP has rich push notifications + morning reports; Goose has local rule-based card on Coach tab only |
| **Hormonal/Menstrual Coaching** | Cycle-phase-aware coaching, period prediction, pregnancy insights — entirely absent |
| **Health Monitor integration** | Coaching tiles integrated with Health Monitor data — absent |

### 3.3 Coach API Endpoints (WHOOP's Server Infrastructure)

Goose has none of these server-side coaching endpoints:
- `/coaching-service/v1/coaching/strain/optimal/mapping/cycle/`
- `/coaching-service/v1/performance-assessment/`
- `/coaching-service/v1/sleepneed`
- `/coaching-service/v1/health/report`
- `/coaching-service/v1/health/bff/monitor`
- `/coaching-service/v1/tile-dismissal`

---

## 4. ECG / Heart Screener (Labrador) — MG Only

| Feature | Status |
|---------|--------|
| Labrador sensor commands (124/125/139) | ✅ BLE commands sent on MG connect |
| K16 raw ECG packet parsing | ⚠️ Structure parsed, raw samples extracted |
| K17 filtered ECG (R17) | ⚠️ Flags/channels/samples extracted; PPG interpretation not decoded |
| **ECG waveform display** (live trace) | ❌ |
| **ECG taking UI** (on-demand recording) | ❌ |
| **ECG results / classification** | ❌ (Sinus Rhythm, Inconclusive, Unreadable, Low/High HR) |
| **ECG history / past recordings** | ❌ |
| **ECG symptoms & notes** | ❌ |
| **ECG share / PDF report** | ❌ |
| **ECG terms of use / registration** | ❌ |
| **ECG about / education** | ❌ |
| **ECG device location** (wrist placement) | ❌ |
| **ECG production vs clinical modes** | ❌ |
| **Raw ECG save to device** | ⚠️ Command 125 sent; save behavior unclear |
| **ECG upload to cloud** | ❌ |

### HeartKey (ECG Analysis Engine) — MG Only

All ❌ — `HeartKeyProgress`, `HeartKeyStressScore`, `HeartKeyHRV`, `HeartKeyHR`, `SignalQuality`, arrhythmia check status/result — entire analysis engine absent.

---

## 5. Arrhythmia / AFib Detection (Shepherd) — MG Only

All ❌ — AFib detection, history, onboarding, notifications, settings, terms of use, regulatory info, result statuses, complete Shepherd module (`WhoopShepherd`, `ShepherdModule`, `ShepherdState`).

---

## 6. Blood Pressure — MG Only

All ❌ — Relative blood pressure, BP entitlement, manual BP entry, HealthKit integration, BP insights.

---

## 7. Healthspan / WHOOP Age — Peak/Life

All ❌ — Healthspan screen, WHOOP Age, Pace of Aging, impact cards, VoW messages, hero metric, education content.

---

## 8. Advanced Labs / Biomarkers (Sanguine) — MG Only

All ❌ — Advanced Labs screen, biomarker tracking, details & history, clinical reports, blood test scheduling, test results upload, hormonal context, Sanguine waitlist.

---

## 9. Journal / Daily Behaviors

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Behavior tracking | ❌ SQLite table only (no UI) | ✅ Full journal | Sliders, steppers, question banks, behavior selection — all absent |
| Journal home tile | ❌ | ✅ | |
| Behavior correlation | ❌ | ✅ | WHOOP correlates behaviors with recovery/sleep |

---

## 10. Health Monitor

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Vitals dashboard | ✅ Own implementation | ✅ | |
| Health Monitor with alerts | ❌ | ✅ | WHOOP Peak gated; alerting system |
| Vitals snapshot grid | ✅ | ✅ | |

---

## 11. Trends & Analytics

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Multi-metric trends | ⚠️ 7-day only, 3 metrics | ✅ Full range selector | No multi-range (30d, 90d, 6mo, 1yr) |
| Weekly/Monthly reports (WPA/MPA) | ❌ | ✅ | |
| YearHeatStrip heatmap | ❌ | ✅ | |
| Metric Explorer / correlation | ⚠️ Built (Phase 71) | ❌ (WHOOP doesn't have this) | Goose advantage |

---

## 12. Activity & Workouts

| Aspect | Goose | WHOOP | Gap |
|--------|-------|-------|-----|
| Activity types | ✅ 19 types with GPS/HR | ✅ 80+ types | |
| Passive activity detection | ✅ Heuristic motion/HR | ✅ | |
| Manual workout entry | ✅ (Phase 71) | ✅ | |
| Live Activity / Dynamic Island | ✅ WidgetKit extension | ✅ | |
| GPS track | ✅ CoreLocation + MapKit | ✅ | |
| HR zone breakdown per workout | ✅ | ✅ | |
| Strain per workout | ✅ | ✅ | |

---

## 13. Integrations & Social

| Feature | Goose | WHOOP | Gap |
|---------|-------|-------|-----|
| Strava integration | ❌ | ✅ | OAuth, activity sync, share to Strava |
| TrainingPeaks | ❌ | ✅ | |
| Integrations hub | ❌ | ✅ | |
| Teams | ❌ | ✅ | Team creation, sharing |
| Shared reports | ❌ | ✅ | |

---

## 14. Hormonal / Menstrual / Pregnancy

All ❌ — Menstrual cycle tracking, period prediction, pregnancy insights, hormonal birth control mode, cycle-phase coaching, pregnancy trimester palettes. WHOOP has ~50+ classes/screens dedicated to this.

---

## 15. Device & Hardware

| Feature | Goose | WHOOP | Gap |
|---------|-------|-------|-----|
| BLE connection | ✅ Full GATT protocol | ✅ | |
| Historical sync | ✅ Gen4/5.0 | ✅ | |
| Firmware version read | ✅ GATT 0x2A26 | ✅ | |
| **Firmware OTA updates** | ❌ Blocked | ✅ | FIRMWARE_UPDATE command blocked |
| **Battery fuel gauge** | ⚠️ Basic % + charging | ✅ | No battery health, cycle count, advanced gauge |
| **On-wrist detection** (cap sense) | ❌ Hardware-gated | ✅ | GATT UUID for capacitive sensor unknown |
| **Strap location** (L/R wrist) | ❌ | ✅ | Command 123 (SELECT_WRIST) |
| Clock sync | ✅ Auto-sync >5s drift | ✅ | |
| High-frequency sync mode | ✅ Cmd 96/97 | ✅ | |

---

## 16. Smart Alarm & Haptics

| Feature | Goose | WHOOP | Gap |
|---------|-------|-------|-----|
| Basic alarm (set/get/run) | ✅ AlarmCommandKind + writeAlarmCommand | ✅ | |
| Smart alarm UI | ✅ Built (Phase 73) | ✅ | |
| **Wake-window engine** (lightest-sleep fire) | ❌ RE-gated | ✅ | RE-01/RE-02 required: BTSnoop + Ghidra on SetAlarmInfoCommandPacketRev4 |
| Haptic buzz primitive | ✅ Cmd 0x13 | ✅ | |
| Breathe screen with haptic cues | ✅ (Phase 79) | ✅ | |
| Interval Timer with haptic transitions | ✅ (Phase 71) | ✅ | |
| AdvancedHaptic / HapticHeartbeat | ❌ RE-gated | ✅ | Pattern values unknown |

---

## 17. Data & Export

| Feature | Goose | WHOOP | Gap |
|---------|-------|-------|-----|
| Raw data export (ZIP) | ✅ SHA-256 signed bundles | ✅ | |
| Remote server upload | ✅ Watermark-based dedup | ✅ (cloud) | |
| WHOOP CSV import | ❌ Deferred | — | Goose planned differentiator |
| Apple Health import | ✅ 10+ data types | ✅ | |
| Apple Health write-back | ❌ | ✅ | Goose only reads; doesn't write back |

---

## 18. Notifications & Alerts

| Feature | Goose | WHOOP | Gap |
|---------|-------|-------|-----|
| Sleep summary notification | ✅ | ✅ | |
| Workout detected notification | ✅ | ✅ | |
| Battery low notification | ✅ | ✅ | |
| Health Monitor alerts | ❌ | ✅ | Peak gated |
| AFib notification | ❌ | ✅ | MG gated |
| Morning report notification | ❌ | ✅ | "Your morning report with WHOOP Coach is ready" |
| Coach ongoing guidance push | ❌ | ✅ | |

---

## 19. Protocol Gaps

| Feature | Goose | WHOOP | Gap |
|---------|-------|-------|-----|
| R22 packet parsing | ✅ (v10.0) | ✅ | |
| v18 historical decode | ✅ (v10.0) | ✅ | |
| Puffin protocol (types 37/38/53/54/56) | ⚠️ Raw only | ✅ | Noop has full framing |
| K25/K26 SpO₂ PIP persistent packets | ❌ Unresolved | ✅ | |
| K18 respiratory rate candidate | ⚠️ Detected but unverified | ✅ | Semantics unverified |

---

## 20. App Polish & UX

| Feature | Goose | WHOOP | Gap |
|---------|-------|-------|-----|
| Onboarding flow | ✅ Permissions + profile | ✅ | |
| Dark mode | ✅ | ✅ | |
| Tabbed navigation | ✅ 4 tabs | ✅ 5 tabs | |
| Coach chat interface | ✅ | ✅ | |
| Debug tools (Connection Lab, Packet Monitor) | ✅ | ❌ | Goose advantage |
| Server self-hosting | ✅ FastAPI + TimescaleDB | ❌ (WHOOP cloud only) | **Goose differentiator** |
| Profile with HealthKit autofill | ✅ | ✅ | |

---

## Summary: Feature Completeness by Tier

| Tier | Goose Coverage | Key Gaps |
|------|--------------|----------|
| **WHOOP One** (core) | ~60% | Sleep Coach wizard, full Stress Monitor, LiveStrain tile, WPA/MPA, Journal, Integrations |
| **WHOOP Peak** | ~30% | Healthspan/WHOOP Age, Pace of Aging, Health Monitor alerts, Stress Monitor calibration |
| **WHOOP Life (MG)** | ~5% | ECG UI/results/PDF, HeartKey analysis, AFib detection, Blood Pressure, Advanced Labs |

### Goose's Unique Advantages Over WHOOP

| Feature | Why It Matters |
|---------|---------------|
| **Self-hosted server** | Data stays on user's own infrastructure — no subscription lock-in |
| **Raw data export** | Full access to raw BLE frames, sensor samples, decoded packets |
| **External LLM Coach** | Can use GPT-5.5, Claude, or any compatible model |
| **Open-source** | Auditable, modifiable, community-extendable |
| **Debug tools** | Connection Lab, Packet Monitor — power-user diagnostics WHOOP doesn't offer |
| **Remote server upload** | Automatic watermark-based sync to personal server |

---

## Sources

- Goose codebase: `GooseSwift/`, `Rust/core/src/` — live verification 2026-06-14
- WHOOP RE: `.planning/research/whoop-re/ObjC_RESOLVED.txt`
- MG feature status: `WHOOP-MG-FEATURE-STATUS.md`
- Feature research: `.planning/research/FEATURES.md`
- Project state: `.planning/STATE.md`, `.planning/ROADMAP.md`
