# Roadmap: Goose

## Milestones

- ✅ **v1.0 Remote Server + Upstream PRs** — Phases 1-5 (shipped 2026-06-03)
- ✅ **v2.0 Multi-Device & Platform Foundations** — Phases 6-8+8.1 (shipped 2026-06-04)
- ✅ **v3.0 Wearable UX, CI Hardening & RTC Sync** — Phases 9-15 (shipped 2026-06-05)
- ✅ **v4.0 Security, Performance & Coach Expansion** — Phases 16-19 (shipped 2026-06-06)
- 📋 **v5.0 Metrics Accuracy, IMU & Upstream Fixes** — Phases 20-28 (backlog)

## Phases

<details>
<summary>✅ v1.0 Remote Server + Upstream PRs (Phases 1-5) — SHIPPED 2026-06-03</summary>

- [x] Phase 1: Server Infrastructure (3/3 plans) — completed 2026-06-03
- [x] Phase 2: iOS Server Settings (2/2 plans) — completed 2026-06-03
- [x] Phase 3: iOS Upload Client (3/3 plans) — completed 2026-06-03
- [x] Phase 4: Upload Status Feedback (2/2 plans) — completed 2026-06-03
- [x] Phase 5: Upstream PR Integration (4/4 plans) — completed 2026-06-03

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v2.0 Multi-Device & Platform Foundations (Phases 6-8+8.1) — SHIPPED 2026-06-04</summary>

- [x] Phase 6: WHOOP Gen4 iOS Support (3/3 plans) — completed 2026-06-03
- [x] Phase 7: Android Port Foundations + CI (4/4 plans) — completed 2026-06-03
- [x] Phase 8: Additional Wearables E2E (4/4 plans) — completed 2026-06-03
- [x] Phase 8.1: Gap closure WEAR-01/WEAR-03 (2/2 plans) — completed 2026-06-04

Full details: `.planning/milestones/v2.0-ROADMAP.md`

Known deferred: WEAR-02 scan UI (v3.0), CR-02 per-row filter (v3.0), hardware BLE tests (no device)

</details>

<details>
<summary>✅ v3.0 Wearable UX, CI Hardening & RTC Sync (Phases 9-15) — SHIPPED 2026-06-05</summary>

- [x] Phase 9: BLE Stability & Data Integrity (4/4 plans) — completed 2026-06-04
- [x] Phase 10: HR Monitor Scan/Connect UI (3/3 plans) — completed 2026-06-05
- [x] Phase 10.1: BLE Main-Thread Publishing Fix (1/1 plans) — completed 2026-06-05
- [x] Phase 11: HR Monitor Independent Capture (2/2 plans) — completed 2026-06-05
- [x] Phase 12: WHOOP 4.0 RTC Clock Sync (1/1 plans) — completed 2026-06-05
- [x] Phase 13: Recovery V2 Dashboard (1/1 plans) — completed 2026-06-05
- [x] Phase 14: pt-PT Localisation (4/4 plans) — completed 2026-06-05
- [x] Phase 15: Recovery Formula V2 SDNN (1/1 plans) — completed 2026-06-05

Full details: `.planning/milestones/v3.0-ROADMAP.md`

</details>

<details>
<summary>✅ v4.0 Security, Performance & Coach Expansion (Phases 16-19) — SHIPPED 2026-06-06</summary>

- [x] Phase 16: Deep Link Security (1/1 plans) — completed 2026-06-05
- [x] Phase 17: @Observable Migration (4/4 plans) — completed 2026-06-05
- [x] Phase 18: Coach Multi-Provider (6/6 plans) — completed 2026-06-06
- [x] Phase 19: pt-PT Localisation Completion (1/1 plans) — completed 2026-06-06

Full details: `.planning/milestones/v4.0-ROADMAP.md`

Known deferred: COACH-06 device migration test, 4 streaming provider runtime tests, 3 localisation device tests

</details>

## Phase Details

### Phase 9: BLE Stability & Data Integrity

**Goal**: BLE connections are resilient, HR monitor frames are stored with correct per-row device identifiers, FFI panics return JSON errors instead of crashing, and storage growth is bounded
**Depends on**: Phase 8.1 (v2.0 complete)
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04, FIX-05
**Success Criteria** (what must be TRUE):

  1. HR monitor frames written to the database contain a non-NULL `device_id` matching the connected HR monitor device
  2. After a WHOOP disconnection, the app retries with exponential backoff (1 s base, doubles, 60 s cap) and stops after 10 attempts, showing attempt count in the UI
  3. After an HR monitor disconnection, the same backoff parameters apply and the UI reflects reconnect state
  4. User can tap a manual retry button to restart reconnection at any time, and a stop button to abort it
  5. A Rust panic in the FFI layer returns a structured JSON error instead of terminating the app process
  6. Raw evidence payload retention is capped at 24 MB; a large history sync does not balloon the SQLite database**Plans**: 4 plans

