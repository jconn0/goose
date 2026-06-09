# Requirements: Goose v6.0 — UI Wiring, Algorithm Alignment & Parity Validation

**Milestone:** v6.0
**Goal:** Ligar os algoritmos Rust do v5.0 à interface SwiftUI, corrigir as divergências de algoritmos identificadas no cross-project review, e fechar as gates de validação humana (HRV e sleep staging).

---

## Dashboard UI

- [x] **RDY-UI-01**: O utilizador vê o nível de disponibilidade diário (rundown/strained/balanced/primed) no Recovery dashboard, derivado do ACWR (7d/28d) e do índice de monotonia de Foster implementado no Phase 30
- [x] **SLP-UI-01**: O utilizador vê o hipnograma 4-class (wake/light/deep/REM) e as métricas AASM completas (REM latency, TST, eficiência, SOL, WASO por etapa) no Sleep V2 dashboard
- [x] **BIO-UI-01**: O utilizador vê SpO2 estimado, temperatura da pele e resp rate no painel de saúde, com badge "não calibrado" obrigatório e skin_contact=false mostrado como "--"

## Activity UI

- [x] **EX-UI-01**: O utilizador vê lista de sessões de exercício detectadas automaticamente (Phase 28) com hora de início, duração, calorias kcal, strain score e gráfico de zonas Edwards
- [x] **STEP-UI-01**: O utilizador vê a contagem de passos IMU-derivada (zero-crossing na magnitude de gravidade K10) com label "via acelerómetro" distinta do contador oficial WHOOP

## Sync UI

- [x] **SYNC-UI-01**: O utilizador vê quantas rows estão pendentes de sincronização no More tab e pode forçar um backfill manual; o GooseUploadService marca rows como synced=1 após confirmação do servidor

## Algorithm Alignment

- [x] **ALG-ALIGN-01**: As 3 divergências identificadas no Phase 35 cross-project review vs my-whoop são corrigidas: (1) `goose_recovery_v1` usa Z-score+logística com pesos HRV=0.60, RHR=0.20, resp=0.05, sleep_perf=0.15; Z=0 → ~58%; (2) EWMA baseline alpha corrigido para 0.0483 (14-night half-life) com Winsorização ±3σ; (3) Cole-Kripke usa épocas de 30s (`COLE_KRIPKE_EPOCH_MINUTES = 0.5`)

## Validation (human gates)

- [x] **VAL-01**: Gate ALG-HRV-04 fechada — Rust `goose_hrv_v0` RMSSD validado contra `my-whoop` Python reference em ≥5 sessões overnight reais capturadas pelo Goose iOS; delta ≤1 ms; resultados documentados em golden fixtures
- [x] **VAL-02**: Gate ALG-SLP-04 fechada — classificador 4-class validado com ≥70% de concordância de época em ≥5 sessões overnight vs etapas oficiais WHOOP; resultados tabulados em phase notes

---

## Future Requirements

- Apple Health bidirectional sync (export WHOOP data to HealthKit) — deferred
- Journal feature (daily notes linked to recovery/sleep context) — deferred
- Workout sport classification (running vs cycling vs strength) — deferred
- ACWR injury risk zone alerts (push notification when ACWR ≥ 1.5) — deferred
- SpO2 windowed ratio-of-ratios (AC=MAD method — Ghidra Phase 33 validation needed) — deferred
- Resp rate spectral estimation via Welch periodogram — deferred

## Out of Scope

- Server-side dashboard or analytics (personal server stores only; no web UI)
- Background URLSession upload when app is suspended
- Full Android app (architecture foundations only in v2.0)
- Clinical calibration of V24 biometrics (uncalibrated flag is a design constraint, not a bug)
- Multi-user support

---

## Traceability

| Requirement | Phase |
|-------------|-------|
| RDY-UI-01 | Phase 36 |
| SLP-UI-01 | Phase 37 |
| BIO-UI-01 | Phase 38 |
| EX-UI-01 | Phase 39 |
| SYNC-UI-01 | Phase 40 |
| STEP-UI-01 | Phase 41 |
| ALG-ALIGN-01 | Phase 42 |
| VAL-01 | Phase 43 |
| VAL-02 | Phase 44 |
