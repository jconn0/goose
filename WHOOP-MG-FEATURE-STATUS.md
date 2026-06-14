# WHOOP MG Feature Status

> Complete status of all WHOOP MG (medical-grade) features in Goose, compared against Noop, upstream PRs, and the broader open-source ecosystem.
>
> The WHOOP MG is the medical-grade variant of WHOOP 5.0, requiring a WHOOP Life subscription (~$359/yr). It adds ~70 distinct features/capabilities on top of the standard WHOOP 5.0.

## WHOOP Membership Tiers (MG context)

| Tier | Key Features | MG Required? |
|---|---|---|
| **WHOOP One** (~$200/yr) | Sleep, strain, recovery, HR zones, hormonal insights | No |
| **WHOOP Peak** (~$239/yr) | + Healthspan, Pace of Aging, Health Monitor with alerts, Stress Monitor | No |
| **WHOOP Life** (~$359/yr) | + ECG Heart Screener, AFib notifications, Blood Pressure, Advanced Labs | **Yes** |

---

## 1. ECG / Heart Screener (Labrador)

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Labrador sensor commands (124/125/139) | ✅ | ❌ | PR #50 | BLE commands sent on MG connect |
| K16 raw ECG packet parsing | ⚠️ Partial | ❌ | PR #50 | Structure parsed, raw samples extracted |
| K17 filtered ECG (R17) | ⚠️ Partial | ❌ | ❌ | Flags/channels/samples extracted, PPG interpretation not decoded |
| ECG waveform display (live trace) | ❌ | ❌ | ❌ | `LabradorWaveformView`, `LiveWaveformInteractor` in official app |
| ECG taking UI (on-demand recording) | ❌ | ❌ | ❌ | `TakeAnECGSectionModel` in official app |
| ECG results / classification | ❌ | ❌ | ❌ | Sinus Rhythm, Inconclusive, Unreadable, Low/High HR |
| ECG history / past recordings | ❌ | ❌ | ❌ | `AllRecordingsScreen`, `/ecg-service/v1/ecg/metric/mobile` |
| ECG symptoms & notes | ❌ | ❌ | ❌ | `SaveECGSymptomsBody`, `LabradorSymptom` |
| ECG share / PDF report | ❌ | ❌ | ❌ | `LabradorReadingReportPDF` |
| ECG terms of use / registration | ❌ | ❌ | ❌ | Onboarding flow |
| ECG about / education | ❌ | ❌ | ❌ | `LabradorAboutScreen` |
| ECG device location (wrist placement) | ❌ | ❌ | ❌ | `LabradorDeviceLocationScreen` |
| ECG production vs clinical modes | ❌ | ❌ | ❌ | Two modes in official app |
| Raw ECG save to device | ⚠️ Partial | ❌ | ❌ | Command 125 sent, save behavior unclear |
| ECG upload to cloud | ❌ | ❌ | ❌ | `UploadRawLabradorMetricsRequest` |

## 2. HeartKey (ECG Analysis Engine)

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| HeartKey progress tracking | ❌ | ❌ | ❌ | `HeartKeyProgress` |
| HeartKey stress score | ❌ | ❌ | ❌ | `HeartKeyStressScoreFailedToParse` |
| HeartKey HRV | ❌ | ❌ | ❌ | `HeartKeyHRVFailedToParse` |
| HeartKey HR | ❌ | ❌ | ❌ | `HeartKeyHRFailedToParse` |
| HeartKey average HR | ❌ | ❌ | ❌ | `HeartKeyAverageHRFailedToParse` |
| HeartKey unreadable reason | ❌ | ❌ | ❌ | `HeartKeyUnreadableReasonFailedToParse` |
| HeartKey leads are on | ❌ | ❌ | ❌ | `HeartKeyLeadsAreOnFailedToParse` |
| HeartKey is running / stopped | ❌ | ❌ | ❌ | `HeartKeyIsRunningFailedToParse` |
| HeartKey arrhythmia check status | ❌ | ❌ | ❌ | `HeartKeyArrhythmiaCheckStatusFailedToParse` |
| HeartKey arrhythmia check result | ❌ | ❌ | ❌ | `HeartKeyArrhythmiaCheckResultFailedToParse` |
| HeartKey signal quality | ❌ | ❌ | ❌ | `SignalQualityFailedToParse` |