**Wave 1**

  - [x] 09-01-PLAN.md — FFI panic safety (catch_unwind + panic=unwind) and storage.compact_raw_evidence bridge method (FIX-04, FIX-05 Rust)

**Wave 2** *(blocked on Wave 1 completion)*

  - [x] 09-02-PLAN.md — Propagate active_device_id into capture_sessions (FIX-01 Rust/CR-02)

**Wave 3** *(blocked on Wave 2 completion)*

  - [x] 09-03-PLAN.md — ReconnectBackoff + WHOOP reconnect UI + storage compaction call sites + active_device_id arg (FIX-02, FIX-05 Swift, FIX-01 Swift)

**Wave 4** *(blocked on Wave 3 completion)*

  - [x] 09-04-PLAN.md — HR monitor reconnect backoff + ConnectionView HR row (FIX-03)

### Phase 10: HR Monitor Scan/Connect UI

**Goal**: Users can discover and connect nearby HR monitors from within the app
**Depends on**: Phase 9
**Requirements**: WEAR-04, WEAR-05
**Success Criteria** (what must be TRUE):

  1. User can initiate an HR monitor scan from the app and see a live list of discovered devices showing device name and RSSI
  2. The scan list updates in real time as devices appear and disappear
  3. User can tap a device in the list to initiate a connection to that HR monitor
  4. The UI shows connection progress and confirms when the HR monitor is connected

**Plans**: 3 plans
**UI hint**: yes

Plans:

- [x] 10-01-PLAN.md — Promote HR monitor BLE state to @Published, add connecting/disconnect/fail handling, test scaffold
- [x] 10-02-PLAN.md — Build HRMonitorView (scan list, connect sheet, connected panel) + on-device verification
- [x] 10-03-PLAN.md — Wire HRMonitorView into the More tab Device section (MoreRoute.hrMonitor)

### Phase 10.1: BLE Main-Thread Publishing Fix (INSERTED)

**Goal:** All `@Published` property mutations in `GooseBLEClient+Commands.swift` and `GooseBLEClient+Parsing.swift` happen on the main thread, eliminating the runtime "Publishing changes from background threads" warnings produced by CoreBluetooth callbacks.
**Requirements**: BLE-MT-01, BLE-MT-02, BLE-MT-03
**Depends on:** Phase 10
**Plans:** 1/1 plans complete
**Success Criteria** (what must be TRUE):

  1. No "Publishing changes from background threads is not allowed" runtime warnings appear when the app is connected to a WHOOP or HR monitor
  2. `updateConnectionState`, `updateActiveDeviceName`, and all other `@Published`-mutating methods in `GooseBLEClient+Commands.swift` dispatch mutations to the main thread
  3. `GooseBLEClient+Parsing.swift` line 430 equivalent mutation is also dispatched to main thread
  4. No existing BLE behaviour or reconnect logic is broken

Plans:

- [x] 10.1-01-PLAN.md — Main-thread guards on all @Published mutators in GooseBLEClient+Commands.swift and +Parsing.swift; resolve duplicate updateReconnectState warning; cargo test -p goose-core gate

### Phase 11: HR Monitor Independent Capture

**Goal**: Users can run an HR monitor capture session without requiring an active WHOOP session
**Depends on**: Phase 9, Phase 10
**Requirements**: WEAR-06
**Success Criteria** (what must be TRUE):

  1. HR monitor frames are captured and stored when no WHOOP session is active
  2. HR monitor capture starts and stops independently of the WHOOP session lifecycle
  3. Captured HR monitor data (BPM and RR intervals) appears in the upload payload regardless of WHOOP session state

**Plans**: 2 plans

**Wave 1**

  - [x] 11-01-PLAN.md — Add .hrMonitor capture mode + startHRMonitorCapture/stopHRMonitorCapture without WHOOP gate (D-01, D-03)

**Wave 2** *(blocked on Wave 1 completion)*

  - [x] 11-02-PLAN.md — Auto-start/stop on hrConnectionState via onHRConnectionStateChange callback + D-04 upload verification + cargo test gate (D-02, D-04)

### Phase 12: WHOOP 4.0 RTC Clock Sync

**Goal**: WHOOP 4.0 clock drift is automatically corrected after each BLE connection
**Depends on**: Phase 9
**Requirements**: RTC-01
**Success Criteria** (what must be TRUE):

  1. After connecting a WHOOP 4.0, the app automatically reads the device clock and compares it to iPhone time
  2. When drift exceeds the configured threshold, the app writes the current iPhone time to the WHOOP 4.0 via BLE
  3. The sync is silent (no user prompt required) and does not interrupt normal BLE data capture

**Plans**: TBD

### Phase 13: Recovery V2 Dashboard

**Goal**: Users can view a live Recovery V2 dashboard with bridge-backed biometric data
**Depends on**: Phase 9
**Requirements**: DASH-01
**Success Criteria** (what must be TRUE):

  1. User can see a hero recovery score on the Recovery V2 dashboard derived from live bridge data
  2. User can see current HRV and resting heart rate values, not placeholder zeros
  3. User can see a 7-day trend of recovery scores on the dashboard