## 3. Arrhythmia / AFib Detection (Shepherd)

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| AFib detection | ❌ | ❌ | ❌ | `ArrhythmiaCheckResult`, `POSSIBLE_AFIB_DETECTED` |
| AFib history | ❌ | ❌ | ❌ | `/arrhythmia-service/v2/afibhistory/paginated` |
| AFib onboarding | ❌ | ❌ | ❌ | `afibOnboarding` |
| AFib notifications | ❌ | ❌ | ❌ | `arrhythmia-notification-feature-ios` |
| AFib settings | ❌ | ❌ | ❌ | `ShepherdSettingsToggle`, `detection_on` |
| AFib terms of use | ❌ | ❌ | ❌ | `/arrhythmia-service/v2/termsofuse` |
| AFib welcome screen | ❌ | ❌ | ❌ | `/arrhythmia-service/v2/welcome/bff` |
| AFib education | ❌ | ❌ | ❌ | `about_anf_title` |
| AFib regulatory info | ❌ | ❌ | ❌ | `RegulatoryInformationModel` |
| AFib result statuses | ❌ | ❌ | ❌ | NOT_AFIB, SINUS_RHYTHM, AFIB_HIGH_HEART_RATE, etc. |
| Shepherd module (entire subsystem) | ❌ | ❌ | ❌ | `WhoopShepherd`, `ShepherdModule`, `ShepherdState` |
| ANF state tracking | ❌ | ❌ | ❌ | `anf_state`, `anf_high_water_mark` |

## 4. Blood Pressure Monitoring

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Relative blood pressure | ❌ | ❌ | ❌ | `Relative Blood Pressure`, `BLOOD_PRESSURE_INSIGHTS` |
| Blood pressure entitlement | ❌ | ❌ | ❌ | `ENTITLEMENT_BLOOD_PRESSURE`, `LOCKED_BLOOD_PRESSURE` |
| Manual blood pressure entry | ❌ | ❌ | ❌ | `SageManualBloodPressureEntry` |
| Blood pressure HealthKit integration | ❌ | ❌ | ❌ | `_HKQuantityTypeIdentifierBloodPressureDiastolic/Systolic` |
| Blood pressure insights | ❌ | ❌ | ❌ | `Daily blood pressure insights` |

## 5. Health Monitor

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Health Monitor screen | ❌ | ❌ | ❌ | `ENTITLEMENT_HEALTH_MONITOR`, MG-gated |
| Health Monitor with alerts | ❌ | ❌ | ❌ | `Health Monitor with health alerts` |
| Vitals snapshot grid | ⚠️ Own impl | ❌ | ❌ | Goose has its own vitals dashboard, not WHOOP's MG-gated version |

## 6. Stress Monitor

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Real-time stress monitor | ❌ | ❌ | ❌ | `ENTITLEMENT_STRESS_MONITOR`, WHOOP Life gated |
| Stress monitor with live monitoring | ❌ | ❌ | ❌ | `Stress Monitor with Live Monitoring` |
| Stress monitor intervention | ❌ | ❌ | ❌ | `STRESS_MONITOR_INTERVENTION` |
| Stress monitor education | ❌ | ❌ | ❌ | `STRESS_MONITOR_IN_APP_EDUCATION` |
| Stress calibrating | ❌ | ❌ | ❌ | `stressMonitorCalibrating`, `Calibration in progress` |
| Stress VoW (Voice of WHOOP) | ❌ | ❌ | ❌ | `StressVoW` |

## 7. Healthspan / WHOOP Age

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Healthspan screen | ❌ | ❌ | ❌ | `ENTITLEMENT_HEALTHSPAN`, WHOOP Life gated |
| WHOOP Age | ❌ | ❌ | ❌ | `WHOOP_AGE`, `WHOOP_AGE_YOUNGER/OLDER` |
| Pace of Aging | ❌ | ❌ | ❌ | `PACE_OF_AGING`, `FAST/SLOW_PACE_OF_AGING` |
| Healthspan education | ❌ | ❌ | ❌ | `HEALTHSPAN_EDUCATION` |
| Healthspan impact cards | ❌ | ❌ | ❌ | `HealthspanImpactCardModel` |
| Healthspan VoW | ❌ | ❌ | ❌ | `HealthspanVoW` |
| Healthspan locked content | ❌ | ❌ | ❌ | `LOCKED_HEALTHSPAN`, `LOCKED_PURPLE` |
| Healthspan hero metric | ❌ | ❌ | ❌ | `HealthspanHeroMetricModel` |

## 8. Advanced Labs / Biomarkers (Sanguine)

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Advanced Labs | ❌ | ❌ | ❌ | `AdvancedLabsHomeScreen`, WHOOP Life gated |
| Biomarker tracking | ❌ | ❌ | ❌ | `BiomarkerCard`, `BiomarkersGetRequest` |
| Biomarker details & history | ❌ | ❌ | ❌ | `AdvancedLabsBiomarkerDetailsScreen` |
| Clinical report & action plan | ❌ | ❌ | ❌ | `AdvancedLabsActionPlanScreen` |
| Blood test scheduling | ❌ | ❌ | ❌ | `AdvancedLabsSchedulingFormScreen` |
| Test results upload | ❌ | ❌ | ❌ | `AdvancedLabsUploadTestScreen` |
| Hormonal context in labs | ❌ | ❌ | ❌ | `AdvancedLabsHormonalContextScreen` |
| Sanguine waitlist | ❌ | ❌ | ❌ | `SanguineWaitlistScreen` |
| Edit biomarkers | ❌ | ❌ | ❌ | `BiomarkerOverride` |