**Plans**: TBD
**UI hint**: yes

### Phase 14: pt-PT Localisation

**Goal**: All user-visible text in the app is presented in European Portuguese
**Depends on**: Phase 10, Phase 11, Phase 13 (all UI stable)
**Requirements**: L10N-01, L10N-02
**Success Criteria** (what must be TRUE):

  1. All static UI text strings are stored in a `Localizable.xcstrings` String Catalog and rendered in pt-PT when the device language is Portuguese (Portugal)
  2. Dynamic status strings (BLE connection state, sync state, upload state) displayed in the UI appear in pt-PT
  3. No hardcoded English text remains visible in the main user-facing UI flows

**Plans**: 4 plans
**UI hint**: yes

**Wave 1**

- [x] 14-01-PLAN.md — Infrastructure: create Localizable.xcstrings, register pt-PT in project.pbxproj, fix GooseAppTab.title + MoreRoute.title/subtitle to String(localized:), translate tab + More-route titles/subtitles (L10N-01)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 14-02-PLAN.md — Static catalog translations: Home dashboard, Health families (Recovery V2, Sleep V2, Cardio, Strain, Stress), Coach view (~150 strings) (L10N-01)

**Wave 3** *(blocked on Wave 2 completion — shared Localizable.xcstrings)*

- [x] 14-03-PLAN.md — Static catalog translations: More tab, Connection/Device/HR Monitor, Capture/Debug/Raw Export, Onboarding (~150 strings) (L10N-01)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 14-04-PLAN.md — LocalizedStatusStrings.swift (14 @Published display extensions, D-04) + display-site rewiring + MoreStatusKind.title + final sweep + xcodebuild verification (L10N-02)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Server Infrastructure | v1.0 | 3/3 | Complete | 2026-06-03 |
| 2. iOS Server Settings | v1.0 | 2/2 | Complete | 2026-06-03 |
| 3. iOS Upload Client | v1.0 | 3/3 | Complete | 2026-06-03 |
| 4. Upload Status Feedback | v1.0 | 2/2 | Complete | 2026-06-03 |
| 5. Upstream PR Integration | v1.0 | 4/4 | Complete | 2026-06-03 |
| 6. WHOOP Gen4 iOS Support | v2.0 | 3/3 | Complete | 2026-06-03 |
| 7. Android Port Foundations + CI | v2.0 | 4/4 | Complete | 2026-06-03 |
| 8. Additional Wearables E2E | v2.0 | 4/4 | Complete | 2026-06-03 |
| 8.1. Gap closure WEAR-01/WEAR-03 | v2.0 | 2/2 | Complete | 2026-06-04 |
| 9. BLE Stability & Data Integrity | v3.0 | 4/4 | Complete    | 2026-06-04 |
| 10. HR Monitor Scan/Connect UI | v3.0 | 3/3 | Complete    | 2026-06-04 |
| 10.1. BLE Main-Thread Publishing Fix | v3.0 | 1/1 | Complete    | 2026-06-04 |
| 11. HR Monitor Independent Capture | v3.0 | 2/2 | Complete    | 2026-06-05 |
| 12. WHOOP 4.0 RTC Clock Sync | v3.0 | 1/1 | Complete    | 2026-06-05 |
| 13. Recovery V2 Dashboard | v3.0 | 1/1 | Complete    | 2026-06-05 |
| 14. pt-PT Localisation | v3.0 | 4/4 | Complete | 2026-06-05 |
| 15. Recovery Formula V2 SDNN | v3.0 | 1/1 | Complete | 2026-06-05 |
| 16. Deep Link Security | v4.0 | 1/1 | Complete | 2026-06-05 |
| 17. @Observable Migration | v4.0 | 4/4 | Complete | 2026-06-05 |
| 18. Coach Multi-Provider | v4.0 | 6/6 | Complete | 2026-06-06 |
| 19. pt-PT Localisation Completion | v4.0 | 1/1 | Complete | 2026-06-06 |

## Backlog

### Phase 999.5: GooseAppModel @Observable Migration (promoted to Phase 17 — v4.0)

Promoted to Phase 17: @Observable Migration.

---

### Phase 999.4: Recovery V2 Completion (promoted to Phase 13 — v3.0)

Promoted to Phase 13: Recovery V2 Dashboard.

---

### Phase 999.3: Apply upstream PR #15 (promoted to Phase 16 — v4.0)

Promoted to Phase 16: Deep Link Security.

---

### Phase 999.2: Multi-Language Support (promoted to Phase 14 — v3.0)

Promoted to Phase 14: pt-PT Localisation.

---

### Phase 999.1: Coach Multi-Provider & Custom Endpoint (promoted to Phase 18 — v4.0)

Promoted to Phase 18: Coach Multi-Provider.