## 9. SpO2 (Blood Oxygen Saturation)

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| SpO2 raw ADC (red + IR channels) | ✅ | ✅ | ❌ | V24 decode in Rust `protocol.rs` |
| SpO2 computed percentage | ⚠️ Server-side | ⚠️ Partial | ❌ | Requires WHOOP's proprietary calibration |
| SpO2 HealthKit export | ❌ | ❌ | ❌ | `_HKQuantityTypeIdentifierOxygenSaturation` |

## 10. Skin Temperature

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Skin temperature raw ADC | ✅ | ✅ | ❌ | V24 decode in Rust |
| Skin temperature computed (degC) | ⚠️ Server-side | ⚠️ Partial | ❌ | Requires calibration against WHOOP export |
| Skin temperature deviation | ⚠️ Server-side | ❌ | ❌ | `skin_temp_dev_c` in server daily metrics |

## 11. Respiratory Rate

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Respiratory rate | ⚠️ Partial | ⚠️ Partial | ❌ | K18 candidate detected, extraction fails in Goose; Noop stores raw values |
| Respiratory rate elevated alert | ❌ | ❌ | ❌ | `Respiratory Rate elevated` |

## 12. Puffin Protocol

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Puffin command/response (types 37/38) | RAW_ONLY | ✅ | ❌ | Goose extracts type only; Noop has full framing |
| Puffin events (types 53/54) | RAW_ONLY | ✅ | ❌ | |
| Puffin metadata (type 56) | RAW_ONLY | ✅ | ❌ | |

## 13. On-Wrist Detection / Cap Sense

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| Cap sense (capacitive contact sensor) | ❌ Blocked | ❌ | ❌ | Phase 66 hardware-gated, GATT UUID unknown |
| On-wrist / off-wrist events | ❌ | ❌ | ❌ | `WHPWhoopStrapOnWrist/OffWrist` |
| Skin contact flag in V24 | ✅ | ✅ | ❌ | Decoded in Rust `protocol.rs` |
| Cap sense recalibration | ❌ | ❌ | ❌ | `CalibrateCapsense` |

## 14. Shared Features (WHOOP 5.0 + MG)

| Feature | Goose | Noop | Notes |
|---|---|---|---|
| Live HR stream | ✅ | ✅ | BLE Heart Rate profile (0x180D) |
| HR zones | ✅ | ✅ | |
| Historical sync | ✅ | ✅ | |
| Activity recording | ✅ | ✅ | Workout, sleep, nap, meditation |
| GPS track | ✅ | ✅ | |
| Smart alarm / haptic | ⚠️ Seed | ❌ | Commands confirmed on MG hardware |
| Guided breathing | ⚠️ Seed | ❌ | `BreathingView.swift` seed file |
| Strap location (left/right wrist) | ❌ | ❌ | Command 123 (`SELECT_WRIST`) |
| Firmware OTA | ❌ | ❌ | |
| Battery fuel gauge | ❌ | ❌ | |
| Coach / VoW | ✅ | ✅ | |
| Sleep coach | ❌ | ✅ | |
| Hormonal / pregnancy insights | ❌ | ❌ | |

## 15. Rust Device Type

| Feature | Goose | Noop | Upstream PRs | Notes |
|---|---|---|---|---|
| `DeviceType::MG` variant | ❌ | N/A | ❌ | Aliased to `DeviceType::Goose` — no MG-specific logic in Rust core |

---

## Other Open-Source Projects

**None found.** GitHub searches for `whoop MG ecg`, `whoop labrador ecg`, `whoop arrhythmia heartkey`, `whoop blood pressure`, and related terms returned zero MG-specific projects. Goose appears to be the only open-source project attempting WHOOP MG BLE-level access.

---

## Sources

- Goose codebase (`GooseBLETypes.swift`, `GooseBLEClient.swift`, `protocol.rs`, `HealthDataStore+StaticSnapshots.swift`)
- Noop repo: https://github.com/NoopApp/noop (README, PROTOCOL.md, whoop_protocol.json)
- Upstream PRs: https://github.com/b-nnett/goose/pulls
- GitHub search (multiple queries, June 2026)
- WHOOP MG reverse engineering: `.planning/research/whoop-re/ObjC_RESOLVED.txt`
- WHOOP membership tiers: ObjC_RESOLVED.txt L99140-99408