### Phase 15: Recovery Formula V2 (SDNN Accuracy)

**Goal:** Corrigir a fórmula `goose_recovery_v0` — renomear `hrvRmssdMs` para `hkHRVSDNNMs` para reflectir a métrica real da Apple Watch, remover a conversão `/1.2` (aproximação populacional SDNN→RMSSD), e normalizar os baselines directamente em SDNN para eliminar desvios individuais no score de recuperação. Inclui também a implementação de `rmssd_segment_aware` (cálculo fisiologicamente correcto de RMSSD a partir de RR intervals segmentados).
**Requirements**: TBD
**Depends on:** Phase 13
**Reference:** [OKKHALIL3 review comment — PR #5](https://github.com/b-nnett/goose/pull/5#discussion_r3359064144); [po-sc PR #19 commits 303f329 / rmssd_segment_aware](https://github.com/b-nnett/goose/pull/19#issuecomment-4632805440)
**Plans:** 1/1 plans complete

**Scope:**

1. `rmssd_segment_aware(segments: &[Vec<f64>], min_pairs: usize) -> Option<f64>` — implementar no `Rust/core/src/metrics.rs`. Calcula RMSSD apenas dentro de cada segmento (janela de captura), nunca entre janelas distintas. Inclui filtro de artefactos (banda 300–2000 ms, regra de Malik 20%). A ausência desta função no fork causa inflação de RMSSD quando existem múltiplas janelas de captura.
2. Unit tests cobrindo: banda fisiológica (300/2000 ms), regra de Malik (diferença relativa > 20% rejeita o par), invariante cross-window (beats de janelas diferentes nunca são diferenciados).
3. Renomear `hrvRmssdMs` → `hkHRVSDNNMs`, remover conversão `/1.2`, normalizar baselines em SDNN.

Plans:

- [x] TBD (run /gsd-plan-phase 15 to break down) (completed 2026-06-05)

---

### Phase 999.6: body_hex Storage Optimization (promoted to Phase 27 — v5.0)

Promoted to Phase 27: body_hex Storage Optimization.

---

## 📋 v5.0 Metrics Accuracy, IMU & Upstream Fixes (Backlog)

**Milestone Goal:** Portar para o Rust core do Goose os algoritmos validados do `my-whoop`, confirmados contra o IPA real da WHOOP 5.37.0 via Ghidra e contra publicações peer-reviewed. O resultado é que cada métrica exposta pela app (HRV, Recovery, Strain, Calorias, Sleep) produz valores alinhados com os da WHOOP para os mesmos dados brutos.

**Fonte primária:** `~/Documents/my-whoop/server/ingest/app/analysis/` — pipeline Python com remodelação de precisão completa (2026-05-26). Coeficientes de calorias confirmados byte-a-byte contra `Whoop` binary AARCH64 via Ghidra MCP (2026-06-01, `FINDINGS_5.md` §GHIDRA-HB-01 e §GHIDRA-02).

---

### Phase 20: HRV Pipeline Accuracy

**Goal:** O RMSSD noturno do Goose passa a usar a janela SWS correta (última fase de sono profundo, não a noite toda), filtragem de batimentos ectópicos, e pooling segmentado que não cria diffs espúrios entre gaps de dados BLE.
**Depends on:** Phase 19
**Requirements:** ALG-HRV-01, ALG-HRV-02, ALG-HRV-03, ALG-HRV-04
**Source:** `my-whoop/server/ingest/app/analysis/hrv.py` — Task Force 1996, Lipponen & Tarvainen 2019 (Kubios), te Lindert 2013, Walch 2019

**Success Criteria** (what must be TRUE):

  1. `rmssd_segment_aware` (já existe no Phase 15) é estendido para recusar diffs que cruzem gaps de timestamp > 3 s no stream RR bruto do WHOOP — RMSSD não é inflacionado por dropouts BLE
  2. Pipeline de limpeza de RR: filtro de plausibilidade fisiológica 300–2000 ms → remoção de batimentos ectópicos via regra de Malik (rejeita par quando |ΔRR|/RR > 20%) — equivalente ao Kubios sem depender de neurokit2
  3. Seleção de janela noturna em 3 níveis implementada no bridge: (1) último episódio "deep" ≥ 5 min; (2) média ponderada por recência de todos os episódios "deep"; (3) fallback noite toda — `HrvInput` aceita `stage_segments` opcionais
  4. pNN50 exposto no `HrvOutput` e visível no dashboard Recovery V2 (já no struct, garantir que chega à UI)
  5. `cargo test -p goose-core` verde; testes unitários cobrem: filtro 300–2000 ms, regra de Malik, invariante cross-window, tiered window selection

**Plans:** TBD

**Wave 1** — Rust: filtro fisiológico + regra de Malik no `metrics.rs`
**Wave 2** *(blocked on Wave 1)* — Rust: tiered SWS window selection no bridge (`hrv.compute_nightly`)
**Wave 3** *(blocked on Wave 2)* — Swift + UI: pNN50 surfacing no Recovery V2 dashboard

---

### Phase 21: Recovery Score — Z-score + Logistic Model

**Goal:** O score de Recovery (0–100) passa a usar o modelo composto ponderado com baseline pessoal EWMA, cold-start gate, e squash logístico — alinhado com a metodologia publicada pela WHOOP.
**Depends on:** Phase 20
**Requirements:** ALG-REC-01, ALG-REC-02, ALG-REC-03
**Source:** `my-whoop/server/ingest/app/analysis/recovery.py` + `baselines.py` — Logistic squash Z=0 → 58% (média WHOOP publicada); EWMA com Winsorização; Lipponen & Tarvainen 2019

**Success Criteria** (what must be TRUE):

  1. `recovery_score_v1` no `metrics.rs` implementa `score = 100 / (1 + exp(-1.6 × (Z + 0.20)))` com `Z = 0.60·z_hrv + 0.20·z_rhr + 0.05·z_resp + 0.15·z_sleep` — Z=0 produz ≈ 58%
  2. Cada z-score normaliza pelo baseline pessoal EWMA (não média populacional): `z = (valor − μ_ewma) / (1.253 × σ_ewma)`
  3. Cold-start gate: quando o utilizador tem < 4 noites de baseline HRV válidas, o bridge retorna `recovery: null` em vez de um score fabricado — UI mostra estado "A calibrar"
  4. Trust levels do baseline expostos: `calibrating` (< 4 noites) → `provisional` (4–13) → `trusted` (≥ 14)
  5. Bandas de cor correctas: Vermelho < 34 / Amarelo 34–66 / Verde ≥ 67
  6. `cargo test` verde; testes cobrem: cold-start, Z=0→58%, bandas, normalização EWMA

**Plans:** TBD

**Wave 1** — Rust: EWMA baseline state + update + fold_history no `metrics.rs`
**Wave 2** *(blocked on Wave 1)* — Rust: `recovery_score_v1` com modelo Z + logístico + cold-start gate
**Wave 3** *(blocked on Wave 2)* — Swift: bridge call + UI "A calibrar" state + bandas de cor

---

### Phase 22: Calorias — Mifflin-St Jeor + Coeficientes IPA

**Goal:** Adicionar o modelo Mifflin-St Jeor para RMR diário total (ausente no Goose); confirmar que os coeficientes Keytel e Harris-Benedict em uso são os validados contra o IPA da WHOOP 5.37.0 via Ghidra.
**Depends on:** Phase 19
**Requirements:** ALG-CAL-01, ALG-CAL-02
**Source:** `my-whoop/server/ingest/app/analysis/calories.py`; coeficientes Keytel confirmados em `0x1058a5ac0` e Harris-Benedict em `0x1058a5a80` (WHOOP `Whoop` binary AARCH64, Ghidra MCP, 2026-06-01, `FINDINGS_5.md §GHIDRA-HB-01 + §GHIDRA-02`)

**Success Criteria** (what must be TRUE):

  1. `rmr_mifflin_st_jeor(weight_kg, height_cm, age, sex)` implementado no `energy_rollup.rs`:
     Homens: `10·kg + 6.25·cm − 5·age + 5` kcal/dia; Mulheres: `10·kg + 6.25·cm − 5·age − 161` kcal/dia; Outro: intercept médio −78

  2. Coeficientes Keytel em uso no `energy_rollup.rs` validados contra os confirmados por Ghidra: homens `(−55.0969, 0.6309, 0.1988, 0.2017)`, mulheres `(−20.4022, 0.4472, −0.1263, 0.0740)`, divisor `251.04`
  3. Coeficientes Harris-Benedict em uso validados contra Ghidra: homens `(88.362, 13.397, 479.9, −5.677)`, mulheres `(447.593, 9.247, 309.8, −4.330)`
  4. Threshold activo/repouso: HR ≥ resting_hr + 30% × (hrmax − resting_hr) usa Keytel; abaixo usa Harris-Benedict
  5. RMR diário (Mifflin-St Jeor) exposto como campo separado no `EnergyDailyRollupReport` e visível no dashboard
  6. `cargo test` verde; testes cobrem: coeficientes exatos, threshold ativo/repouso, sex=nonbinary

**Plans:** TBD

**Wave 1** — Rust: `rmr_mifflin_st_jeor` + verificação/correcção dos coeficientes Keytel e Harris-Benedict em `energy_rollup.rs`
**Wave 2** *(blocked on Wave 1)* — Swift + UI: campo RMR diário no dashboard Energy/Calorias

---

### Phase 23: Strain — Tanaka HRmax + Banister TRIMP + Calibração

**Goal:** O cálculo de Strain passa a usar HRmax personalizado (Tanaka ou percentil 99.5 do histórico), expõe o modelo Banister como alternativa ao Edwards, e inclui helper de calibração do denominador contra valores reais da WHOOP.
**Depends on:** Phase 19
**Requirements:** ALG-STR-01, ALG-STR-02, ALG-STR-03
**Source:** `my-whoop/server/ingest/app/analysis/strain.py` — Karvonen 1957, Edwards 1993, Banister 1991, Tanaka et al. 2001

**Success Criteria** (what must be TRUE):

  1. `tanaka_hrmax(age) = 208 − 0.7 × age` substitui `220 − age` como default em todo o pipeline de strain — diferença ≥ 2 bpm para utilizadores > 40 anos
  2. `estimate_hrmax_from_history(hr_history: &[f64]) → Option<f64>` implementado: percentil 99.5 do histórico quando ≥ 600 amostras (≥ 10 min); max(observado, Tanaka) como escolha final
  3. `banister_trimp(hr_series, resting_hr, hrmax, sex)` implementado como alternativa ao Edwards: `Σ duração × x × 0.64 × e^(b×x)` com `b=1.92` (homens) / `b=1.67` (mulheres), `x=%HRR/100`
  4. `fit_strain_denominator(pairs: &[(f64, f64)]) → f64` implementado: dado ≥ 2 pares (TRIMP, strain_WHOOP), ajusta `D` em `21 × ln(TRIMP+1)/ln(D)` por least-squares — permite calibração pessoal
  5. Bridge expõe `method: "edwards" | "banister"` e `use_personal_hrmax: bool` como parâmetros opcionais
  6. `cargo test` verde; testes cobrem: Tanaka vs 220-age, Banister > Edwards para alta intensidade, calibração com 2 pares

**Plans:** TBD

**Wave 1** — Rust: `tanaka_hrmax` + `estimate_hrmax_from_history` + `banister_trimp` + `fit_strain_denominator` em `metrics.rs`
**Wave 2** *(blocked on Wave 1)* — Rust: actualizar bridge strain para aceitar os novos parâmetros
**Wave 3** *(blocked on Wave 2)* — Swift: expor método de TRIMP nas Settings; mostrar HRmax personalizado no dashboard

---

### Phase 24: Sleep Metrics Detalhados (sem staging)

**Goal:** Expor métricas AASM derivadas dos dados de sleep já existentes — HR dip noturno %, WASO, SOL, latência REM, perturbações — sem depender de staging 4-classes (que requer IMU).
**Depends on:** Phase 20
**Requirements:** ALG-SLP-01, ALG-SLP-02
**Source:** `my-whoop/server/ingest/app/analysis/sleep.py` — Berry et al. 2017 (AASM Manual v2.4); `my-whoop/server/ingest/app/analysis/recovery.py` (`resting_hr`)

**Success Criteria** (what must be TRUE):

  1. `heart_rate_dip_pct` computado a partir do stream HR da sessão de sono: `(hr_baseline_pre_sleep − hr_nadir_5min_rolling) / hr_baseline_pre_sleep × 100` — campo já existe em `SleepInput`, passa a ser preenchido em vez de `null`
  2. `waso_minutes` (Wake After Sleep Onset) computado a partir de epochs de wake após o onset — estimado via threshold de actividade HR (≥ 1.05 × resting_hr) quando staging não disponível
  3. `sol_minutes` (Sleep Onset Latency) preenchido correctamente quando disponível nos dados de staging existentes
  4. `rem_latency_minutes` extraído quando stage_segments inclui episódios REM
  5. `disturbance_count` (episódios de wake pós-onset) exposto no `SleepScoreOutput` e visível no dashboard Sleep V2
  6. `cargo test` verde; testes cobrem: HR dip com nadir correcto, WASO = 0 quando sem wake pós-onset

**Plans:** TBD

**Wave 1** — Rust: HR dip computation + WASO estimation em `metrics.rs`
**Wave 2** *(blocked on Wave 1)* — Swift + UI: campos HR dip, WASO, disturbances no Sleep V2 dashboard

---

### Phase 25: IMU Data Pipeline

**Goal:** Os dados do acelerómetro e giroscópio do WHOOP chegam completos ao bridge Rust e são persistidos no SQLite como rows `gravity` — desbloqueando o sleep staging baseado em movimento (Phase 26).
**Depends on:** Phase 19
**Requirements:** IMU-01, IMU-02, IMU-03, IMU-04
**Source:** `FINDINGS.md §9b` (my-whoop) — layout K10 confirmado por controlled-motion analysis: accelX/Y/Z offsets 82/282/482, gyroX/Y/Z offsets 685/885/1085, 100 amostras por eixo por pacote, signed int16 LE, escala ~3900 LSB/g

**Contexto técnico:** O parsing K10 já existe em `protocol.rs` mas o `I16SeriesSummary` guarda apenas um preview de 8 amostras — os 100 valores por eixo são descartados. No `bridge.rs` o Vec `gravity` é inicializado vazio e nunca preenchido (`// no direct extraction` na linha 3154). O `TOGGLE_IMU_MODE` (command 106) existe como comando de debug mas não é enviado automaticamente nas sessões de captura.

**Success Criteria** (what must be TRUE):

  1. `I16SeriesSummary` em `protocol.rs` preserva o array completo `samples: Vec<i16>` (100 valores por eixo) em vez de descartar após o preview — sem quebrar a serialização existente
  2. No bridge `extract_streams`, frames K10 com `RawMotionK10` populam o Vec `gravity` com rows `{"ts": unix_s, "x": f64_g, "y": f64_g, "z": f64_g}` convertidos com fator ~3900 LSB/g; fator exposto como parâmetro configurável para calibração futura
  3. Tabela `gravity (device_id TEXT, ts REAL, x REAL, y REAL, z REAL)` criada no schema SQLite com índice em `(device_id, ts)`; bridge method `store.insert_gravity_rows` implementado
  4. `GooseBLEClient.swift`: `startCapture()` envia `TOGGLE_IMU_MODE_ON` (command 106) após confirmar bond; `stopCapture()` envia `TOGGLE_IMU_MODE_OFF` — simétrico com o padrão `START_RAW_DATA`/`STOP_RAW_DATA` existente
  5. Upload payload em `GooseUploadService.swift` inclui `gravity` não-vazio quando há dados IMU na sessão
  6. `cargo test` verde; testes cobrem: preservação dos 100 samples, conversão LSB→g, insert gravity rows, query por janela de tempo

**Plans:** TBD

**Wave 1** — Rust: estender `I16SeriesSummary` com `samples: Vec<i16>` + ajustar `parse_k10_raw_motion_summary` para preencher o campo (`protocol.rs`)
**Wave 2** *(blocked on Wave 1)* — Rust: populating `gravity` Vec no bridge extractor K10 com conversão LSB→g + schema SQL + `insert_gravity_rows` (`bridge.rs`, `store.rs`)
**Wave 3** *(blocked on Wave 2)* — Swift: `TOGGLE_IMU_MODE_ON/OFF` automático em `startCapture`/`stopCapture`; upload payload gravity; verificação end-to-end com dispositivo real

---

### Phase 26: 4-Class Sleep Staging (Cole-Kripke + IMU)

**Goal:** Pipeline de staging automático wake/light/deep/REM a partir do acelerómetro IMU + FC + RR — eliminando a dependência exclusiva dos dados de staging da WHOOP.
**Depends on:** Phase 24, Phase 25
**Requirements:** ALG-SLP-03, ALG-SLP-04
**Source:** `my-whoop/server/ingest/app/analysis/sleep.py` — Cole & al. 1992 (Cole-Kripke actigrafia); te Lindert & Van Someren 2013 (proxy actigrafia 30 s); Walch et al. 2019 (DoG HR-variability feature)

**Success Criteria** (what must be TRUE):

  1. `cole_kripke_activity_series(gravity_rows)` implementado em `sleep_staging.rs`: magnitude inter-amostra `√(Δx²+Δy²+Δz²)` por par consecutivo; dropout (coordenada ausente) → intensidade infinita
  2. Spine sleep/wake: janela rolante de 15 min, 70% amostras em repouso (< 0.01 g de variação) → candidato de sono; gaps > 20 min quebram o run; runs < 15 min absorvidos pelos vizinhos
  3. Features cardiorrespiratórias por época de 30s: HR médio, RMSSD, Walch DoG (variabilidade HR), clock proxy — calculadas sobre janela rolante de 5 min centrada na época
  4. Classificador produz hipnograma: wake / light / deep / REM; suavização (flips isolados de 30 s eliminados); reimposição fisiológica (sem REM nos primeiros 15 min; deep concentrado no 1.º terço)
  5. ≥ 70% concordância de época com staging WHOOP em ≥ 5 noites de validação cruzada
  6. Métricas AASM completas do hipnograma: TST, eficiência, SOL, WASO, latência REM, stage_minutes por fase
  7. `cargo test` verde; testes cobrem: Cole-Kripke, threshold stillness, merge de runs curtos, reimposição fisiológica

**Plans:** TBD

**Wave 1** — Rust: `cole_kripke_activity_series` + `activity_magnitude` em `sleep_staging.rs`
**Wave 2** *(blocked on Wave 1)* — Rust: features cardiorrespiratórias por época 30s + classificador threshold-based
**Wave 3** *(blocked on Wave 2)* — Rust: suavização + reimposição fisiológica + métricas AASM completas
**Wave 4** *(blocked on Wave 3)* — Validação cruzada com dados reais + Swift + UI: hypnogram visual no Sleep V2

---

### Phase 27: body_hex Storage Optimization

**Goal:** Eliminar o campo `body_hex` duplicado no cached parsed-payload JSON para frames de raw-motion, reduzindo o tamanho da base de dados e acelerando o batch de métricas.
**Depends on:** Phase 19
**Requirements:** PERF-05
**Source:** Commit `3eef377` do po-sc (upstream PR #19, 2026-06-05) — reduziu ~43 MB num DB de 147 MB no raw-motion stream e tornou o metric batch 27% mais rápido

**Success Criteria** (what must be TRUE):

  1. Verificação em `Rust/core/src/protocol.rs:515` confirma se o fork duplica `payload_hex` no campo `body_hex` do cached parsed-payload JSON para frames K10/K21 grandes
  2. Se confirmado: `body_hex` excluído do JSON para frames de raw-motion (K10/K21) — a flag `include_body_hex: false` ou condicionamento por tamanho de frame implementado em `parse_frame_batch`
  3. Redução mensurável no tamanho da DB: ≥ 20 MB poupados por 24 h de captura com IMU activo (comparação antes/depois documentada)
  4. Tempo do metric batch inalterado ou melhorado
  5. `cargo test` verde — nenhum teste de round-trip `body_hex` quebrado

**Plans:** TBD

**Wave 1** — Rust: auditar `protocol.rs:515` + `parse_frame_batch`; condicionar `body_hex` para frames K10/K21; medir impacto

---

### Phase 28: Gen4 Historical Sync — Upstream Fixes

**Goal:** Aplicar os fixes de correcção identificados durante a review do upstream PR #26 à implementação de Gen4 historical sync do fork.
**Depends on:** Phase 19
**Requirements:** SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05
**Source:** PR #26 review — b-nnett/goose (jakobrmarrone, 2026-06-06)

**Success Criteria** (what must be TRUE):

  1. **Retain inversion corrigido** (`AppShellView.swift`): closure `onHistoricalSyncCompleted` usa `[weak healthStore]` + `.onDisappear { model.onHistoricalSyncCompleted = nil }` — sem referência forte de `GooseAppModel` (vida longa) para `HealthDataStore` (vida da view)
  2. **Overflow consistente** (`GooseBLEClient+HistoricalHandlers.swift`): todos os sites de incremento de `gen4HistoricalPageSeq` usam `&+= 1` (wrapping) — sem mistura de wrapping e trapping
  3. **Padding Gen4 clarificado** (`GooseBLETypes.swift`): `buildGen4CommandFrame` tem padding de 4 bytes ou comentário documentado explicando a ausência (confirmado contra capturas PacketLogger)
  4. **Confinamento documentado** (`GooseBLEClient.swift`): `activeDeviceGeneration` tem `/// Only mutated/read on coreBluetoothQueue.`
  5. **UUID normalizado** (`WhoopGeneration.detect`): `hasPrefix("61080002")` normaliza para lowercase antes da comparação
  6. `cargo test` + Xcode build verdes após os 5 fixes

**Plans:** TBD

**Wave 1** — Swift: fixes 1–5 em sequência (todos no mesmo wave — cada fix é cirúrgico e independente)

---

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 9. BLE Stability & Data Integrity | v3.0 | 4/4 | Complete | 2026-06-04 |
| 10. HR Monitor Scan/Connect UI | v3.0 | 3/3 | Complete | 2026-06-05 |
| 10.1. BLE Main-Thread Publishing Fix | v3.0 | 1/1 | Complete | 2026-06-05 |
| 11. HR Monitor Independent Capture | v3.0 | 2/2 | Complete | 2026-06-05 |
| 12. WHOOP 4.0 RTC Clock Sync | v3.0 | 1/1 | Complete | 2026-06-05 |
| 13. Recovery V2 Dashboard | v3.0 | 1/1 | Complete | 2026-06-05 |
| 14. pt-PT Localisation | v3.0 | 4/4 | Complete | 2026-06-05 |
| 15. Recovery Formula V2 SDNN | v3.0 | 1/1 | Complete | 2026-06-05 |
| 16. Deep Link Security | v4.0 | 1/0 | Complete    | 2026-06-05 |
| 17. @Observable Migration | v4.0 | 4/4 | Complete | 2026-06-05 |
| 18. Coach Multi-Provider | v4.0 | 6/6 | Complete | 2026-06-06 |
| 19. pt-PT Localisation Completion | v4.0 | 1/1 | Complete   | 2026-06-06 |
| 20. HRV Pipeline Accuracy | v5.0 | 0/0 | Backlog | |
| 21. Recovery Score Z-score + Logistic | v5.0 | 0/0 | Backlog | |
| 22. Calorias Mifflin-St Jeor + IPA | v5.0 | 0/0 | Backlog | |
| 23. Strain Tanaka + Banister + Calibração | v5.0 | 0/0 | Backlog | |
| 24. Sleep Metrics Detalhados (sem staging) | v5.0 | 0/0 | Backlog | |
| 25. IMU Data Pipeline | v5.0 | 0/0 | Backlog | |
| 26. 4-Class Sleep Staging (Cole-Kripke + IMU) | v5.0 | 0/0 | Backlog | |
| 27. body_hex Storage Optimization | v5.0 | 0/0 | Backlog | |
| 28. Gen4 Historical Sync — Upstream Fixes | v5.0 | 0/0 | Backlog | |
